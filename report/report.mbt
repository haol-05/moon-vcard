// Human-readable rendering of the public contact model: a markdown table, a
// bullet list for one contact, a summary block, and the plain lines used by the
// bundled demo.

///|
/// Renders the parameters of one field as ` [NAME=value]` groups, with the
/// values of a single parameter joined by `,`.
fn params_text(params : Array[@vcard.Param]) -> String {
  let text = StringBuilder()
  for param in params {
    text.write_string(" [" + param.name)
    if param.values.length() > 0 {
      text.write_string("=")
      text.write_string(param.values.join(","))
    }
    text.write_string("]")
  }
  text.to_string()
}

///|
/// Joins the values of multi-value fields with `"; "`, dropping parameters.
fn join_field_values(fields : Array[@vcard.Field]) -> String {
  let values : Array[String] = []
  for field in fields {
    values.push(field.value)
  }
  values.join("; ")
}

///|
/// Escapes one markdown table cell: `|` becomes `\|` and every CR or LF becomes
/// a single space, so a cell never breaks its row.
pub fn escape_markdown_cell(value : String) -> String {
  value
  .replace_all(old="\r\n", new=" ")
  .replace_all(old="\r", new=" ")
  .replace_all(old="\n", new=" ")
  .replace_all(old="|", new="\\|")
}

///|
/// Renders one contact as markdown bullet lines: name, version, then one line
/// per phone and per email in the contact's stored order.
pub fn contact_markdown(contact : @vcard.Contact) -> String {
  let lines : Array[String] = []
  lines.push("- name: " + contact.full_name)
  lines.push("- version: " + contact.version)
  for phone in contact.phones {
    lines.push("- tel: " + phone.value + params_text(phone.params))
  }
  for email in contact.emails {
    lines.push("- email: " + email.value + params_text(email.params))
  }
  lines.join("\n")
}

///|
/// Renders all contacts as one markdown table: the header row
/// `| name | version | phones | emails |`, the alignment row that makes it a
/// table in CommonMark, then one row per contact.
pub fn contacts_markdown(contacts : Array[@vcard.Contact]) -> String {
  let lines : Array[String] = []
  lines.push("| name | version | phones | emails |")
  lines.push("| --- | --- | --- | --- |")
  for contact in contacts {
    let row = "| " +
      escape_markdown_cell(contact.full_name) +
      " | " +
      escape_markdown_cell(contact.version) +
      " | " +
      escape_markdown_cell(join_field_values(contact.phones)) +
      " | " +
      escape_markdown_cell(join_field_values(contact.emails)) +
      " |"
    lines.push(row)
  }
  lines.join("\n")
}

///|
/// Renders the contact count, the diagnostic count and then one line per
/// diagnostic code.
pub fn summary_markdown(
  contacts : Array[@vcard.Contact],
  diagnostics : Array[String],
) -> String {
  let lines : Array[String] = []
  lines.push("- contacts: " + contacts.length().to_string())
  lines.push("- diagnostics: " + diagnostics.length().to_string())
  for diagnostic in diagnostics {
    lines.push("- diagnostic: " + diagnostic)
  }
  lines.join("\n")
}

///|
/// The plain demo lines of one contact: a name line, then two-space-indented
/// `TEL ` and `EMAIL ` lines in the contact's stored order.
pub fn contact_lines(contact : @vcard.Contact) -> Array[String] {
  let lines : Array[String] = []
  lines.push("Name: " + contact.full_name + " (v" + contact.version + ")")
  for phone in contact.phones {
    lines.push("  TEL " + phone.value + params_text(phone.params))
  }
  for email in contact.emails {
    lines.push("  EMAIL " + email.value + params_text(email.params))
  }
  lines
}
