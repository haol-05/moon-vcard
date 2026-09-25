///|
/// Renders the parameters of one field as ` [NAME=value]` groups.
fn params_text(params : Array[@vcard.Param]) -> String {
  let text = StringBuilder()
  for param in params {
    text.write_string(" [" + param.name)
    for value in param.values {
      text.write_string("=" + value)
    }
    text.write_string("]")
  }
  text.to_string()
}

///|
fn main {
  let input = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN;ENCODING=QUOTED-PRINTABLE:=E5=BC=A0=E4=B8=89\r\nN:Zhang;San;;;\r\nTEL;TYPE=cell;PREF=2:+8613900000002\r\nTEL;TYPE=home;PREF=1:+8613900000001\r\nEMAIL;TYPE=work:zhang@example.org\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:4.0\r\nFN:Bob\r\nN:Doe;Bob;;;\r\nEND:VCARD\r\n"
  let result = @vcard.parse(input)
  println("Contacts: " + result.contacts.length().to_string())
  println("Diagnostics: " + result.diagnostics.length().to_string())
  for contact in result.contacts {
    println("Name: " + contact.full_name + " (v" + contact.version + ")")
    for phone in @vcard.sort_by_preference(contact.phones) {
      println("  TEL " + phone.value + params_text(phone.params))
    }
    for email in contact.emails {
      println("  EMAIL " + email.value + params_text(email.params))
    }
  }
}
