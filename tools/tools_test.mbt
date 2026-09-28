///|
/// Alice with one phone and one email.
fn alice() -> @vcard.Contact {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Alice\nN:Smith;Alice;;;\nTEL;TYPE=cell;PREF=1:+8613900000001\nEMAIL:a@x.org\nEND:VCARD",
  )
  result.contacts[0]
}

///|
/// The same person as `alice`, written differently, plus a second phone.
fn alice_again() -> @vcard.Contact {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:3.0\nFN:Alice Smith\nN:;Alice;;;\nTEL;TYPE=home:+86 139 0000 0001\nTEL:+8613900000002\nEMAIL:b@x.org\nEND:VCARD",
  )
  result.contacts[0]
}

///|
/// A different person.
fn bob() -> @vcard.Contact {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Bob Doe\nN:Doe;Bob;;;\nEMAIL:bob@example.org\nEND:VCARD",
  )
  result.contacts[0]
}

///|
fn three() -> Array[@vcard.Contact] {
  [alice(), alice_again(), bob()]
}

///|
test "render_contact_text matches the core writer" {
  let contact = alice()
  match @vcard.format(contact) {
    Some(text) => assert_eq(@tools.render_contact_text(contact), text)
    None => fail("expected a serialized contact")
  }
}

///|
test "render_contact_text escapes text fields" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:Lee\\, Ann\\;Team\nN:Lee;Ann;;;\nEND:VCARD",
  )
  let contact = result.contacts[0]
  match @vcard.format(contact) {
    Some(text) => assert_eq(@tools.render_contact_text(contact), text)
    None => fail("expected a serialized contact")
  }
}

///|
test "render_contact_text keeps parameters and crlf endings" {
  let text = @tools.render_contact_text(alice())
  assert_true(text.contains("TEL;TYPE=cell;PREF=1:+8613900000001\r\n"))
  assert_true(text.has_prefix("BEGIN:VCARD\r\n"))
  assert_true(text.has_suffix("END:VCARD\r\n"))
}

///|
test "render_contacts_text concatenates cards" {
  let text = @tools.render_contacts_text(three())
  let mut occurrences = 0
  for line in text.split("\n") {
    if line.trim().to_owned() == "BEGIN:VCARD" {
      occurrences += 1
    }
  }
  assert_eq(occurrences, 3)
}

///|
test "merge keeps the left name and fills gaps from the right" {
  let merged = @tools.merge(alice(), alice_again())
  assert_eq(merged.full_name, "Alice")
  assert_eq(merged.family_name, "Smith")
  assert_eq(merged.given_name, "Alice")
}

///|
test "merge unions channels without duplicates" {
  let merged = @tools.merge(alice(), alice_again())
  assert_eq(merged.phones.length(), 2)
  assert_eq(merged.emails.length(), 2)
  assert_eq(merged.phones[0].value, "+8613900000001")
  assert_eq(merged.phones[1].value, "+8613900000002")
  assert_eq(merged.emails[0].value, "a@x.org")
  assert_eq(merged.emails[1].value, "b@x.org")
}

///|
test "merge preserves parameters of the surviving channel" {
  let merged = @tools.merge(alice(), alice_again())
  assert_eq(merged.phones[0].params[0].name, "TYPE")
  assert_eq(merged.phones[0].params[0].values, ["cell"])
}

///|
test "merge prefers the left version" {
  let merged = @tools.merge(alice(), alice_again())
  assert_eq(merged.version, "4.0")
}

///|
test "merge_text renders the union" {
  let text = @tools.merge_text(alice(), alice_again())
  assert_true(text.contains("TEL;TYPE=cell;PREF=1:+8613900000001\r\n"))
  assert_true(text.contains("TEL:+8613900000002\r\n"))
  let reparsed = @vcard.parse(text)
  assert_eq(reparsed.contacts.length(), 1)
  assert_eq(reparsed.contacts[0].phones.length(), 2)
}

///|
test "merge_group folds several cards" {
  match @tools.merge_group(three()) {
    Some(merged) => assert_eq(merged.phones.length(), 2)
    None => fail("expected a merged contact")
  }
}

///|
test "merge_group of nothing is none" {
  match @tools.merge_group([]) {
    Some(_) => fail("expected none for an empty group")
    None => assert_true(true)
  }
}

///|
test "duplicate_groups reports shared keys" {
  let groups = @tools.duplicate_groups(three())
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].indices, [0, 1])
  assert_true(groups[0].key.contains("alice"))
}

///|
test "duplicate_groups is empty without duplicates" {
  assert_eq(@tools.duplicate_groups([alice(), bob()]).length(), 0)
}

///|
test "dedupe merges duplicates and keeps the first position" {
  let deduped = @tools.dedupe(three())
  assert_eq(deduped.length(), 2)
  assert_eq(deduped[0].full_name, "Alice")
  assert_eq(deduped[0].phones.length(), 2)
  assert_eq(deduped[1].full_name, "Bob Doe")
}

///|
test "dedupe leaves a clean set untouched" {
  let deduped = @tools.dedupe([alice(), bob()])
  assert_eq(deduped.length(), 2)
  assert_eq(deduped[0].full_name, "Alice")
  assert_eq(deduped[1].full_name, "Bob Doe")
}

