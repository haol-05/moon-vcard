///|
test "ascii case helpers only touch ascii letters" {
  assert_eq(@normalize.ascii_lower("Alice SMITH 42"), "alice smith 42")
  assert_eq(@normalize.ascii_upper("alice smith"), "ALICE SMITH")
  assert_eq(@normalize.ascii_lower(""), "")
}

///|
test "digits_only keeps digits in order" {
  assert_eq(@normalize.digits_only("+86 139-0000-0002"), "8613900000002")
  assert_eq(@normalize.digits_only("no digits here"), "")
  assert_eq(@normalize.digits_only("a1b2c3"), "123")
}

///|
test "phone_key keeps a leading plus and drops separators" {
  assert_eq(@normalize.phone_key("+86 139-0000-0002"), "+8613900000002")
  assert_eq(@normalize.phone_key("(010) 6666 8888"), "01066668888")
  assert_eq(@normalize.phone_key("+1 (555) 010-9999"), "+15550109999")
}

///|
test "phone_key ignores a plus that is not leading" {
  assert_eq(@normalize.phone_key("86+139"), "86139")
}

///|
test "phone_key normalizes different spellings to one key" {
  let a = @normalize.phone_key("+86 139 0000 0002")
  let b = @normalize.phone_key("+8613900000002")
  let c = @normalize.phone_key(" +86139-0000-0002 ")
  assert_eq(a, b)
  assert_eq(b, c)
}

///|
test "email_key lowercases and trims" {
  assert_eq(@normalize.email_key(" Alice@Example.ORG "), "alice@example.org")
  assert_eq(@normalize.email_key("a@b"), "a@b")
}

///|
test "name_key collapses spaces and drops punctuation" {
  assert_eq(@normalize.name_key("Smith-Jones,  Ann"), "smithjones ann")
  assert_eq(@normalize.name_key("  Alice   SMITH "), "alice smith")
  assert_eq(@normalize.name_key("O'Neil"), "oneil")
}

///|
test "name_key handles tabs and empty input" {
  assert_eq(@normalize.name_key("a\t\tb"), "a b")
  assert_eq(@normalize.name_key("   "), "")
  assert_eq(@normalize.name_key(""), "")
}

///|
test "contact_key joins name and first channels" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nTEL:+8613900000001\nEMAIL:Alice@Example.org\nEND:VCARD",
  )
  assert_eq(result.contacts.length(), 1)
  assert_eq(
    @normalize.contact_key(result.contacts[0]),
    "alice smith|+8613900000001|alice@example.org",
  )
}

///|
test "contact_key tolerates missing channels" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\nEND:VCARD",
  )
  assert_eq(@normalize.contact_key(result.contacts[0]), "bob||")
}

///|
test "same_person matches spelling differences" {
  let first = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nTEL:+86 139 0000 0001\nEND:VCARD",
  )
  let second = @vcard.parse(
    "BEGIN:VCARD\nVERSION:3.0\nFN:alice  smith\nN:Smith;Alice;;;\nTEL:+8613900000001\nEND:VCARD",
  )
  assert_true(@normalize.same_person(first.contacts[0], second.contacts[0]))
}

///|
test "same_person rejects different people" {
  let first = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice\nN:Smith;Alice;;;\nTEL:+8613900000001\nEND:VCARD",
  )
  let second = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\nTEL:+8613900000002\nEND:VCARD",
  )
  assert_false(@normalize.same_person(first.contacts[0], second.contacts[0]))
}

///|
test "has_enough_digits counts digits" {
  assert_true(@normalize.has_enough_digits("+86 139", 5))
  assert_false(@normalize.has_enough_digits("+86 139", 6))
  assert_true(@normalize.has_enough_digits("123456", 6))
}

///|
test "is_plausible_phone accepts common shapes" {
  assert_true(@normalize.is_plausible_phone("+8613900000002"))
  assert_true(@normalize.is_plausible_phone("(010) 6666 8888"))
  assert_true(@normalize.is_plausible_phone("5550109999"))
}

///|
test "is_plausible_phone rejects short and misplaced plus" {
  assert_false(@normalize.is_plausible_phone("12345"))
  assert_false(@normalize.is_plausible_phone("86+1390000"))
  assert_false(@normalize.is_plausible_phone("++861390000000"))
  assert_false(@normalize.is_plausible_phone(""))
}

///|
test "is_plausible_email accepts ordinary addresses" {
  assert_true(@normalize.is_plausible_email("alice@example.org"))
  assert_true(@normalize.is_plausible_email("a.b-c@sub.example.co"))
}

///|
test "is_plausible_email rejects malformed addresses" {
  assert_false(@normalize.is_plausible_email("alice"))
  assert_false(@normalize.is_plausible_email("a@b@c"))
  assert_false(@normalize.is_plausible_email("@example.org"))
  assert_false(@normalize.is_plausible_email("alice@localhost"))
  assert_false(@normalize.is_plausible_email("ali ce@example.org"))
}

///|
test "mask_phone hides all but the last four digits" {
  assert_eq(@normalize.mask_phone("+8613900000002"), "+*********0002")
  assert_eq(@normalize.mask_phone("1234"), "**34")
}

///|
test "mask_phone keeps the plus and short values readable" {
  assert_eq(@normalize.mask_phone("+12345"), "+*2345")
  assert_eq(@normalize.mask_phone("12345678"), "****5678")
}

///|
test "mask_email hides the local part" {
  assert_eq(@normalize.mask_email("alice@example.org"), "a****@example.org")
  assert_eq(@normalize.mask_email("a@example.org"), "a@example.org")
}

///|
test "mask_email returns non addresses unchanged" {
  assert_eq(@normalize.mask_email("not-an-address"), "not-an-address")
}

///|
test "group_phone inserts spaces every four digits" {
  assert_eq(@normalize.group_phone("+8613900000002"), "+8613 9000 0000 2")
  assert_eq(@normalize.group_phone("12345678"), "1234 5678")
}

///|
test "primary keys read the first stored channel" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice\nN:Smith;Alice;;;\nTEL:+86 139 0000 0001\nTEL:+8613900000002\nEMAIL:First@Example.org\nEMAIL:second@example.org\nEND:VCARD",
  )
  assert_eq(@normalize.primary_phone_key(result.contacts[0]), "+8613900000001")
  assert_eq(
    @normalize.primary_email_key(result.contacts[0]),
    "first@example.org",
  )
}

///|
test "primary keys are empty without channels" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\nEND:VCARD",
  )
  assert_eq(@normalize.primary_phone_key(result.contacts[0]), "")
  assert_eq(@normalize.primary_email_key(result.contacts[0]), "")
}

///|
test "key_count counts cards sharing one key" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nTEL:+8613900000001\nEND:VCARD\nBEGIN:VCARD\nVERSION:3.0\nFN:alice  smith\nN:Smith;Alice;;;\nTEL:+86 139 0000 0001\nEND:VCARD\nBEGIN:VCARD\nVERSION:4.0\nFN:Bob\nN:Doe;Bob;;;\nEND:VCARD",
  )
  assert_eq(result.contacts.length(), 3)
  assert_eq(@normalize.key_count(result.contacts, result.contacts[0]), 2)
  assert_eq(@normalize.key_count(result.contacts, result.contacts[2]), 1)
}
