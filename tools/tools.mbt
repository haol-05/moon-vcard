///|
/// Set-level operations on parsed contacts: statistics, duplicate detection,
/// merging, searching, sorting and diffing.
///
/// One design note matters for every function here. `Contact` is a read-only
/// type outside the core package, so this package never fabricates one by hand:
/// when an operation has to produce a derived contact (a merged duplicate, for
/// example) it renders canonical vCard text and feeds it back through
/// `parse`. Derived contacts are therefore always structurally valid cards, and
/// parameter data survives the round trip.

///|
/// Counts and histograms over a set of contacts.
pub struct Stats {
  total : Int
  with_phone : Int
  with_email : Int
  phones : Int
  emails : Int
  versions : Array[VersionCount]
  duplicate_groups : Int
} derive(Eq, Debug)

///|
/// How many contacts carry one card version.
pub struct VersionCount {
  version : String
  count : Int
} derive(Eq, Debug)

///|
/// Contacts that share one comparison key.
pub struct DuplicateGroup {
  key : String
  indices : Array[Int]
} derive(Eq, Debug)

///|
/// Result of comparing two sets of contacts by identity keys.
pub struct Diff {
  added : Array[@vcard.Contact]
  removed : Array[@vcard.Contact]
  changed : Array[@vcard.Contact]
  unchanged : Array[@vcard.Contact]
} derive(Eq, Debug)

///|
pub extend Stats with Eq::{not_equal, equal}

///|
pub extend Stats with @debug.Debug::{to_repr}

///|
pub extend VersionCount with Eq::{not_equal, equal}

///|
pub extend VersionCount with @debug.Debug::{to_repr}

///|
pub extend DuplicateGroup with Eq::{not_equal, equal}

///|
pub extend DuplicateGroup with @debug.Debug::{to_repr}

///|
pub extend Diff with Eq::{not_equal, equal}

///|
pub extend Diff with @debug.Debug::{to_repr}

