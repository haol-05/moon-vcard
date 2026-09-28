// Tests build every input through `@vcard.parse` and check both directions of
// each codec, including wrong shapes, extra keys and pretty printing.

///|
/// Parses a card with a phone and an email and returns its only contact.
fn sample_contact() -> @vcard.Contact {
  let text = "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\n" +
    "TEL;TYPE=cell,voice;PREF=1:+100\n" +
    "EMAIL;TYPE=work:alice@example.org\n" +
    "END:VCARD"
  @vcard.parse(text).contacts[0]
}

///|
/// Parses a card whose only multi-value field is a phone number.
fn phone_only_contact() -> @vcard.Contact {
  let text = "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\n" +
    "TEL;TYPE=cell,voice;PREF=1:+100\nEND:VCARD"
  @vcard.parse(text).contacts[0]
}

///|
/// Parameters of the sample card's phone field: `TYPE` and `PREF`.
fn sample_params() -> Array[@vcard.Param] {
  phone_only_contact().phones[0].params
}

///|
/// Parameters of a card whose phone carries a bare `PREF` without a value.
fn bare_params() -> Array[@vcard.Param] {
  let text = "BEGIN:VCARD\nVERSION:4.0\nFN:Bare\nN:Bare;;;;\n" +
    "TEL;PREF:+1\nEND:VCARD"
  @vcard.parse(text).contacts[0].phones[0].params
}

///|
test "param encoder writes the name and every value" {
  match @json.param_to_json(sample_params()[0]) {
    Object(fields) => {
      assert_true(fields.get("name") == Some(Json::string("TYPE")))
      assert_true(
        fields.get("values") ==
        Some(Json::array([Json::string("cell"), Json::string("voice")])),
      )
    }
    _ => fail("expected a JSON object")
  }
}

///|
test "param JSON round trip keeps name and values" {
  for param in sample_params() {
    let value = @json.param_to_json(param)
    assert_true(@json.json_to_param(value) == Some(param))
  }
}

///|
test "bare parameter JSON round trip keeps the empty value list" {
  let param = bare_params()[0]
  assert_eq(param.values.length(), 0)
  assert_true(@json.json_to_param(@json.param_to_json(param)) == Some(param))
}

///|
test "param decoder rejects a value that is not an object" {
  assert_true(@json.json_to_param(Json::boolean(true)) is None)
  assert_true(@json.json_to_param(Json::null()) is None)
  assert_true(@json.json_to_param(Json::array([])) is None)
}

///|
test "param decoder rejects an object without a name" {
  let value = Json::object(Map([("values", Json::array([]))]))
  assert_true(@json.json_to_param(value) is None)
}

///|
test "param decoder rejects a name of the wrong JSON type" {
  let value = Json::object(
    Map([("name", Json::number(1.0)), ("values", Json::array([]))]),
  )
  assert_true(@json.json_to_param(value) is None)
}

///|
test "param decoder rejects values that are not an array" {
  let value = Json::object(
    Map([("name", Json::string("TYPE")), ("values", Json::string("cell"))]),
  )
  assert_true(@json.json_to_param(value) is None)
}

///|
test "param decoder rejects a non-string value entry" {
  let value = Json::object(
    Map([
      ("name", Json::string("TYPE")),
      ("values", Json::array([Json::string("cell"), Json::number(2.0)])),
    ]),
  )
  assert_true(@json.json_to_param(value) is None)
}

///|
test "param decoder ignores extra keys" {
  let value = Json::object(
    Map([
      ("name", Json::string("TYPE")),
      ("values", Json::array([Json::string("cell")])),
      ("x-note", Json::boolean(true)),
    ]),
  )
  match @json.json_to_param(value) {
    Some(param) => {
      assert_eq(param.name, "TYPE")
      assert_eq(param.values, ["cell"])
    }
    None => fail("expected the parameter to decode")
  }
}

///|
test "field encoder writes the value and the parameters" {
  match @json.field_to_json(phone_only_contact().phones[0]) {
    Object(fields) => {
      assert_true(fields.get("value") == Some(Json::string("+100")))
      match fields.get("params") {
        Some(Array(items)) => assert_eq(items.length(), 2)
        _ => fail("expected a JSON array of parameters")
      }
    }
    _ => fail("expected a JSON object")
  }
}

///|
test "field JSON round trip keeps every parameter" {
  let field = sample_contact().phones[0]
  assert_true(@json.json_to_field(@json.field_to_json(field)) == Some(field))
}

///|
test "field decoder rejects a value that is not an object" {
  assert_true(@json.json_to_field(Json::string("+100")) is None)
}

