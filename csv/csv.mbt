// Self-contained RFC 4180 CSV support for the public contact model: fields are
// quoted only when they must be, every record ends with CRLF, and the reader
// tolerates LF input, quoted newlines and malformed quoting instead of failing.

///|
/// Doubles every `"` so the field can be wrapped in quotes.
fn escape_quotes(value : String) -> String {
  value.replace_all(old="\"", new="\"\"")
}

///|
/// True when `value` needs surrounding quotes: `,`, `"`, CR or LF inside.
fn needs_quotes(value : String) -> Bool {
  value.contains(",") ||
  value.contains("\"") ||
  value.contains("\r") ||
  value.contains("\n")
}

///|
/// Encodes one field: quoted and doubled only when RFC 4180 requires it.
pub fn encode_field(value : String) -> String {
  if needs_quotes(value) {
    "\"" + escape_quotes(value) + "\""
  } else {
    value
  }
}

///|
/// Encodes one record and terminates it with CRLF.
pub fn encode_row(cells : Array[String]) -> String {
  let encoded : Array[String] = []
  for cell in cells {
    encoded.push(encode_field(cell))
  }
  encoded.join(",") + "\r\n"
}

///|
/// Encodes a whole table. Every record, the last one included, ends with CRLF.
pub fn encode(rows : Array[Array[String]]) -> String {
  let output = StringBuilder()
  for row in rows {
    output.write_string(encode_row(row))
  }
  output.to_string()
}

///|
/// Decodes one CSV document into records of raw field values.
///
/// CRLF and LF both end a record, a quoted field may span newlines, `""` is a
/// literal quote, and empty fields are kept. A record is closed by the end of
/// the text as well, so a trailing newline never adds a phantom record, while a
/// blank line is one record holding a single empty field. Unclosed quotes and
/// stray quotes inside an unquoted field are read as literal text.
pub fn parse(text : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let chars = text.iter().to_array()
  let mut cells : Array[String] = []
  let mut field = StringBuilder()
  let mut field_chars = 0
  let mut quoted_cell = false
  let mut in_quotes = false
  let mut started = false
  let mut index = 0
  while index < chars.length() {
    let c = chars[index]
    if in_quotes {
      if c == '"' {
        if index + 1 < chars.length() && chars[index + 1] == '"' {
          field.write_char('"')
          field_chars += 1
          index += 2
        } else {
          in_quotes = false
          index += 1
        }
      } else {
        field.write_char(c)
        field_chars += 1
        index += 1
      }
      continue
    }
    if c == '"' && field_chars == 0 && !quoted_cell {
      in_quotes = true
      quoted_cell = true
      started = true
      index += 1
      continue
    }
    if c == ',' {
      cells.push(field.to_string())
      field = StringBuilder()
      field_chars = 0
      quoted_cell = false
      started = true
      index += 1
      continue
    }
    if c == '\r' || c == '\n' {
      cells.push(field.to_string())
      rows.push(cells)
      cells = []
      field = StringBuilder()
      field_chars = 0
      quoted_cell = false
      started = false
      if c == '\r' && index + 1 < chars.length() && chars[index + 1] == '\n' {
        index += 2
      } else {
        index += 1
      }
      continue
    }
    field.write_char(c)
    field_chars += 1
    started = true
    index += 1
  }
  if started || field_chars > 0 || cells.length() > 0 {
    cells.push(field.to_string())
    rows.push(cells)
  }
  rows
}

///|
/// The column names written by `contacts_to_csv`.
pub fn contact_header() -> Array[String] {
  ["full_name", "family_name", "given_name", "version", "phones", "emails"]
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
/// One raw CSV record for `contact`, in `contact_header` order.
pub fn contact_row(contact : @vcard.Contact) -> Array[String] {
  [
    contact.full_name,
    contact.family_name,
    contact.given_name,
    contact.version,
    join_field_values(contact.phones),
    join_field_values(contact.emails),
  ]
}

///|
/// Writes the header record followed by one record per contact.
pub fn contacts_to_csv(contacts : Array[@vcard.Contact]) -> String {
  let rows : Array[Array[String]] = [contact_header()]
  for contact in contacts {
    rows.push(contact_row(contact))
  }
  encode(rows)
}

///|
/// Splits `text` into its header record and the remaining records. Empty input
/// yields an empty header and no rows.
pub fn table(text : String) -> (Array[String], Array[Array[String]]) {
  let rows = parse(text)
  if rows.length() == 0 {
    return ([], [])
  }
  let body : Array[Array[String]] = []
  for index in 1..<rows.length() {
    body.push(rows[index])
  }
  (rows[0], body)
}
