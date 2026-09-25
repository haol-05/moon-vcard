///|
test "parse two contacts and folded name" {
  let input = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Alice\r\n Smith\r\nN:Smith;Alice;;;\r\nTEL;TYPE=cell:+123\r\nEMAIL:alice@example.org\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nFN:Bob\r\nEND:VCARD\r\n"
  let result = @moon-vcard.parse(input)
  assert_eq(result.contacts.length(), 2)
  assert_eq(result.contacts[0].full_name, "AliceSmith")
  assert_eq(result.contacts[0].family_name, "Smith")
  assert_eq(result.contacts[0].phones.length(), 1)
  assert_eq(result.contacts[0].phones[0].value, "+123")
  assert_eq(result.contacts[0].phones[0].params[0].name, "TYPE")
  assert_eq(result.contacts[0].phones[0].params[0].values, ["cell"])
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

///|
test "property parameters are parsed and written back" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN:Alice\nN:Smith;Alice;;;\nTEL;TYPE=cell,voice;PREF=1:+123\nEMAIL;TYPE=work:alice@example.org\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.diagnostics.length(), 0)
  let phone = result.contacts[0].phones[0]
  assert_eq(phone.value, "+123")
  assert_eq(phone.params.length(), 2)
  assert_eq(phone.params[0].name, "TYPE")
  assert_eq(phone.params[0].values, ["cell", "voice"])
  assert_eq(phone.params[1].name, "PREF")
  assert_eq(phone.params[1].values, ["1"])
  assert_eq(result.contacts[0].emails[0].params[0].values, ["work"])
  match @moon-vcard.format(result.contacts[0]) {
    Some(text) => {
      assert_true(text.contains("TEL;TYPE=cell,voice;PREF=1:+123\r\n"))
      assert_true(text.contains("EMAIL;TYPE=work:alice@example.org\r\n"))
      let again = @moon-vcard.parse(text)
      assert_eq(again.contacts[0], result.contacts[0])
    }
    None => fail("expected serialized contact")
  }
}

///|
test "bare parameter and quoted parameter value" {
  let input = "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\nTEL;PREF;TYPE=\"work,voice\":+456\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.diagnostics.length(), 0)
  let params = result.contacts[0].phones[0].params
  assert_eq(params[0].name, "PREF")
  assert_eq(params[0].values.length(), 0)
  assert_eq(params[1].name, "TYPE")
  assert_eq(params[1].values, ["work,voice"])
}

///|
test "quoted-printable value decodes utf-8 text" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN;ENCODING=QUOTED-PRINTABLE:=E5=BC=A0=E4=B8=89\nN:Zhang;San;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(result.contacts[0].full_name, "张三")
}

///|
test "quoted-printable soft line break is joined" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN;ENCODING=QUOTED-PRINTABLE:=E5=BC=A0=\n=E4=B8=89\nN:Zhang;San;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(result.contacts[0].full_name, "张三")
  assert_eq(result.contacts[0].family_name, "Zhang")
}

///|
test "malformed quoted-printable is reported and kept" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN;ENCODING=QUOTED-PRINTABLE:Bad=ZZ\nN:Bad;Case;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_true(result.diagnostics.contains("invalid-quoted-printable:3"))
  assert_eq(result.contacts[0].full_name, "Bad=ZZ")
}

///|
test "unsupported charset is reported instead of mis-decoded" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN;CHARSET=GB2312;ENCODING=QUOTED-PRINTABLE:=D5=C5=C8=FD\nN:Zhang;San;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_true(result.diagnostics.contains("unsupported-charset:3"))
  assert_true(result.diagnostics.contains("invalid-quoted-printable:3"))
}

///|
test "quoted-printable parameter is dropped once decoded" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN:Alice\nN:Smith;Alice;;;\nTEL;ENCODING=QUOTED-PRINTABLE:+1=2D234\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.contacts[0].phones[0].value, "+1-234")
  assert_eq(result.contacts[0].phones[0].params.length(), 0)
  match @moon-vcard.format(result.contacts[0]) {
    Some(text) => {
      assert_true(text.contains("TEL:+1-234\r\n"))
      assert_false(text.contains("ENCODING"))
    }
    None => fail("expected serialized contact")
  }
}

///|
test "sort_by_preference orders numeric preferences" {
  let input = "BEGIN:VCARD\nVERSION:4.0\nFN:Alice\nN:Smith;Alice;;;\nTEL;PREF=10:+10\nTEL:+none-a\nTEL;PREF=2:+2\nTEL;PREF=1:+1\nTEL;PREF=abc:+abc\nTEL:+none-b\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  let ordered = @moon-vcard.sort_by_preference(result.contacts[0].phones)
  let values = ordered.map(fn(field) { field.value })
  assert_eq(values, ["+1", "+2", "+10", "+none-a", "+abc", "+none-b"])
  assert_eq(result.contacts[0].phones[0].value, "+10")
}

///|
test "sort_by_preference keeps equal preferences in file order" {
  let input = "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\nTEL;PREF=1:+a\nTEL;PREF=1:+b\nTEL;PREF:+bare\nTEL:+c\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  let ordered = @moon-vcard.sort_by_preference(result.contacts[0].phones)
  let values = ordered.map(fn(field) { field.value })
  assert_eq(values, ["+a", "+b", "+bare", "+c"])
}

///|
test "quoted-printable decodes a four byte utf-8 sequence" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN;ENCODING=QUOTED-PRINTABLE:=F0=9F=98=80 Smith\nN:Smith;Ann;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_eq(result.diagnostics.length(), 0)
  assert_eq(result.contacts[0].full_name, "😀 Smith")
}

///|
test "quoted-printable reports truncated utf-8 bytes" {
  let input = "BEGIN:VCARD\nVERSION:3.0\nFN;ENCODING=QUOTED-PRINTABLE:=E5=BC\nN:Smith;Ann;;;\nEND:VCARD"
  let result = @moon-vcard.parse(input)
  assert_true(result.diagnostics.contains("invalid-quoted-printable:3"))
}