///|
test "field decoder rejects a missing value key" {
  let value = Json::object(Map([("params", Json::array([]))]))
  assert_true(@json.json_to_field(value) is None)
}

///|
test "field decoder rejects params that are not an array" {
  let value = Json::object(
    Map([("value", Json::string("+100")), ("params", Json::boolean(true))]),
  )
  assert_true(@json.json_to_field(value) is None)
}

///|
test "field decoder rejects a parameter of the wrong shape" {
  let bad = Json::object(Map([("name", Json::string("TYPE"))]))
  let value = Json::object(
    Map([("value", Json::string("+100")), ("params", Json::array([bad]))]),
  )
  assert_true(@json.json_to_field(value) is None)
}

///|
test "contact JSON round trip" {
  let contact = sample_contact()
  let value = @json.contact_to_json(contact)
  assert_true(@json.json_to_contact(value) == Some(contact))
}

///|
test "contact encoder writes all six keys" {
  match @json.contact_to_json(sample_contact()) {
    Object(fields) => {
      assert_true(fields.get("version") == Some(Json::string("4.0")))
      assert_true(fields.get("full_name") == Some(Json::string("Alice Smith")))
      assert_true(fields.get("family_name") == Some(Json::string("Smith")))
      assert_true(fields.get("given_name") == Some(Json::string("Alice")))
      match (fields.get("phones"), fields.get("emails")) {
        (Some(Array(phones)), Some(Array(emails))) => {
          assert_eq(phones.length(), 1)
          assert_eq(emails.length(), 1)
        }
        _ => fail("expected the phone and email arrays")
      }
    }
    _ => fail("expected a JSON object")
  }
}

///|
test "contact decoder rejects an array" {
  assert_true(@json.json_to_contact(Json::array([])) is None)
}

///|
test "contact decoder rejects an object with a missing key" {
  let value = Json::object(Map([("version", Json::string("4.0"))]))
  assert_true(@json.json_to_contact(value) is None)
}

///|
test "contact decoder rejects a wrongly typed key" {
  let value = Json::object(
    Map([
      ("version", Json::string("4.0")),
      ("full_name", Json::string("Alice")),
      ("family_name", Json::string("Smith")),
      ("given_name", Json::string("Alice")),
      ("phones", Json::string("+100")),
      ("emails", Json::array([])),
    ]),
  )
  assert_true(@json.json_to_contact(value) is None)
}

///|
test "contact decoder ignores extra keys" {
  let contact = phone_only_contact()
  let value = Json::object(
    Map([
      ("version", Json::string(contact.version)),
      ("full_name", Json::string(contact.full_name)),
      ("family_name", Json::string(contact.family_name)),
      ("given_name", Json::string(contact.given_name)),
      ("phones", Json::array([@json.field_to_json(contact.phones[0])])),
      ("emails", Json::array([])),
      ("x-extra", Json::boolean(true)),
    ]),
  )
  assert_true(@json.json_to_contact(value) == Some(contact))
}

///|
test "contacts array round trip" {
  let contacts = [sample_contact(), phone_only_contact()]
  let value = @json.contacts_to_json(contacts)
  assert_true(@json.json_to_contacts(value) == Some(contacts))
}

///|
test "json_to_contacts rejects a value that is not an array" {
  assert_true(@json.json_to_contacts(Json::object(Map([]))) is None)
}

///|
test "json_to_contacts rejects an entry that is not a contact" {
  let value = Json::array([Json::number(1.0)])
  assert_true(@json.json_to_contacts(value) is None)
}

///|
test "empty contact list is an empty JSON array" {
  assert_eq(@json.encode_contacts([]), "[]")
  let empty : Array[@vcard.Contact] = []
  assert_true(@json.json_to_contacts(Json::array([])) == Some(empty))
}

///|
test "encode_contacts writes a compact array" {
  let contacts = [sample_contact()]
  let text = @json.encode_contacts(contacts)
  assert_true(!text.contains("\n"))
  assert_true(text.has_prefix("["))
  assert_true(text.has_suffix("]"))
  assert_true(text.contains("\"full_name\""))
  assert_true(@json.decode_contacts(text) == Some(contacts))
}

///|
test "encode_contacts pretty prints when indent is given" {
  let contacts = [sample_contact(), phone_only_contact()]
  let text = @json.encode_contacts(contacts, indent=2)
  assert_true(text.contains("\n"))
  assert_true(text.contains("  \"version\": "))
  assert_true(text.contains("  \"params\": ["))
  assert_true(@json.decode_contacts(text) == Some(contacts))
}

