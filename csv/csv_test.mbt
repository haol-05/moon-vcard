// Tests for the RFC 4180 CSV package. Contacts are always built through
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
/// A three line card with two phones and one email.
fn demo_contact() -> @vcard.Contact {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN:张三\n" +
    "N:Zhang;San;;;\nTEL;TYPE=cell;PREF=2:+8613900000002\n" +
    "TEL;TYPE=home;PREF=1:+8613900000001\n" +
    "EMAIL;TYPE=work:zhang@example.org\nEND:VCARD"
  contact_of(input)
}

///|
test "encode_field leaves plain text unchanged" {
  assert_eq(@csv.encode_field("Alice"), "Alice")
  assert_eq(@csv.encode_field(""), "")
  assert_eq(@csv.encode_field("two words"), "two words")
  assert_eq(@csv.encode_field("semi;colon"), "semi;colon")
  assert_eq(@csv.encode_field("张 三"), "张 三")
}

///|
test "encode_field quotes a field holding a comma" {
  assert_eq(@csv.encode_field("Lee, Ann"), "\"Lee, Ann\"")
  assert_eq(@csv.encode_field(","), "\",\"")
}

///|
test "encode_field doubles inner quotes" {
  assert_eq(@csv.encode_field("say \"hi\""), "\"say \"\"hi\"\"\"")
  assert_eq(@csv.encode_field("\""), "\"\"\"\"")
}

///|
test "encode_field quotes every kind of newline" {
  assert_eq(@csv.encode_field("a\nb"), "\"a\nb\"")
  assert_eq(@csv.encode_field("a\r\nb"), "\"a\r\nb\"")
  assert_eq(@csv.encode_field("a\rb"), "\"a\rb\"")
}

///|
test "encode_row joins cells with commas and ends with crlf" {
  assert_eq(@csv.encode_row(["a", "b", "c"]), "a,b,c\r\n")
  assert_eq(@csv.encode_row(["only"]), "only\r\n")
}

///|
test "encode_row of no cells is one blank record" {
  assert_eq(@csv.encode_row([]), "\r\n")
}

///|
test "encode writes every row with a crlf terminator" {
  let rows : Array[Array[String]] = [["a", "b"], ["c", "d"]]
  assert_eq(@csv.encode(rows), "a,b\r\nc,d\r\n")
}

///|
test "encode of no rows is the empty string" {
  let rows : Array[Array[String]] = []
  assert_eq(@csv.encode(rows), "")
}

///|
test "encode quotes only the cells that need it" {
  let rows : Array[Array[String]] = [["Lee, Ann", "plain", "a\nb"]]
  assert_eq(@csv.encode(rows), "\"Lee, Ann\",plain,\"a\nb\"\r\n")
}

///|
test "parse splits crlf records" {
  let rows = @csv.parse("a,b\r\nc,d\r\n")
  assert_eq(rows.length(), 2)
  assert_eq(rows[0], ["a", "b"])
  assert_eq(rows[1], ["c", "d"])
}

///|
test "parse accepts lf records" {
  let rows = @csv.parse("a,b\nc,d\n")
  assert_eq(rows.length(), 2)
  assert_eq(rows[1], ["c", "d"])
}

///|
test "parse accepts a last record without a newline" {
  let rows = @csv.parse("a,b\nc")
  assert_eq(rows.length(), 2)
  assert_eq(rows[1], ["c"])
}

///|
test "parse keeps trailing empty fields" {
  let rows = @csv.parse("a,,\r\n")
  assert_eq(rows.length(), 1)
  assert_eq(rows[0], ["a", "", ""])
}

///|
test "parse keeps a single empty field on a one cell record" {
  assert_eq(@csv.parse("a\r\n"), [["a"]])
  assert_eq(@csv.parse(","), [["", ""]])
}

///|
test "parse reads a quoted comma" {
  assert_eq(@csv.parse("\"Lee, Ann\",x\r\n"), [["Lee, Ann", "x"]])
}

///|
test "parse unescapes doubled quotes" {
  assert_eq(@csv.parse("\"say \"\"hi\"\"\"\r\n"), [["say \"hi\""]])
}

///|
test "parse reads a crlf inside a quoted field" {
  let rows = @csv.parse("\"line1\r\nline2\",x\r\n")
  assert_eq(rows.length(), 1)
  assert_eq(rows[0][0], "line1\r\nline2")
  assert_eq(rows[0][1], "x")
}

///|
test "parse reads a lf inside a quoted field" {
  let rows = @csv.parse("\"line1\nline2\"\n")
  assert_eq(rows.length(), 1)
  assert_eq(rows[0], ["line1\nline2"])
}

///|
test "parse reads an empty quoted field" {
  assert_eq(@csv.parse("\"\",a\r\n"), [["", "a"]])
  assert_eq(@csv.parse("\"\"\r\n"), [[""]])
}

///|
test "parse of empty input has no records" {
  assert_eq(@csv.parse("").length(), 0)
}

///|
test "parse of a blank line is one empty field" {
  let rows = @csv.parse("\r\n")
  assert_eq(rows.length(), 1)
  assert_eq(rows[0], [""])
}

