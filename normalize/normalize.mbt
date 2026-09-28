///|
/// Comparison and display helpers for contact values.
///
/// The core library keeps exactly what the card contained. Callers that need to
/// compare, deduplicate or show values usually want a normalized form instead,
/// which is what this package produces. All transformations are ASCII-only,
/// matching the rest of the library: no Unicode case folding, no locale rules.

///|
/// ASCII-lowercased copy of `input`.
pub fn ascii_lower(input : String) -> String {
  let out = StringBuilder()
  for c in input.iter() {
    out.write_char(c.to_ascii_lowercase())
  }
  out.to_string()
}

///|
/// ASCII-uppercased copy of `input`.
pub fn ascii_upper(input : String) -> String {
  let out = StringBuilder()
  for c in input.iter() {
    out.write_char(c.to_ascii_uppercase())
  }
  out.to_string()
}

///|
/// Keeps the ASCII digits of `value` and drops everything else.
pub fn digits_only(value : String) -> String {
  let out = StringBuilder()
  for c in value.iter() {
    if c.is_ascii_digit() {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Comparison key for a phone number: a leading `+` is preserved, every ASCII
/// digit is kept in order, and separators such as spaces, dashes, dots and
/// parentheses are dropped. `+86 139-0000-0002` and `+8613900000002` therefore
/// share one key.
pub fn phone_key(value : String) -> String {
  let out = StringBuilder()
  let trimmed = value.trim()
  if trimmed.has_prefix("+") {
    out.write_char('+')
  }
  for c in trimmed.iter() {
    if c.is_ascii_digit() {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Comparison key for an email address: trimmed and ASCII-lowercased.
/// `Alice@Example.ORG` and `alice@example.org` share one key.
pub fn email_key(value : String) -> String {
  ascii_lower(value.trim().to_owned())
}

///|
/// Comparison key for a person name: ASCII-lowercased, apostrophes, commas,
/// dots and hyphens dropped, and every run of spaces or tabs collapsed into a
/// single space. `Smith-Jones,  Ann` and `smithjones ann` share one key.
pub fn name_key(value : String) -> String {
  let out = StringBuilder()
  let mut pending_space = false
  for c in value.iter() {
    if c == ' ' || c == '\t' {
      pending_space = !out.is_empty()
      continue
    }
    if c == '\'' || c == ',' || c == '.' || c == '-' {
      continue
    }
    if pending_space {
      out.write_char(' ')
      pending_space = false
    }
    out.write_char(c.to_ascii_lowercase())
  }
  out.to_string()
}

///|
/// The first phone key of `contact`, or `""` when the contact has no phone.
pub fn primary_phone_key(contact : @vcard.Contact) -> String {
  if contact.phones.length() == 0 {
    return ""
  }
  phone_key(contact.phones[0].value)
}

///|
/// The first email key of `contact`, or `""` when the contact has no email.
pub fn primary_email_key(contact : @vcard.Contact) -> String {
  if contact.emails.length() == 0 {
    return ""
  }
  email_key(contact.emails[0].value)
}

///|
/// Comparison key for a whole contact: name key, first phone key and first
/// email key joined by `|`. Two cards that describe the same person with the
/// same first phone or email produce the same key.
pub fn contact_key(contact : @vcard.Contact) -> String {
  let parts = [
    name_key(contact.full_name),
    primary_phone_key(contact),
    primary_email_key(contact),
  ]
  parts.join("|")
}

///|
/// True when both contacts produce the same comparison key, that is, they look
/// like two cards for the same person.
pub fn same_person(left : @vcard.Contact, right : @vcard.Contact) -> Bool {
  contact_key(left) == contact_key(right)
}

///|
/// True when the value carries at least `minimum` digits, the usual sanity
/// check for a dialable number. It is a structural check, not validation
/// against numbering plans.
pub fn has_enough_digits(value : String, minimum : Int) -> Bool {
  digits_only(value).length() >= minimum
}

///|
/// True when the value looks like a phone number: at least six digits and no
/// more than one `+`, which must be leading.
pub fn is_plausible_phone(value : String) -> Bool {
  let trimmed = value.trim()
  let mut plus_seen = false
  let mut digits = 0
  let mut index = 0
  for c in trimmed.iter() {
    if c == '+' {
      if plus_seen || index > 0 {
        return false
      }
      plus_seen = true
    } else if c.is_ascii_digit() {
      digits += 1
    }
    index += 1
  }
  digits >= 6
}

///|
/// True when the value looks like an email address: exactly one `@`, a
/// non-empty local part, and a domain that contains a dot and no spaces.
pub fn is_plausible_email(value : String) -> Bool {
  let trimmed = value.trim()
  let parts = trimmed.split("@").to_array()
  if parts.length() != 2 {
    return false
  }
  let local_part = parts[0].to_owned()
  let domain = parts[1].to_owned()
  if local_part == "" || domain == "" {
    return false
  }
  if local_part.contains(" ") || domain.contains(" ") {
    return false
  }
  domain.contains(".")
}

///|
/// Masks a phone number for display: keeps a leading `+` and the last four
/// digits, replaces every other digit with `*`. Short values keep at least two
/// visible digits.
pub fn mask_phone(value : String) -> String {
  let digits = digits_only(value)
  let visible = if digits.length() <= 4 { 2 } else { 4 }
  let hidden = digits.length() - visible
  let out = StringBuilder()
  if value.trim().has_prefix("+") {
    out.write_char('+')
  }
  let mut index = 0
  for c in digits.iter() {
    if index < hidden {
      out.write_char('*')
    } else {
      out.write_char(c)
    }
    index += 1
  }
  out.to_string()
}

///|
/// Masks an email address for display: keeps the first character of the local
/// part and the whole domain, hides the rest of the local part.
pub fn mask_email(value : String) -> String {
  let trimmed = value.trim()
  let parts = trimmed.split("@").to_array()
  if parts.length() != 2 {
    return trimmed.to_owned()
  }
  let local_part = parts[0].to_owned()
  let domain = parts[1].to_owned()
  if local_part.length() == 0 {
    return trimmed.to_owned()
  }
  let out = StringBuilder()
  let chars = local_part.iter().to_array()
  out.write_char(chars[0])
  let mut index = 1
  while index < chars.length() {
    out.write_char('*')
    index += 1
  }
  out.write_char('@')
  out.write_string(domain)
  out.to_string()
}

///|
/// Renders a phone value in groups of four digits for readability, keeping a
/// leading `+`. `+8613900000002` becomes `+8613 9000 0000 2`.
pub fn group_phone(value : String) -> String {
  let key = phone_key(value)
  let out = StringBuilder()
  let mut index = 0
  for c in key.iter() {
    if c == '+' {
      out.write_char('+')
      continue
    }
    if index > 0 && index % 4 == 0 {
      out.write_char(' ')
    }
    out.write_char(c)
    index += 1
  }
  out.to_string()
}

///|
/// Counts how many contacts in `contacts` share the key of `contact`.
pub fn key_count(
  contacts : Array[@vcard.Contact],
  contact : @vcard.Contact,
) -> Int {
  let key = contact_key(contact)
  let mut count = 0
  for other in contacts {
    if contact_key(other) == key {
      count += 1
    }
  }
  count
}
