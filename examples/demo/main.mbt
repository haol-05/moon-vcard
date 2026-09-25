///|
fn main {
  let input = "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nEMAIL:alice@example.org\nEND:VCARD"
  let result = @vcard.parse(input)
  println("Contacts: " + result.contacts.length().to_string())
  println("Diagnostics: " + result.diagnostics.length().to_string())
}