///|
test "channel filters keep the matching contacts" {
  let contacts = [alice(), bob()]
  assert_eq(@tools.with_phone(contacts).length(), 1)
  assert_eq(@tools.with_email(contacts).length(), 2)
  assert_eq(@tools.complete_only(contacts).length(), 2)
}

///|
test "complete_only drops cards without a channel" {
  let result = @vcard.parse(
    "BEGIN:VCARD\nVERSION:4.0\nFN:No Channel\nN:Channel;No;;;\nEND:VCARD",
  )
  assert_eq(@tools.complete_only(result.contacts).length(), 0)
}

///|
test "search finds names, phones and emails" {
  let contacts = [alice(), bob()]
  assert_eq(@tools.search(contacts, "alice").length(), 1)
  assert_eq(@tools.search(contacts, "DOE").length(), 1)
  assert_eq(@tools.search(contacts, "13900000001").length(), 1)
  assert_eq(@tools.search(contacts, "example.org").length(), 1)
  assert_eq(@tools.search(contacts, "nobody").length(), 0)
}

///|
test "search with an empty needle returns every contact" {
  let contacts = [alice(), bob()]
  assert_eq(@tools.search(contacts, "   ").length(), 2)
}

///|
test "filter delegates to the query language" {
  let contacts = [alice(), bob()]
  assert_eq(@tools.filter(contacts, "has:phone").length(), 1)
  assert_eq(@tools.filter(contacts, "type=cell").length(), 1)
  assert_eq(@tools.filter(contacts, "-has:email").length(), 0)
}

///|
test "sort_by_name orders case insensitively" {
  let sorted = @tools.sort_by_name([bob(), alice()])
  assert_eq(sorted[0].full_name, "Alice")
  assert_eq(sorted[1].full_name, "Bob Doe")
}

///|
test "sort_by_name ignores punctuation and keeps ties stable" {
  let first = @vcard.parse(
      "BEGIN:VCARD\nVERSION:4.0\nFN:O'Neil, Ann\nN:ONeil;Ann;;;\nEND:VCARD",
    ).contacts[0]
  let second = @vcard.parse(
      "BEGIN:VCARD\nVERSION:4.0\nFN:oneil ann\nN:Oneil;Ann;;;\nEND:VCARD",
    ).contacts[0]
  let sorted = @tools.sort_by_name([first, second])
  assert_eq(sorted[0].full_name, "O'Neil, Ann")
  assert_eq(sorted[1].full_name, "oneil ann")
}

///|
test "unique channels deduplicate by comparison key" {
  let contacts = three()
  assert_eq(@tools.unique_phones(contacts).length(), 2)
  assert_eq(@tools.unique_emails(contacts).length(), 3)
}

///|
test "stats counts contacts, channels and versions" {
  let value = @tools.stats(three())
  assert_eq(value.total, 3)
  assert_eq(value.with_phone, 2)
  assert_eq(value.with_email, 3)
  assert_eq(value.phones, 3)
  assert_eq(value.emails, 3)
  assert_eq(value.duplicate_groups, 1)
  assert_eq(value.versions.length(), 2)
  assert_eq(value.versions[0].version, "3.0")
  assert_eq(value.versions[0].count, 1)
  assert_eq(value.versions[1].version, "4.0")
  assert_eq(value.versions[1].count, 2)
}

///|
test "diff reports added, removed and unchanged cards" {
  let value = @tools.diff([alice()], [alice(), bob()])
  assert_eq(value.added.length(), 1)
  assert_eq(value.added[0].full_name, "Bob Doe")
  assert_eq(value.removed.length(), 0)
  assert_eq(value.unchanged.length(), 1)
}

///|
test "diff detects removals" {
  let value = @tools.diff([alice(), bob()], [bob()])
  assert_eq(value.added.length(), 0)
  assert_eq(value.removed.length(), 1)
  assert_eq(value.removed[0].full_name, "Alice")
}

///|
test "diff reports a rewritten card as changed" {
  let value = @tools.diff([alice()], [alice_again()])
  assert_eq(value.added.length(), 0)
  assert_eq(value.removed.length(), 0)
  assert_eq(value.changed.length(), 1)
  assert_eq(value.unchanged.length(), 0)
}

///|
test "render_stats lists counters" {
  let text = @tools.render_stats(@tools.stats(three()))
  assert_true(text.contains("contacts: 3\n"))
  assert_true(text.contains("duplicate groups: 1\n"))
  assert_true(text.contains("version 4.0: 2\n"))
}

///|
test "render_groups lists one line per member" {
  let contacts = three()
  let text = @tools.render_groups(contacts, @tools.duplicate_groups(contacts))
  assert_true(text.contains("key alice|+8613900000001|a@x.org\n"))
  assert_true(text.contains("  Alice\n"))
  assert_true(text.contains("  Alice Smith\n"))
}

///|
test "render_diff lists added and removed names" {
  let value = @tools.diff([alice()], [bob()])
  let text = @tools.render_diff(value)
  assert_true(text.contains("added: 1\n"))
  assert_true(text.contains("removed: 1\n"))
  assert_true(text.contains("+ Bob Doe\n"))
  assert_true(text.contains("- Alice\n"))
}