///|
test "decode_contacts rejects malformed JSON text" {
  assert_true(@json.decode_contacts("{not json") is None)
  assert_true(@json.decode_contacts("") is None)
}

///|
test "decode_contacts rejects an object instead of an array" {
  assert_true(@json.decode_contacts("{}") is None)
}

///|
test "decode_contacts rejects an array of wrong shapes" {
  assert_true(@json.decode_contacts("[1, 2]") is None)
  assert_true(@json.decode_contacts("[{}]") is None)
}

///|
test "decode_contacts keeps parameters through encode and decode" {
  let contacts = [sample_contact()]
  match @json.decode_contacts(@json.encode_contacts(contacts)) {
    Some(decoded) => {
      assert_eq(decoded.length(), 1)
      assert_eq(decoded[0].phones[0].params.length(), 2)
      assert_eq(decoded[0].phones[0].params[1].name, "PREF")
      assert_eq(decoded[0].phones[0].params[1].values, ["1"])
    }
    None => fail("expected the contacts to decode")
  }
}

///|
test "round trip keeps parameter order and duplicates" {
  let text = "BEGIN:VCARD\nVERSION:4.0\nFN:Dup\nN:Dup;;;;\n" +
    "TEL;TYPE=cell;TYPE=voice;PREF=2:+7\nEND:VCARD"
  let contact = @vcard.parse(text).contacts[0]
  match @json.decode_contacts(@json.encode_contacts([contact])) {
    Some(contacts) => {
      assert_eq(contacts.length(), 1)
      let params = contacts[0].phones[0].params
      assert_eq(params.length(), 3)
      assert_eq(params[0].name, "TYPE")
      assert_eq(params[0].values, ["cell"])
      assert_eq(params[1].name, "TYPE")
      assert_eq(params[1].values, ["voice"])
      assert_eq(params[2].name, "PREF")
      assert_eq(params[2].values, ["2"])
    }
    None => fail("expected the contact to decode")
  }
}

///|
test "round trip keeps the order of the contacts" {
  let contacts = [sample_contact(), phone_only_contact()]
  match @json.decode_contacts(@json.encode_contacts(contacts)) {
    Some(decoded) => {
      assert_eq(decoded.length(), 2)
      assert_eq(decoded[0], contacts[0])
      assert_eq(decoded[1], contacts[1])
    }
    None => fail("expected both contacts to decode")
  }
}

///|
test "parse result JSON round trip keeps diagnostics" {
  let result = @vcard.parse("BEGIN:VCARD\nVERSION:2.1\nFN:Bad\\x\nEND:VCARD")
  assert_true(result.diagnostics.length() > 0)
  let value = @json.parse_result_to_json(result)
  assert_true(@json.json_to_parse_result(value) == Some(result))
}

///|
test "parse result encoder writes contacts and diagnostics" {
  let result = @vcard.parse("BEGIN:VCARD\nVERSION:2.1\nFN:Bad\nEND:VCARD")
  match @json.parse_result_to_json(result) {
    Object(fields) =>
      match (fields.get("contacts"), fields.get("diagnostics")) {
        (Some(Array(contacts)), Some(Array(diagnostics))) => {
          assert_eq(contacts.length(), result.contacts.length())
          assert_eq(diagnostics.length(), result.diagnostics.length())
          assert_true(diagnostics.length() > 0)
        }
        _ => fail("expected the contact and diagnostic arrays")
      }
    _ => fail("expected a JSON object")
  }
}

///|
test "parse result decoder rejects an array" {
  assert_true(@json.json_to_parse_result(Json::array([])) is None)
}

///|
test "parse result decoder rejects a missing diagnostics key" {
  let value = Json::object(Map([("contacts", Json::array([]))]))
  assert_true(@json.json_to_parse_result(value) is None)
}

///|
test "parse result decoder rejects non-string diagnostics" {
  let value = Json::object(
    Map([
      ("contacts", Json::array([])),
      ("diagnostics", Json::array([Json::number(1.0)])),
    ]),
  )
  assert_true(@json.json_to_parse_result(value) is None)
}

///|
test "parse result decoder ignores extra keys" {
  let value = Json::object(
    Map([
      ("contacts", Json::array([])),
      ("diagnostics", Json::array([Json::string("invalid-version:3")])),
      ("x-extra", Json::null()),
    ]),
  )
  match @json.json_to_parse_result(value) {
    Some(result) => {
      assert_eq(result.contacts.length(), 0)
      assert_eq(result.diagnostics, ["invalid-version:3"])
    }
    None => fail("expected the parse result to decode")
  }
}
