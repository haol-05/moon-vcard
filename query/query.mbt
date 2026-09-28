///|
/// A small filter language for contacts.
///
/// Batch tools rarely want every card: they want the ones with a cell number,
/// a preferred address, or a name they can recognize. This package parses a
/// short expression such as `has:phone,type:cell,-name~test` into terms and
/// tests contacts against them.
///
/// Grammar: terms are separated by commas and all of them must match (AND).
/// A term is `[-]field[operator]value`, where the operator is one of `~`
/// (contains), `=` (equals), `<`, `>`, `<=`, `>=` (numeric, for `pref`), or
/// `:` (alias of `~`, kept for readability). A term without an operator is a
/// free-text search across the usual text fields. A leading `-` negates the
/// term. Values cannot contain commas; there is no quoting.

///|
/// One parsed term.
pub struct Term {
  negated : Bool
  field : String
  op : String
  value : String
} derive(Eq, Debug)

///|
/// A parsed expression: every term has to match.
pub struct Query {
  terms : Array[Term]
  source : String
} derive(Eq, Debug)

///|
pub extend Term with Eq::{not_equal, equal}

///|
pub extend Term with @debug.Debug::{to_repr}

///|
pub extend Query with Eq::{not_equal, equal}

///|
pub extend Query with @debug.Debug::{to_repr}

///|
/// ASCII-lowercased copy of `input`.
fn lower(input : String) -> String {
  @normalize.ascii_lower(input)
}

///|
/// True when `haystack` contains `needle`, ignoring ASCII case.
fn contains_ci(haystack : String, needle : String) -> Bool {
  if needle == "" {
    return true
  }
  lower(haystack).contains(lower(needle))
}

///|
/// True when both strings are equal, ignoring ASCII case and outer spaces.
fn equals_ci(left : String, right : String) -> Bool {
  lower(left.trim().to_owned()) == lower(right.trim().to_owned())
}

///|
/// Reads an operator at `index`, preferring the two-character comparisons.
/// Returns the operator and the index just past it, or `None` without one.
fn operator_at(chars : Array[Char], index : Int) -> (String, Int)? {
  if index >= chars.length() {
    return None
  }
  let c = chars[index]
  if c == '<' || c == '>' {
    let symbol = if c == '<' { "<" } else { ">" }
    if index + 1 < chars.length() && chars[index + 1] == '=' {
      return Some((symbol + "=", index + 2))
    }
    return Some((symbol, index + 1))
  }
  if c == '~' {
    return Some(("~", index + 1))
  }
  if c == '=' {
    return Some(("=", index + 1))
  }
  if c == ':' {
    return Some((":", index + 1))
  }
  None
}

///|
/// Splits one raw term into its parts. A term without an operator becomes a
/// free-text search (`any` with `~`).
fn parse_term(raw : String) -> Term? {
  let trimmed = raw.trim().to_owned()
  if trimmed == "" {
    return None
  }
  let mut negated = false
  let mut text = trimmed
  if text.has_prefix("-") {
    negated = true
    text = text[1:].to_owned()
  }
  let text = text.trim().to_owned()
  if text == "" {
    return None
  }
  let chars = text.iter().to_array()
  let mut index = 0
  while index < chars.length() {
    match operator_at(chars, index) {
      Some((op, next)) => {
        let field = slice(chars, 0, index)
        let value = slice(chars, next, chars.length())
        return Some({
          negated,
          field: lower(field.trim().to_owned()),
          op,
          value: value.trim().to_owned(),
        })
      }
      None => index += 1
    }
  }
  Some({ negated, field: "any", op: "~", value: text, })
}

///|
/// Builds a string from `chars[from:to]`.
fn slice(chars : Array[Char], from : Int, to : Int) -> String {
  let out = StringBuilder()
  let mut index = from
  while index < to && index < chars.length() {
    out.write_char(chars[index])
    index += 1
  }
  out.to_string()
}

///|
/// Parses `text`. Empty terms are ignored; unrecognized text never throws.
pub fn parse(text : String) -> Query {
  let terms : Array[Term] = []
  for piece in text.split(",") {
    match parse_term(piece.to_owned()) {
      Some(term) => terms.push(term)
      None => ()
    }
  }
  { terms, source: text, }
}

///|
/// True when the expression carries no terms (it then matches everything).
pub fn is_empty(query : Query) -> Bool {
  query.terms.length() == 0
}

///|
/// Every phone and email of `contact`.
fn all_fields(contact : @vcard.Contact) -> Array[@vcard.Field] {
  let fields : Array[@vcard.Field] = []
  for field in contact.phones {
    fields.push(field)
  }
  for field in contact.emails {
    fields.push(field)
  }
  fields
}

///|
/// True when any field carries a parameter named `name` whose values match
/// `value` (contains, ignoring ASCII case).
fn has_param_value(
  contact : @vcard.Contact,
  name : String,
  value : String,
) -> Bool {
  for field in all_fields(contact) {
    for param in field.params {
      if equals_ci(param.name, name) {
        for item in param.values {
          if contains_ci(item, value) {
            return true
          }
        }
      }
    }
  }
  false
}

///|
/// True when any field carries a parameter named `name`.
fn has_param(contact : @vcard.Contact, name : String) -> Bool {
  has_param_value(contact, name, "")
}

///|
/// Smallest numeric `PREF` of the contact, or `None` without one.
fn min_preference(contact : @vcard.Contact) -> Int? {
  let mut best : Int? = None
  for field in all_fields(contact) {
    for param in field.params {
      if equals_ci(param.name, "PREF") {
        for item in param.values {
          let text = item.trim().to_owned()
          let digits = @normalize.digits_only(text)
          if digits != "" && digits.length() == text.length() {
            let number = parse_int(digits)
            match best {
              Some(current) => if number < current { best = Some(number) }
              None => best = Some(number)
            }
          }
        }
      }
    }
  }
  best
}