///|
test "parse tolerates an unterminated quote" {
  assert_eq(@csv.parse("\"abc"), [["abc"]])
}

///|
test "parse tolerates a stray quote inside an unquoted field" {
  assert_eq(@csv.parse("a\"b\r\n"), [["a\"b"]])
}

///|
test "parse tolerates text after a closing quote" {
  assert_eq(@csv.parse("\"a\"x\r\n"), [["ax"]])
}

///|
test "parse ignores a cr that is not followed by lf" {
  assert_eq(@csv.parse("a\rb\r\n"), [["a"], ["b"]])
}

///|
test "encode and parse round trip a tricky table" {
  let rows : Array[Array[String]] = [
    ["plain", "", "with,comma"],
    ["with \"quote\"", "line1\nline2", "tail"],
  ]
  let text = @csv.encode(rows)
  assert_eq(@csv.parse(text), rows)
}

///|
test "contact_header names every column in order" {
  assert_eq(@csv.contact_header(), [
    "full_name", "family_name", "given_name", "version", "phones", "emails",
  ])
}

///|
test "contact_row joins phones and emails in stored order" {
  let row = @csv.contact_row(demo_contact())
  assert_eq(row.length(), 6)
  assert_eq(row[0], "张三")
  assert_eq(row[1], "Zhang")
  assert_eq(row[2], "San")
  assert_eq(row[3], "3.0")
  assert_eq(row[4], "+8613900000002; +8613900000001")
  assert_eq(row[5], "zhang@example.org")
}

///|
test "contact_row drops parameters" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\n" +
    "TEL;TYPE=cell;PREF=1:+1\nEMAIL;TYPE=work:b@example.org\nEND:VCARD",
  )
  let row = @csv.contact_row(contact)
  assert_eq(row[4], "+1")
  assert_eq(row[5], "b@example.org")
  assert_false(row[4].contains("TYPE"))
  assert_false(row[4].contains("PREF"))
}

///|
test "contact_row of a bare contact has empty multi-value cells" {
  let contact = contact_of("BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nEND:VCARD")
  assert_eq(@csv.contact_row(contact), ["Bob", "", "", "4.0", "", ""])
}

///|
test "contacts_to_csv writes the header and one row per contact" {
  let first = demo_contact()
  let second = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\n" +
    "EMAIL:bob@example.org\nEND:VCARD",
  )
  let text = @csv.contacts_to_csv([first, second])
  let rows = @csv.parse(text)
  assert_eq(rows.length(), 3)
  assert_eq(rows[0], @csv.contact_header())
  assert_eq(rows[1][0], "张三")
  assert_eq(rows[1][4], "+8613900000002; +8613900000001")
  assert_eq(rows[2][0], "Bob")
  assert_eq(rows[2][5], "bob@example.org")
}

///|
test "contacts_to_csv quotes unsafe values" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Lee\\, Ann\nN:Lee;Ann;;;\n" +
    "TEL;TYPE=home:+1\nEND:VCARD",
  )
  let text = @csv.contacts_to_csv([contact])
  assert_eq(contact.full_name, "Lee, Ann")
  assert_true(text.contains("\"Lee, Ann\""))
  let rows = @csv.parse(text)
  assert_eq(rows[1][0], "Lee, Ann")
  assert_eq(rows[1][4], "+1")
}

///|
test "contacts_to_csv of no contacts is the header only" {
  let contacts : Array[@vcard.Contact] = []
  let text = @csv.contacts_to_csv(contacts)
  assert_eq(text, "full_name,family_name,given_name,version,phones,emails\r\n")
}

///|
test "contacts_to_csv keeps a newline inside one cell" {
  let contact = contact_of(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Lee\\, Ann\\nTeam\nN:Lee;Ann;;;\nEND:VCARD",
  )
  let text = @csv.contacts_to_csv([contact])
  let rows = @csv.parse(text)
  assert_eq(rows.length(), 2)
  assert_eq(rows[1][0], "Lee, Ann\nTeam")
}

///|
test "table returns the header and the remaining rows" {
  let (header, body) = @csv.table("a,b\r\n1,2\r\n3,4\r\n")
  assert_eq(header, ["a", "b"])
  assert_eq(body.length(), 2)
  assert_eq(body[0], ["1", "2"])
  assert_eq(body[1], ["3", "4"])
}

///|
test "table of empty input is empty" {
  let (header, body) = @csv.table("")
  assert_eq(header.length(), 0)
  assert_eq(body.length(), 0)
}

///|
test "table of a header only document has no rows" {
  let (header, body) = @csv.table("a,b\r\n")
  assert_eq(header, ["a", "b"])
  assert_eq(body.length(), 0)
}

///|
test "table reads back what contacts_to_csv wrote" {
  let text = @csv.contacts_to_csv([demo_contact()])
  let (header, body) = @csv.table(text)
  assert_eq(header, @csv.contact_header())
  assert_eq(body.length(), 1)
  assert_eq(body[0], @csv.contact_row(demo_contact()))
}
