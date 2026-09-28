///|
fn two_contacts() -> Array[@vcard.Contact] {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nTEL;TYPE=cell;PREF=2:+8613900000002\nTEL;TYPE=home;PREF=1:+8613900000001\nEMAIL;TYPE=work:alice@example.org\nEND:VCARD\nBEGIN:VCARD\nVERSION:3.0\nFN:Bob Doe\nN:Doe;Bob;;;\nTEL:+15550109999\nEND:VCARD",
  )
  result.contacts
}

///|
test "the helper parses both cards" {
  assert_eq(two_contacts().length(), 2)
}

///|
test "empty expression matches everything" {
  let query = @query.parse("")
  assert_true(@query.is_empty(query))
  assert_eq(@query.describe(query), "any")
  assert_eq(@query.filter(two_contacts(), "").length(), 2)
}

///|
test "free text term searches every text field" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "alice").length(), 1)
  assert_eq(@query.filter(contacts, "doe").length(), 1)
  assert_eq(@query.filter(contacts, "nobody").length(), 0)
}

///|
test "name operator equals and contains" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "name=Alice Smith").length(), 1)
  assert_eq(@query.filter(contacts, "name=alice smith").length(), 1)
  assert_eq(@query.filter(contacts, "name=Alice").length(), 0)
  assert_eq(@query.filter(contacts, "name~smith").length(), 1)
}

///|
test "family and given fields are searchable" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "family=Smith").length(), 1)
  assert_eq(@query.filter(contacts, "given~bob").length(), 1)
}

///|
test "version field distinguishes card versions" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "version=4.0").length(), 1)
  assert_eq(@query.filter(contacts, "version=3.0").length(), 1)
}

///|
test "phone matches on digits" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "phone~13900000002").length(), 1)
  assert_eq(@query.filter(contacts, "phone~0000").length(), 1)
  assert_eq(@query.filter(contacts, "phone=+86 139 0000 0002").length(), 1)
  assert_eq(@query.filter(contacts, "phone=13900000002").length(), 0)
}

///|
test "email matches as text" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "email~example.org").length(), 1)
  assert_eq(@query.filter(contacts, "email=ALICE@example.org").length(), 1)
  assert_eq(@query.filter(contacts, "email~other.org").length(), 0)
}

///|
test "type matches parameter values" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "type=cell").length(), 1)
  assert_eq(@query.filter(contacts, "type=CELL").length(), 1)
  assert_eq(@query.filter(contacts, "type=work").length(), 1)
  assert_eq(@query.filter(contacts, "type=fax").length(), 0)
}

///|
test "pref compares the smallest preference" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "pref=1").length(), 1)
  assert_eq(@query.filter(contacts, "pref<=2").length(), 1)
  assert_eq(@query.filter(contacts, "pref>=1").length(), 1)
  assert_eq(@query.filter(contacts, "pref<1").length(), 0)
  assert_eq(@query.filter(contacts, "pref>0").length(), 1)
}

///|
test "has checks channels and parameters" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "has:phone").length(), 2)
  assert_eq(@query.filter(contacts, "has:email").length(), 1)
  assert_eq(@query.filter(contacts, "has:pref").length(), 1)
  assert_eq(@query.filter(contacts, "has:type").length(), 1)
  assert_eq(@query.filter(contacts, "has:fax").length(), 0)
}

///|
test "leading dash negates a term" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "-has:email").length(), 1)
  assert_eq(@query.filter(contacts, "-name~alice").length(), 1)
  assert_eq(@query.filter(contacts, "-nobody").length(), 2)
}

///|
test "several terms are combined with and" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "has:phone,type=cell").length(), 1)
  assert_eq(@query.filter(contacts, "has:email,type=cell").length(), 1)
  assert_eq(@query.filter(contacts, "has:email,type=fax").length(), 0)
  assert_eq(@query.filter(contacts, "has:pref,-type=cell").length(), 0)
}

///|
test "unknown fields never match" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "nickname~alice").length(), 0)
  assert_eq(@query.filter(contacts, "-nickname~alice").length(), 2)
}

///|
test "parsing keeps operator and value" {
  let query = @query.parse("pref<=2")
  assert_eq(query.terms.length(), 1)
  let term = query.terms[0]
  assert_eq(term.field, "pref")
  assert_eq(term.op, "<=")
  assert_eq(term.value, "2")
  assert_false(term.negated)
}

///|
test "parsing ignores empty pieces and lonely dash" {
  let query = @query.parse(" , ,- ,name~a,")
  assert_eq(query.terms.length(), 1)
  assert_eq(query.terms[0].field, "name")
}

///|
test "describe renders the expression back" {
  assert_eq(
    @query.describe(@query.parse("has:phone,type=cell")),
    "has:phone AND type=cell",
  )
  assert_eq(@query.describe(@query.parse("-has:email")), "-has:email")
  assert_eq(@query.describe(@query.parse("alice")), "alice")
}

///|
test "colon behaves like contains" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "name:ali").length(), 1)
  assert_eq(@query.filter(contacts, "email:example").length(), 1)
}

///|
test "greater and smaller operators need a preference" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:No Pref\nN:None;No;;;\nTEL:+15550100000\nEND:VCARD",
  )
  assert_eq(@query.filter(result.contacts, "pref>=1").length(), 0)
  assert_eq(@query.filter(result.contacts, "pref<=9").length(), 0)
  assert_eq(@query.filter(result.contacts, "has:pref").length(), 0)
}

///|
test "filter keeps the original order" {
  let contacts = two_contacts()
  let kept = @query.filter(contacts, "has:phone")
  assert_eq(kept.length(), 2)
  assert_eq(kept[0].full_name, "Alice Smith")
  assert_eq(kept[1].full_name, "Bob Doe")
}

///|
test "empty values are tolerated" {
  let contacts = two_contacts()
  assert_eq(@query.filter(contacts, "name~").length(), 2)
  assert_eq(@query.filter(contacts, "type~").length(), 1)
}

///|
test "term matching can be used directly" {
  let contacts = two_contacts()
  let query = @query.parse("type=cell")
  assert_true(@query.term_matches(query.terms[0], contacts[0]))
  assert_false(@query.term_matches(query.terms[0], contacts[1]))
}