///|
/// Reads a non-negative decimal integer.
fn parse_int(digits : String) -> Int {
  let mut value = 0
  for c in digits.iter() {
    if c.is_ascii_digit() {
      value = value * 10 + (Char::to_int(c) - Char::to_int('0'))
    }
  }
  value
}

///|
/// True when any phone or email value matches `value` on its digits. A value
/// without digits never matches here; the empty case is handled by the caller.
fn any_phone_matches(contact : @vcard.Contact, value : String) -> Bool {
  let needle = @normalize.digits_only(value)
  if needle == "" {
    return false
  }
  for field in contact.phones {
    if @normalize.digits_only(field.value).contains(needle) {
      return true
    }
  }
  false
}

///|
/// True when any email value matches `value` as text.
fn any_email_matches(contact : @vcard.Contact, value : String) -> Bool {
  for field in contact.emails {
    if contains_ci(field.value, value) {
      return true
    }
  }
  false
}

///|
/// True when any text field of the contact matches `value`.
fn any_text_matches(contact : @vcard.Contact, value : String) -> Bool {
  if contains_ci(contact.full_name, value) {
    return true
  }
  if contains_ci(contact.family_name, value) {
    return true
  }
  if contains_ci(contact.given_name, value) {
    return true
  }
  if contains_ci(contact.version, value) {
    return true
  }
  if any_phone_matches(contact, value) {
    return true
  }
  any_email_matches(contact, value)
}

///|
/// Evaluates one term against one contact.
pub fn term_matches(term : Term, contact : @vcard.Contact) -> Bool {
  let result = match term.field {
    "any" => any_text_matches(contact, term.value)
    "name" => text_compare(contact.full_name, term.op, term.value)
    "family" => text_compare(contact.family_name, term.op, term.value)
    "given" => text_compare(contact.given_name, term.op, term.value)
    "version" => text_compare(contact.version, term.op, term.value)
    "phone" =>
      if term.value.trim().to_owned() == "" {
        contact.phones.length() > 0
      } else if term.op == "=" {
        any_phone_equals(contact, term.value)
      } else {
        any_phone_matches(contact, term.value)
      }
    "email" =>
      if term.op == "=" {
        any_email_equals(contact, term.value)
      } else {
        any_email_matches(contact, term.value)
      }
    "type" => has_param_value(contact, "TYPE", term.value)
    "pref" => preference_matches(contact, term.op, term.value)
    "has" => has_channel(contact, term.value)
    _ => false
  }
  if term.negated {
    !result
  } else {
    result
  }
}

///|
/// Contains or equals on a text field.
fn text_compare(text : String, op : String, value : String) -> Bool {
  if op == "=" {
    equals_ci(text, value)
  } else {
    contains_ci(text, value)
  }
}

///|
/// True when any phone value equals `value` after both are keyed.
fn any_phone_equals(contact : @vcard.Contact, value : String) -> Bool {
  let needle = @normalize.phone_key(value)
  for field in contact.phones {
    if @normalize.phone_key(field.value) == needle {
      return true
    }
  }
  false
}

///|
/// True when any email value equals `value` after both are keyed.
fn any_email_equals(contact : @vcard.Contact, value : String) -> Bool {
  let needle = @normalize.email_key(value)
  for field in contact.emails {
    if @normalize.email_key(field.value) == needle {
      return true
    }
  }
  false
}

///|
/// Numeric comparison against the smallest `PREF` of the contact.
fn preference_matches(
  contact : @vcard.Contact,
  op : String,
  value : String,
) -> Bool {
  let wanted = parse_int(@normalize.digits_only(value))
  match min_preference(contact) {
    Some(current) =>
      if op == "<" {
        current < wanted
      } else if op == "<=" {
        current <= wanted
      } else if op == ">" {
        current > wanted
      } else if op == ">=" {
        current >= wanted
      } else {
        current == wanted
      }
    None => false
  }
}

///|
/// Implements `has:phone`, `has:email`, `has:pref` and `has:type`.
fn has_channel(contact : @vcard.Contact, value : String) -> Bool {
  let wanted = lower(value.trim().to_owned())
  if wanted == "phone" {
    contact.phones.length() > 0
  } else if wanted == "email" {
    contact.emails.length() > 0
  } else if wanted == "pref" {
    has_param(contact, "PREF")
  } else if wanted == "type" {
    has_param(contact, "TYPE")
  } else {
    false
  }
}

///|
/// True when every term matches the contact. An empty query matches everything.
pub fn matches(query : Query, contact : @vcard.Contact) -> Bool {
  for term in query.terms {
    if !term_matches(term, contact) {
      return false
    }
  }
  true
}

///|
/// Keeps the contacts matching `text`, preserving their order.
pub fn filter(
  contacts : Array[@vcard.Contact],
  text : String,
) -> Array[@vcard.Contact] {
  let query = parse(text)
  let kept : Array[@vcard.Contact] = []
  for contact in contacts {
    if matches(query, contact) {
      kept.push(contact)
    }
  }
  kept
}

///|
/// Renders one term back to text.
pub fn term_text(term : Term) -> String {
  let prefix = if term.negated { "-" } else { "" }
  if term.field == "any" && term.op == "~" {
    return prefix + term.value
  }
  prefix + term.field + term.op + term.value
}

///|
/// Renders the expression back to text, joining terms with ` AND `.
pub fn describe(query : Query) -> String {
  if is_empty(query) {
    return "any"
  }
  let parts : Array[String] = []
  for term in query.terms {
    parts.push(term_text(term))
  }
  parts.join(" AND ")
}
