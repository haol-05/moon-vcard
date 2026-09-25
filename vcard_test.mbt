///|
test "parse two contacts and folded name" {
  let input = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Alice\r\n Smith\r\nN:Smith;Alice;;;\r\nTEL;TYPE=cell:+123\r\nEMAIL:alice@example.org\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nFN:Bob\r\nEND:VCARD\r\n"
  let result = @moon-vcard.parse(input)
  assert_eq(result.contacts.length(), 2)
  assert_eq(result.contacts[0].full_name, "AliceSmith")
  assert_eq(result.contacts[0].family_name, "Smith")
  assert_eq(result.contacts[0].phones, ["+123"])
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "text escaping and round trip" {
  let input = "BEGIN:VCARD\nVERSION:4.0\nFN:Lee\\, Ann\\nTeam\nN:Lee;Ann;;;\nEND:VCARD"
  let first = @moon-vcard.parse(input)
  assert_eq(first.contacts[0].full_name, "Lee, Ann\nTeam")
  let written = @moon-vcard.format(first.contacts[0])
  match written {
    Some(text) => {
      let again = @moon-vcard.parse(text)
      assert_eq(again.contacts[0].full_name, first.contacts[0].full_name)
      assert_eq(again.diagnostics.length(), 0)
    }
    None => fail("expected serialized contact")
  }
}

///|
test "reject incomplete card and malformed escape" {
  let input = "BEGIN:VCARD\nVERSION:2.1\nFN:Bad\\x\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.contacts.length(), 0)
  assert_true(result.diagnostics.contains("invalid-escape:3"))
  assert_true(result.diagnostics.contains("invalid-version:4"))
  assert_true(result.diagnostics.contains("missing-fn:4"))
}

///|
test "unclosed card is reported" {
  let result = @moon-vcard.parse("BEGIN:VCARD\nVERSION:4.0\nFN:Alice")
  assert_eq(result.contacts.length(), 0)
  assert_true(result.diagnostics.contains("unclosed-card"))
}

///|
test "escaped semicolon stays inside family name" {
  let input = "BEGIN:VCARD\nVERSION:4.0\nFN:Alice\nN:Smith\\;Jones;Alice;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.contacts[0].family_name, "Smith;Jones")
  assert_eq(result.contacts[0].given_name, "Alice")
}
