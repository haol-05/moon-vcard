// Tests for the markdown rendering package. Contacts are always built through
// `@vcard.parse`, so the tests exercise the real public data model.

///|
/// Parses a one-card document and returns its single contact.
fn contact_of(input : String) -> @vcard.Contact {
  let parsed = @vcard.parse(input)
  if parsed.contacts.length() != 1 {
    abort("expected exactly one contact")
  }
  parsed.contacts[0]
}

///|
/// The card used by the demo example: one phone and one email.
fn demo_contact() -> @vcard.Contact {
  let input = "BEGIN:VCARD\nVERSION:3.0\n" +
    "FN;ENCODING=QUOTED-PRINTABLE:=E5=BC=A0=E4=B8=89\nN:Zhang;San;;;\n" +
    "TEL;TYPE=home;PREF=1:+8613900000001\n" +
    "EMAIL;TYPE=work:zhang@example.org\nEND:VCARD"
  contact_of(input)
}

///|
/// A card whose phones are stored with the higher `PREF` first.
fn two_phone_contact() -> @vcard.Contact {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN:张三\nN:Zhang;San;;;\n" +
    "TEL;TYPE=cell;PREF=2:+8613900000002\n" +
    "TEL;TYPE=home;PREF=1:+8613900000001\n" +
    "EMAIL;TYPE=work:zhang@example.org\nEND:VCARD"
  contact_of(input)
}

///|
test "escape_markdown_cell leaves plain text alone" {
  assert_eq(@report.escape_markdown_cell("Alice"), "Alice")
  assert_eq(@report.escape_markdown_cell(""), "")
  assert_eq(@report.escape_markdown_cell("张 三"), "张 三")
}

///|
test "escape_markdown_cell escapes pipes" {
  assert_eq(@report.escape_markdown_cell("a|b"), "a\\|b")
  assert_eq(@report.escape_markdown_cell("|"), "\\|")
  assert_eq(@report.escape_markdown_cell("|a|b|"), "\\|a\\|b\\|")
}

///|
test "escape_markdown_cell replaces every newline with one space" {
  assert_eq(@report.escape_markdown_cell("a\nb"), "a b")
  assert_eq(@report.escape_markdown_cell("a\r\nb"), "a b")
  assert_eq(@report.escape_markdown_cell("a\rb"), "a b")
  assert_eq(@report.escape_markdown_cell("a\r\n\r\nb"), "a  b")
}

///|
test "escape_markdown_cell escapes a pipe next to a newline" {
  assert_eq(@report.escape_markdown_cell("a|b\nc"), "a\\|b c")
}

///|
test "contact_markdown renders name, version, phones and emails" {
  let expected = "- name: 张三\n- version: 3.0\n" +
    "- tel: +8613900000001 [TYPE=home] [PREF=1]\n" +
    "- email: zhang@example.org [TYPE=work]"
  assert_eq(@report.contact_markdown(demo_contact()), expected)
}

///|
test "contact_markdown of a bare contact has two lines" {
  let contact = contact_of("BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nEND:VCARD")
  assert_eq(@report.contact_markdown(contact), "- name: Bob\n- version: 4.0")
}

///|
test "contact_markdown comma joins the values of one parameter" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\n" + "TEL;TYPE=work,voice:+1\nEND:VCARD",
  )
  assert_eq(
    @report.contact_markdown(contact),
    "- name: Bob\n- version: 4.0\n" + "- tel: +1 [TYPE=work,voice]",
  )
}

///|
test "contact_markdown renders a bare parameter without a value" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nTEL;PREF:+1\nEND:VCARD",
  )
  assert_eq(
    @report.contact_markdown(contact),
    "- name: Bob\n- version: 4.0\n" + "- tel: +1 [PREF]",
  )
}

///|
test "contact_markdown keeps the stored order and repeats the prefix" {
  let lines = @report.contact_markdown(two_phone_contact()).split("\n")
  let collected = lines.to_array()
  assert_eq(collected.length(), 5)
  assert_true(collected[2].contains("+8613900000002 [TYPE=cell] [PREF=2]"))
  assert_true(collected[3].contains("+8613900000001 [TYPE=home] [PREF=1]"))
  assert_true(collected[4].contains("zhang@example.org [TYPE=work]"))
}

///|
test "contacts_markdown renders the header and one contact row" {
  let expected = "| name | version | phones | emails |\n" +
    "| --- | --- | --- | --- |\n" +
    "| 张三 | 3.0 | +8613900000001 | zhang@example.org |"
  assert_eq(@report.contacts_markdown([demo_contact()]), expected)
}