///|
/// Escapes a value for vCard text output: backslash, newline, semicolon and
/// comma, the same rules the core writer applies.
fn escape(value : String) -> String {
  let out = StringBuilder()
  for c in value.iter() {
    match c {
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      ';' => out.write_string("\\;")
      ',' => out.write_string("\\,")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Renders the parameter text of one field, including the leading semicolons.
fn render_params(field : @vcard.Field) -> String {
  let out = StringBuilder()
  for param in field.params {
    out.write_char(';')
    out.write_string(param.name)
    if param.values.length() > 0 {
      out.write_char('=')
      out.write_string(param.values.join(","))
    }
  }
  out.to_string()
}

///|
/// Renders one field line (`TEL...`) ended by CRLF.
fn render_field(name : String, field : @vcard.Field) -> String {
  name + render_params(field) + ":" + escape(field.value) + "\r\n"
}

///|
/// Renders a contact as canonical CRLF-terminated vCard text. This mirrors the
/// core writer and adds nothing the core would not write.
pub fn render_contact_text(contact : @vcard.Contact) -> String {
  let out = StringBuilder()
  out.write_string("BEGIN:VCARD\r\nVERSION:")
  out.write_string(contact.version)
  out.write_string("\r\nFN:")
  out.write_string(escape(contact.full_name))
  out.write_string("\r\nN:")
  out.write_string(escape(contact.family_name))
  out.write_string(";")
  out.write_string(escape(contact.given_name))
  out.write_string(";;;\r\n")
  for field in contact.phones {
    out.write_string(render_field("TEL", field))
  }
  for field in contact.emails {
    out.write_string(render_field("EMAIL", field))
  }
  out.write_string("END:VCARD\r\n")
  out.to_string()
}

///|
/// Renders several contacts as one text block.
pub fn render_contacts_text(contacts : Array[@vcard.Contact]) -> String {
  let out = StringBuilder()
  for contact in contacts {
    out.write_string(render_contact_text(contact))
  }
  out.to_string()
}

///|
/// Lexicographic comparison by code unit. MoonBit's `String` comparison is not
/// a plain code-unit order, so ordering helpers use this instead.
pub fn text_less(left : String, right : String) -> Bool {
  let a = left.iter().to_array()
  let b = right.iter().to_array()
  let mut index = 0
  while index < a.length() && index < b.length() {
    if a[index] != b[index] {
      return Char::to_int(a[index]) < Char::to_int(b[index])
    }
    index += 1
  }
  a.length() < b.length()
}

///|
/// Identity keys of one card: phone keys and email keys, or the name key when
/// the card carries no channel. Two cards that share a key describe the same
/// person.
pub fn identity_keys(contact : @vcard.Contact) -> Array[String] {
  let keys : Array[String] = []
  for field in contact.phones {
    let key = @normalize.phone_key(field.value)
    if key != "" {
      let tagged = "phone:" + key
      if !keys.contains(tagged) {
        keys.push(tagged)
      }
    }
  }
  for field in contact.emails {
    let key = @normalize.email_key(field.value)
    if key != "" {
      let tagged = "email:" + key
      if !keys.contains(tagged) {
        keys.push(tagged)
      }
    }
  }
  if keys.length() == 0 {
    let key = @normalize.name_key(contact.full_name)
    if key != "" {
      keys.push("name:" + key)
    }
  }
  keys
}

///|
/// True when both cards share at least one identity key, which is the rule this
/// package uses for "same person". A missing name or a different spelling does
/// not prevent a match as long as one phone or email agrees.
pub fn same_person(left : @vcard.Contact, right : @vcard.Contact) -> Bool {
  let keys = identity_keys(left)
  for key in identity_keys(right) {
    if keys.contains(key) {
      return true
    }
  }
  false
}

///|
/// True when `value` is a non-empty string.
fn filled(value : String) -> Bool {
  value != ""
}

///|
/// Picks the first non-empty of two values.
fn prefer(left : String, right : String) -> String {
  if filled(left) {
    left
  } else {
    right
  }
}

///|
/// Appends `field` unless a field with the same comparison key is present.
fn push_unique(
  fields : Array[@vcard.Field],
  field : @vcard.Field,
  key_of : (@vcard.Field) -> String,
) -> Unit {
  let key = key_of(field)
  for existing in fields {
    if key_of(existing) == key {
      return
    }
  }
  fields.push(field)
}

///|
/// Union of the phones of both contacts, keeping the left order first.
fn union_phones(
  left : @vcard.Contact,
  right : @vcard.Contact,
) -> Array[@vcard.Field] {
  let out : Array[@vcard.Field] = []
  for field in left.phones {
    push_unique(out, field, fn(f) { @normalize.phone_key(f.value) })
  }
  for field in right.phones {
    push_unique(out, field, fn(f) { @normalize.phone_key(f.value) })
  }
  out
}

///|
/// Union of the emails of both contacts, keeping the left order first.
fn union_emails(
  left : @vcard.Contact,
  right : @vcard.Contact,
) -> Array[@vcard.Field] {
  let out : Array[@vcard.Field] = []
  for field in left.emails {
    push_unique(out, field, fn(f) { @normalize.email_key(f.value) })
  }
  for field in right.emails {
    push_unique(out, field, fn(f) { @normalize.email_key(f.value) })
  }
  out
}

///|
/// Renders the vCard text of the union of two contacts: non-empty name fields
/// win from the left side, and phone and email channels are merged without
/// duplicates. The text form is useful for diffing and for exports.
pub fn merge_text(left : @vcard.Contact, right : @vcard.Contact) -> String {
  render_contact_text(merge(left, right))
}

///|
/// Merges two contacts: non-empty name fields win from the left side, and
/// phone and email channels are merged without duplicates, keeping the left
/// order first.
pub fn merge(left : @vcard.Contact, right : @vcard.Contact) -> @vcard.Contact {
  {
    version: prefer(left.version, right.version),
    full_name: prefer(left.full_name, right.full_name),
    family_name: prefer(left.family_name, right.family_name),
    given_name: prefer(left.given_name, right.given_name),
    phones: union_phones(left, right),
    emails: union_emails(left, right),
  }
}

///|
/// Merges every contact of `group` into one, left to right. Returns `None` for
/// an empty group.
pub fn merge_group(group : Array[@vcard.Contact]) -> @vcard.Contact? {
  if group.length() == 0 {
    return None
  }
  let mut current = group[0]
  let mut index = 1
  while index < group.length() {
    current = merge(current, group[index])
    index += 1
  }
  Some(current)
}

///|
/// Groups contacts that describe the same person. Membership is transitive: a
/// card sharing a phone with one member and an email with another joins the
/// same group. Single-member groups are not reported.
pub fn duplicate_groups(
  contacts : Array[@vcard.Contact],
) -> Array[DuplicateGroup] {
  let groups : Array[Array[Int]] = []
  let mut index = 0
  while index < contacts.length() {
    let merged : Array[Int] = [index]
    let remaining : Array[Array[Int]] = []
    for group in groups {
      let mut connected = false
      for slot in group {
        if same_person(contacts[index], contacts[slot]) {
          connected = true
        }
      }
      if connected {
        for slot in group {
          merged.push(slot)
        }
      } else {
        remaining.push(group)
      }
    }
    remaining.push(merged)
    groups.clear()
    for group in remaining {
      groups.push(group)
    }
    index += 1
  }
  let reported : Array[DuplicateGroup] = []
  for group in groups {
    if group.length() > 1 {
      let sorted = sorted_indices(group)
      let first = sorted[0]
      reported.push({
        key: @normalize.contact_key(contacts[first]),
        indices: sorted,
      })
    }
  }
  let ordered : Array[DuplicateGroup] = []
  for entry in reported {
    let mut position = ordered.length()
    let mut cursor = ordered.length()
    while cursor > 0 {
      cursor -= 1
      if entry.indices[0] < ordered[cursor].indices[0] {
        position = cursor
      } else {
        break
      }
    }
    ordered.insert(position, entry)
  }
  ordered
}

///|
/// Ascending copy of a small index list.
fn sorted_indices(indices : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for value in indices {
    let mut position = out.length()
    let mut index = out.length()
    while index > 0 {
      index -= 1
      if value < out[index] {
        position = index
      } else {
        break
      }
    }
    out.insert(position, value)
  }
  out
}

///|
/// True when the two contacts describe the same person.
fn same_key(left : @vcard.Contact, right : @vcard.Contact) -> Bool {
  same_person(left, right)
}

///|
/// Drops duplicate cards, merging each duplicate group into its first member
/// and keeping the original order of first appearances.
pub fn dedupe(contacts : Array[@vcard.Contact]) -> Array[@vcard.Contact] {
  let groups = duplicate_groups(contacts)
  let merged : Array[@vcard.Contact?] = []
  let mut index = 0
  while index < contacts.length() {
    merged.push(None)
    index += 1
  }
  for group in groups {
    let members : Array[@vcard.Contact] = []
    for position in group.indices {
      members.push(contacts[position])
    }
    match merge_group(members) {
      Some(contact) => merged[group.indices[0]] = Some(contact)
      None => ()
    }
  }
  let out : Array[@vcard.Contact] = []
  let mut position = 0
  while position < contacts.length() {
    let mut skip = false
    for group in groups {
      let first = group.indices[0]
      if position != first && group.indices.contains(position) {
        skip = true
      }
    }
    if !skip {
      match merged[position] {
        Some(contact) => out.push(contact)
        None => out.push(contacts[position])
      }
    }
    position += 1
  }
  out
}

///|
/// Keeps contacts that carry at least one phone number.
pub fn with_phone(contacts : Array[@vcard.Contact]) -> Array[@vcard.Contact] {
  let out : Array[@vcard.Contact] = []
  for contact in contacts {
    if contact.phones.length() > 0 {
      out.push(contact)
    }
  }
  out
}

///|
/// Keeps contacts that carry at least one email address.
pub fn with_email(contacts : Array[@vcard.Contact]) -> Array[@vcard.Contact] {
  let out : Array[@vcard.Contact] = []
  for contact in contacts {
    if contact.emails.length() > 0 {
      out.push(contact)
    }
  }
  out
}

///|
/// Keeps contacts that have a name plus at least one channel, the shape an
/// address book import needs.
pub fn complete_only(contacts : Array[@vcard.Contact]) -> Array[@vcard.Contact] {
  let out : Array[@vcard.Contact] = []
  for contact in contacts {
    if filled(contact.full_name) &&
      (contact.phones.length() > 0 || contact.emails.length() > 0) {
      out.push(contact)
    }
  }
  out
}

///|
/// Free-text search across names, phones and emails, ignoring ASCII case. Use
/// `@query.filter` for structured expressions.
pub fn search(
  contacts : Array[@vcard.Contact],
  text : String,
) -> Array[@vcard.Contact] {
  let needle = @normalize.ascii_lower(text.trim().to_owned())
  if needle == "" {
    return contacts.copy()
  }
  let digits = @normalize.digits_only(needle)
  let out : Array[@vcard.Contact] = []
  for contact in contacts {
    let mut hit = @normalize.ascii_lower(contact.full_name).contains(needle)
    if !hit {
      hit = @normalize.ascii_lower(contact.family_name).contains(needle)
    }
    if !hit {
      hit = @normalize.ascii_lower(contact.given_name).contains(needle)
    }
    for field in contact.phones {
      if @normalize.ascii_lower(field.value).contains(needle) {
        hit = true
      }
      if digits != "" && @normalize.digits_only(field.value).contains(digits) {
        hit = true
      }
    }
    for field in contact.emails {
      if @normalize.ascii_lower(field.value).contains(needle) {
        hit = true
      }
    }
    if hit {
      out.push(contact)
    }
  }
  out
}

///|
/// Filters contacts with a structured expression, for example
/// `has:email,type=cell`. The expression language lives in
/// `haol-05/moon-vcard/query`.
pub fn filter(
  contacts : Array[@vcard.Contact],
  expression : String,
) -> Array[@vcard.Contact] {
  @query.filter(contacts, expression)
}

///|
/// True when `left` sorts before `right` by name key, then by full name.
fn name_before(left : @vcard.Contact, right : @vcard.Contact) -> Bool {
  let a = @normalize.name_key(left.full_name)
  let b = @normalize.name_key(right.full_name)
  if a != b {
    return text_less(a, b)
  }
  text_less(left.full_name, right.full_name)
}

///|
/// Returns a copy ordered by name key using a stable insertion pass, so cards
/// with equal names keep their original order.
pub fn sort_by_name(contacts : Array[@vcard.Contact]) -> Array[@vcard.Contact] {
  let out : Array[@vcard.Contact] = []
  for contact in contacts {
    let mut position = out.length()
    let mut index = out.length()
    while index > 0 {
      index -= 1
      if name_before(contact, out[index]) {
        position = index
      } else {
        break
      }
    }
    out.insert(position, contact)
  }
  out
}

///|
/// Counts contacts per card version, ordered by version text.
pub fn count_by_version(
  contacts : Array[@vcard.Contact],
) -> Array[VersionCount] {
  let versions : Array[String] = []
  for contact in contacts {
    if !versions.contains(contact.version) {
      versions.push(contact.version)
    }
  }
  let sorted : Array[String] = []
  for version in versions {
    let mut position = sorted.length()
    let mut index = sorted.length()
    while index > 0 {
      index -= 1
      if text_less(version, sorted[index]) {
        position = index
      } else {
        break
      }
    }
    sorted.insert(position, version)
  }
  let out : Array[VersionCount] = []
  for version in sorted {
    let mut count = 0
    for contact in contacts {
      if contact.version == version {
        count += 1
      }
    }
    out.push({ version, count, })
  }
  out
}

///|
/// Distinct phone values in first-seen order, keyed on the comparison key.
pub fn unique_phones(contacts : Array[@vcard.Contact]) -> Array[String] {
  let out : Array[String] = []
  let keys : Array[String] = []
  for contact in contacts {
    for field in contact.phones {
      let key = @normalize.phone_key(field.value)
      if key != "" && !keys.contains(key) {
        keys.push(key)
        out.push(field.value)
      }
    }
  }
  out
}

///|
/// Distinct email values in first-seen order, keyed on the comparison key.
pub fn unique_emails(contacts : Array[@vcard.Contact]) -> Array[String] {
  let out : Array[String] = []
  let keys : Array[String] = []
  for contact in contacts {
    for field in contact.emails {
      let key = @normalize.email_key(field.value)
      if key != "" && !keys.contains(key) {
        keys.push(key)
        out.push(field.value)
      }
    }
  }
  out
}

///|
/// Summarizes a contact set.
pub fn stats(contacts : Array[@vcard.Contact]) -> Stats {
  let mut with_phone_count = 0
  let mut with_email_count = 0
  let mut phones = 0
  let mut emails = 0
  for contact in contacts {
    if contact.phones.length() > 0 {
      with_phone_count += 1
    }
    if contact.emails.length() > 0 {
      with_email_count += 1
    }
    phones += contact.phones.length()
    emails += contact.emails.length()
  }
  {
    total: contacts.length(),
    with_phone: with_phone_count,
    with_email: with_email_count,
    phones,
    emails,
    versions: count_by_version(contacts),
    duplicate_groups: duplicate_groups(contacts).length(),
  }
}

///|
/// Compares two contact sets by identity. A card present in both sets is
/// `unchanged` when its rendered text is identical and `changed` otherwise, so
/// callers can tell an edited card from a new one.
pub fn diff(
  before : Array[@vcard.Contact],
  after : Array[@vcard.Contact],
) -> Diff {
  let added : Array[@vcard.Contact] = []
  let removed : Array[@vcard.Contact] = []
  let changed : Array[@vcard.Contact] = []
  let unchanged : Array[@vcard.Contact] = []
  for contact in after {
    let mut matched = false
    for previous in before {
      if same_key(previous, contact) {
        matched = true
        if render_contact_text(previous) == render_contact_text(contact) {
          unchanged.push(contact)
        } else {
          changed.push(contact)
        }
      }
    }
    if !matched {
      added.push(contact)
    }
  }
  for previous in before {
    let mut matched = false
    for contact in after {
      if same_key(previous, contact) {
        matched = true
      }
    }
    if !matched {
      removed.push(previous)
    }
  }
  { added, removed, changed, unchanged, }
}

///|
/// Renders statistics as plain text lines.
pub fn render_stats(value : Stats) -> String {
  let out = StringBuilder()
  out.write_string("contacts: " + value.total.to_string() + "\n")
  out.write_string("with phone: " + value.with_phone.to_string() + "\n")
  out.write_string("with email: " + value.with_email.to_string() + "\n")
  out.write_string("phone entries: " + value.phones.to_string() + "\n")
  out.write_string("email entries: " + value.emails.to_string() + "\n")
  out.write_string(
    "duplicate groups: " + value.duplicate_groups.to_string() + "\n",
  )
  for entry in value.versions {
    out.write_string(
      "version " + entry.version + ": " + entry.count.to_string() + "\n",
    )
  }
  out.to_string()
}

///|
/// Renders one duplicate group with one line per member.
pub fn render_group(
  contacts : Array[@vcard.Contact],
  group : DuplicateGroup,
) -> String {
  let out = StringBuilder()
  out.write_string("key " + group.key + "\n")
  for index in group.indices {
    out.write_string("  " + contacts[index].full_name + "\n")
  }
  out.to_string()
}

///|
/// Renders every duplicate group.
pub fn render_groups(
  contacts : Array[@vcard.Contact],
  groups : Array[DuplicateGroup],
) -> String {
  let out = StringBuilder()
  for group in groups {
    out.write_string(render_group(contacts, group))
  }
  out.to_string()
}

///|
/// Renders a diff summary plus one line per added, removed and changed card.
pub fn render_diff(value : Diff) -> String {
  let out = StringBuilder()
  out.write_string("added: " + value.added.length().to_string() + "\n")
  out.write_string("removed: " + value.removed.length().to_string() + "\n")
  out.write_string("changed: " + value.changed.length().to_string() + "\n")
  out.write_string("unchanged: " + value.unchanged.length().to_string() + "\n")
  for contact in value.added {
    out.write_string("+ " + contact.full_name + "\n")
  }
  for contact in value.removed {
    out.write_string("- " + contact.full_name + "\n")
  }
  for contact in value.changed {
    out.write_string("~ " + contact.full_name + "\n")
  }
  out.to_string()
}
