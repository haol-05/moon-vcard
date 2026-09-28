// JSON codecs between the public vCard model and JSON. The wire shape is
// stable:
//
//   parameter    {"name": String, "values": [String, ...]}
//   field        {"value": String, "params": [parameter, ...]}
//   contact      {"version": String, "full_name": String,
//                 "family_name": String, "given_name": String,
//                 "phones": [field, ...], "emails": [field, ...]}
//   parse result {"contacts": [contact, ...], "diagnostics": [String, ...]}
//
// A decoder answers `None` when a required key is missing or carries the wrong
// JSON type, and ignores keys it does not know about.

///|
/// Object view of a JSON value, or `None` when it is not an object.
fn object_of(value : Json) -> Map[String, Json]? {
  match value {
    Object(fields) => Some(fields)
    _ => None
  }
}

///|
/// String stored under `key`, or `None` when it is absent or not a string.
fn string_at(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
/// Array stored under `key`, or `None` when it is absent or not an array.
fn array_at(fields : Map[String, Json], key : String) -> Array[Json]? {
  match fields.get(key) {
    Some(Array(items)) => Some(items)
    _ => None
  }
}

///|
/// Array of strings stored under `key`, or `None` when it is absent, not an
/// array, or holds an entry that is not a string.
fn strings_at(fields : Map[String, Json], key : String) -> Array[String]? {
  match array_at(fields, key) {
    Some(items) => {
      let result : Array[String] = []
      for item in items {
        match item {
          String(text) => result.push(text)
          _ => return None
        }
      }
      Some(result)
    }
    None => None
  }
}

///|
/// Decodes every entry of `items` with `decode`, giving up at the first
/// failure.
fn[T] decode_each(items : Array[Json], decode : (Json) -> T?) -> Array[T]? {
  let result : Array[T] = []
  for item in items {
    match decode(item) {
      Some(value) => result.push(value)
      None => return None
    }
  }
  Some(result)
}

///|
/// Array stored under `key` with every entry decoded by `decode`.
fn[T] decode_array_at(
  fields : Map[String, Json],
  key : String,
  decode : (Json) -> T?,
) -> Array[T]? {
  match array_at(fields, key) {
    Some(items) => decode_each(items, decode)
    None => None
  }
}

///|
/// JSON array of the encoded parameters.
fn params_to_json(params : Array[@vcard.Param]) -> Json {
  let items : Array[Json] = []
  for param in params {
    items.push(param_to_json(param))
  }
  Json::array(items)
}

///|
/// JSON array of the encoded fields.
fn fields_to_json(fields : Array[@vcard.Field]) -> Json {
  let items : Array[Json] = []
  for field in fields {
    items.push(field_to_json(field))
  }
  Json::array(items)
}

///|
/// Encodes a parameter as `{"name": String, "values": [String, ...]}`, keeping
/// the name casing and every value in order.
pub fn param_to_json(param : @vcard.Param) -> Json {
  Json::object(
    Map([
      ("name", Json::string(param.name)),
      (
        "values",
        Json::array(param.values.map(fn(value) { Json::string(value) })),
      ),
    ]),
  )
}

///|
/// Decodes `{"name": String, "values": [String, ...]}`. `None` when the value
/// is not an object, when `name` is missing or not a string, or when `values`
/// is missing, not an array, or holds a non-string entry.
pub fn json_to_param(value : Json) -> @vcard.Param? {
  guard object_of(value) is Some(fields) else { return None }
  guard string_at(fields, "name") is Some(name) else { return None }
  guard strings_at(fields, "values") is Some(values) else { return None }
  Some({ name, values, })
}

///|
/// Encodes a field as `{"value": String, "params": [parameter, ...]}`.
pub fn field_to_json(field : @vcard.Field) -> Json {
  Json::object(
    Map([
      ("value", Json::string(field.value)),
      ("params", params_to_json(field.params)),
    ]),
  )
}

///|
/// Decodes `{"value": String, "params": [parameter, ...]}`. `None` when the
/// value is not an object, when `value` is missing or not a string, or when
/// `params` is missing, not an array, or holds a parameter that does not
/// decode.
pub fn json_to_field(value : Json) -> @vcard.Field? {
  guard object_of(value) is Some(fields) else { return None }
  guard string_at(fields, "value") is Some(text) else { return None }
  guard decode_array_at(fields, "params", json_to_param) is Some(params) else {
    return None
  }
  Some({ value: text, params, })
}

///|
/// Encodes a contact as an object with `version`, `full_name`, `family_name`,
/// `given_name`, `phones` and `emails`.
pub fn contact_to_json(contact : @vcard.Contact) -> Json {
  Json::object(
    Map([
      ("version", Json::string(contact.version)),
      ("full_name", Json::string(contact.full_name)),
      ("family_name", Json::string(contact.family_name)),
      ("given_name", Json::string(contact.given_name)),
      ("phones", fields_to_json(contact.phones)),
      ("emails", fields_to_json(contact.emails)),
    ]),
  )
}

///|
/// Decodes the contact object described by `contact_to_json`. `None` when the
/// value is not an object, when a key is missing, or when a key carries the
/// wrong JSON type. Extra keys are ignored.
pub fn json_to_contact(value : Json) -> @vcard.Contact? {
  guard object_of(value) is Some(fields) else { return None }
  guard string_at(fields, "version") is Some(version) else { return None }
  guard string_at(fields, "full_name") is Some(full_name) else { return None }
  guard string_at(fields, "family_name") is Some(family_name) else {
    return None
  }
  guard string_at(fields, "given_name") is Some(given_name) else { return None }
  guard decode_array_at(fields, "phones", json_to_field) is Some(phones) else {
    return None
  }
  guard decode_array_at(fields, "emails", json_to_field) is Some(emails) else {
    return None
  }
  Some({ version, full_name, family_name, given_name, phones, emails, })
}

///|
/// Encodes a list of contacts as a JSON array.
pub fn contacts_to_json(contacts : Array[@vcard.Contact]) -> Json {
  let items : Array[Json] = []
  for contact in contacts {
    items.push(contact_to_json(contact))
  }
  Json::array(items)
}

///|
/// Decodes a JSON array of contacts. `None` when the value is not an array or
/// when any entry is not a decodable contact.
pub fn json_to_contacts(value : Json) -> Array[@vcard.Contact]? {
  match value {
    Array(items) => decode_each(items, json_to_contact)
    _ => None
  }
}

///|
/// Encodes a parse result as
/// `{"contacts": [...], "diagnostics": [String, ...]}`.
pub fn parse_result_to_json(result : @vcard.ParseResult) -> Json {
  let diagnostics : Array[Json] = []
  for line in result.diagnostics {
    diagnostics.push(Json::string(line))
  }
  Json::object(
    Map([
      ("contacts", contacts_to_json(result.contacts)),
      ("diagnostics", Json::array(diagnostics)),
    ]),
  )
}

///|
/// Decodes the parse result object described by `parse_result_to_json`. `None`
/// when the value is not an object, when a key is missing, or when a key
/// carries the wrong JSON type. Extra keys are ignored.
pub fn json_to_parse_result(value : Json) -> @vcard.ParseResult? {
  guard object_of(value) is Some(fields) else { return None }
  let entries = decode_array_at(fields, "contacts", json_to_contact)
  guard entries is Some(contacts) else { return None }
  guard strings_at(fields, "diagnostics") is Some(diagnostics) else {
    return None
  }
  Some({ contacts, diagnostics, })
}

///|
/// Writes a contact list as a JSON array. The text is pretty printed when
/// `indent` is `Some(n)`, which indents every level by `n` spaces, and compact
/// otherwise.
pub fn encode_contacts(
  contacts : Array[@vcard.Contact],
  indent? : Int,
) -> String {
  let value = contacts_to_json(contacts)
  match indent {
    Some(width) => value.stringify(indent=width)
    None => value.stringify()
  }
}

///|
/// Reads a contact list written by `encode_contacts`. `None` when `text` is not
/// valid JSON or does not hold an array of well formed contacts.
pub fn decode_contacts(text : String) -> Array[@vcard.Contact]? {
  let value = @json_core.parse(text) catch { _ => return None }
  json_to_contacts(value)
}