///|
test "contacts_markdown writes one row per contact" {
  let second = contact_of("BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nEND:VCARD")
  let text = @report.contacts_markdown([demo_contact(), second])
  let lines = text.split("\n").to_array()
  assert_eq(lines.length(), 4)
  assert_true(text.contains("| name | version | phones | emails |"))
  assert_true(text.contains("| Bob | 4.0 |  |  |"))
}

///|
test "contacts_markdown joins multi-value cells with semicolons" {
  let text = @report.contacts_markdown([two_phone_contact()])
  assert_true(text.contains("+8613900000002; +8613900000001"))
}

///|
test "contacts_markdown escapes a pipe in a cell" {
  let contact = contact_of("BEGIN:VCARD\nVERSION:4.0\nFN:a|b\nEND:VCARD")
  let text = @report.contacts_markdown([contact])
  assert_true(text.contains("| a\\|b |"))
  assert_eq(text.split("\n").to_array().length(), 3)
}

///|
test "contacts_markdown replaces a name newline with a space" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Lee\\, Ann\\nTeam\nEND:VCARD",
  )
  let text = @report.contacts_markdown([contact])
  assert_true(text.contains("| Lee, Ann Team |"))
  assert_eq(text.split("\n").to_array().length(), 3)
}

///|
test "contacts_markdown of no contacts is the header and alignment only" {
  let contacts : Array[@vcard.Contact] = []
  let text = @report.contacts_markdown(contacts)
  assert_eq(
    text, "| name | version | phones | emails |\n| --- | --- | --- | --- |",
  )
}

///|
test "summary_markdown counts contacts and diagnostics" {
  let contacts = [demo_contact()]
  let diagnostics : Array[String] = []
  assert_eq(
    @report.summary_markdown(contacts, diagnostics),
    "- contacts: 1\n- diagnostics: 0",
  )
}

///|
test "summary_markdown lists one diagnostic per code" {
  let contacts : Array[@vcard.Contact] = []
  let diagnostics = ["invalid-version:4", "missing-fn:4"]
  assert_eq(
    @report.summary_markdown(contacts, diagnostics),
    "- contacts: 0\n" +
    "- diagnostics: 2\n- diagnostic: invalid-version:4\n" +
    "- diagnostic: missing-fn:4",
  )
}

///|
test "summary_markdown of an empty result is the zero summary" {
  let parsed = @vcard.parse("")
  assert_eq(
    @report.summary_markdown(parsed.contacts, parsed.diagnostics),
    "- contacts: 0\n- diagnostics: 0",
  )
}

///|
test "summary_markdown reports the diagnostics of a bad card" {
  let parsed = @vcard.parse("BEGIN:VCARD\nVERSION:2.1\nFN:Bad\nEND:VCARD\n")
  assert_eq(parsed.contacts.length(), 0)
  assert_eq(parsed.diagnostics, ["invalid-version:4"])
  assert_eq(
    @report.summary_markdown(parsed.contacts, parsed.diagnostics),
    "- contacts: 0\n- diagnostics: 1\n- diagnostic: invalid-version:4",
  )
}

///|
test "contact_lines matches the demo shape" {
  let lines = @report.contact_lines(demo_contact())
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "Name: 张三 (v3.0)")
  assert_eq(lines[1], "  TEL +8613900000001 [TYPE=home] [PREF=1]")
  assert_eq(lines[2], "  EMAIL zhang@example.org [TYPE=work]")
}

///|
test "contact_lines of a bare contact is the name line only" {
  let contact = contact_of("BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nEND:VCARD")
  assert_eq(@report.contact_lines(contact), ["Name: Bob (v4.0)"])
}

///|
test "contact_lines keeps the stored phone order" {
  let lines = @report.contact_lines(two_phone_contact())
  assert_eq(lines.length(), 4)
  assert_eq(lines[0], "Name: 张三 (v3.0)")
  assert_eq(lines[1], "  TEL +8613900000002 [TYPE=cell] [PREF=2]")
  assert_eq(lines[2], "  TEL +8613900000001 [TYPE=home] [PREF=1]")
  assert_eq(lines[3], "  EMAIL zhang@example.org [TYPE=work]")
}

///|
test "contact_lines renders several emails in order" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nEMAIL;TYPE=work:b@example.org\n" +
    "EMAIL;TYPE=home:b@example.net\nEND:VCARD",
  )
  let lines = @report.contact_lines(contact)
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "Name: Bob (v4.0)")
  assert_eq(lines[1], "  EMAIL b@example.org [TYPE=work]")
  assert_eq(lines[2], "  EMAIL b@example.net [TYPE=home]")
}
