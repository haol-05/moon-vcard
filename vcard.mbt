///|
/// A single attribute parameter, for example `TYPE=cell` or a bare `PREF`.
pub struct Param {
  name : String
  values : Array[String]
} derive(Eq, Debug)

///|
/// A property value together with the parameters written on its own line.
pub struct Field {
  value : String
  params : Array[Param]
} derive(Eq, Debug)

///|
pub struct Contact {
  version : String
  full_name : String
  family_name : String
  given_name : String
  phones : Array[Field]
  emails : Array[Field]
} derive(Eq, Debug)

///|
pub struct ParseResult {
  contacts : Array[Contact]
  diagnostics : Array[String]
} derive(Eq, Debug)

///|
fn unfold(input : String) -> Array[String] {
  let lines : Array[String] = []
  let normalized = input
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  for raw in normalized.split("\n") {
    if raw.has_prefix(" ") || raw.has_prefix("\t") {
      if !lines.is_empty() {
        let chars = raw.iter().to_array()
        let tail = StringBuilder()
        for index in 1..<chars.length() {
          tail.write_char(chars[index])
        }
        let last = lines.length() - 1
        lines[last] = lines[last] + tail.to_string()
      }
    } else {
      lines.push(raw.to_owned())
    }
  }
  lines
}

///|
fn unescape_text(input : String) -> String? {
  let chars = input.iter().to_array()
  let result = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '\\' {
      if index + 1 == chars.length() {
        return None
      }
      match chars[index + 1] {
        'n' | 'N' => result.write_char('\n')
        '\\' => result.write_char('\\')
        ';' => result.write_char(';')
        ',' => result.write_char(',')
        _ => return None
      }
      index += 2
    } else {
      result.write_char(chars[index])
      index += 1
    }
  }
  Some(result.to_string())
}

///|
fn escape_text(input : String) -> String {
  let result = StringBuilder()
  for c in input.iter() {
    match c {
      '\n' => result.write_string("\\n")
      '\\' => result.write_string("\\\\")
      ';' => result.write_string("\\;")
      ',' => result.write_string("\\,")
      _ => result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// Splits `input` at its first `separator` and keeps any later separator in the tail.
fn split_once(input : String, separator : String) -> (String, String?) {
  let parts = input.split(separator).to_array()
  if parts.length() < 2 {
    return (input, None)
  }
  let tail = StringBuilder()
  for index in 1..<parts.length() {
    if index > 1 {
      tail.write_string(separator)
    }
    tail.write_string(parts[index].to_owned())
  }
  (parts[0].to_owned(), Some(tail.to_string()))
}

///|
/// Reads the property name and its parameters from the part before the first `:`.
fn parse_property_head(head : String) -> (String, Array[Param]) {
  let segments = head.split(";").to_array()
  if segments.length() == 0 {
    return ("", [])
  }
  let name = segments[0].trim().to_owned()
  let params : Array[Param] = []
  for index in 1..<segments.length() {
    let raw = segments[index].trim().to_owned()
    if raw == "" {
      continue
    }
    let (param_name, maybe_value) = split_once(raw, "=")
    let values : Array[String] = []
    match maybe_value {
      Some(raw_value) => {
        let text = raw_value.trim().to_owned()
        let quoted = text.has_prefix("\"") && text.has_suffix("\"")
        if quoted && text.length() >= 2 {
          values.push(text.replace_all(old="\"", new=""))
        } else {
          for piece in text.split(",") {
            values.push(piece.trim().to_owned())
          }
        }
      }
      None => ()
    }
    params.push({ name: param_name.trim().to_owned(), values, })
  }
  (name, params)
}

///|
/// Writes one property line, parameters included, followed by CRLF.
fn write_field(output : StringBuilder, name : String, field : Field) -> Unit {
  output.write_string(name)
  for param in field.params {
    output.write_string(";")
    output.write_string(param.name)
    if param.values.length() > 0 {
      output.write_string("=")
      output.write_string(param.values.join(","))
    }
  }
  output.write_string(":")
  output.write_string(escape_text(field.value))
  output.write_string("\r\n")
}

///|
fn name_parts(input : String) -> Array[String]? {
  let parts : Array[String] = []
  let mut current = StringBuilder()
  let chars = input.iter().to_array()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '\\' && index + 1 < chars.length() {
      current.write_char(chars[index])
      current.write_char(chars[index + 1])
      index += 2
    } else if chars[index] == ';' {
      parts.push(current.to_string())
      current = StringBuilder()
      index += 1
    } else {
      current.write_char(chars[index])
      index += 1
    }
  }
  parts.push(current.to_string())
  if parts.length() < 2 {
    return None
  }
  let decoded : Array[String] = []
  for part in parts {
    match unescape_text(part) {
      Some(value) => decoded.push(value)
      None => return None
    }
  }
  Some(decoded)
}

///|
pub fn parse(input : String) -> ParseResult {
  let contacts : Array[Contact] = []
  let diagnostics : Array[String] = []
  let mut active = false
  let mut version = ""
  let mut full_name = ""
  let mut family_name = ""
  let mut given_name = ""
  let mut phones : Array[Field] = []
  let mut emails : Array[Field] = []
  let mut line_number = 0
  for line in unfold(input) {
    line_number += 1
    if line == "BEGIN:VCARD" {
      if active {
        diagnostics.push("nested-card:" + line_number.to_string())
      }
      active = true
      version = ""
      full_name = ""
      family_name = ""
      given_name = ""
      phones = []
      emails = []
      continue
    }
    if line == "END:VCARD" {
      if !active {
        diagnostics.push("unexpected-end:" + line_number.to_string())
      } else {
        let mut valid = true
        if version != "3.0" && version != "4.0" {
          diagnostics.push("invalid-version:" + line_number.to_string())
          valid = false
        }
        if full_name == "" {
          diagnostics.push("missing-fn:" + line_number.to_string())
          valid = false
        }
        if valid {
          contacts.push({
            version,
            full_name,
            family_name,
            given_name,
            phones,
            emails,
          })
        }
      }
      active = false
      continue
    }
    if line == "" {
      continue
    }
    if !active {
      diagnostics.push("outside-card:" + line_number.to_string())
      continue
    }
    let (head, maybe_raw) = split_once(line, ":")
    let raw = match maybe_raw {
      Some(text) => text
      None => {
        diagnostics.push("invalid-line:" + line_number.to_string())
        continue
      }
    }
    let (key, params) = parse_property_head(head)
    if key == "N" {
      match name_parts(raw) {
        Some(names) => {
          family_name = names[0]
          given_name = names[1]
        }
        None => diagnostics.push("invalid-n:" + line_number.to_string())
      }
      continue
    }
    let value = match unescape_text(raw) {
      Some(text) => text
      None => {
        diagnostics.push("invalid-escape:" + line_number.to_string())
        continue
      }
    }
    match key {
      "VERSION" => version = value
      "FN" => full_name = value
      "TEL" => if value != "" { phones.push({ value, params, }) }
      "EMAIL" => if value != "" { emails.push({ value, params, }) }
      _ => ()
    }
  }
  if active {
    diagnostics.push("unclosed-card")
  }
  { contacts, diagnostics, }
}

///|
pub fn format(contact : Contact) -> String? {
  if (contact.version != "3.0" && contact.version != "4.0") ||
    contact.full_name == "" {
    return None
  }
  let output = StringBuilder()
  output.write_string("BEGIN:VCARD\r\nVERSION:")
  output.write_string(contact.version)
  output.write_string("\r\nFN:")
  output.write_string(escape_text(contact.full_name))
  output.write_string("\r\nN:")
  output.write_string(escape_text(contact.family_name))
  output.write_string(";")
  output.write_string(escape_text(contact.given_name))
  output.write_string(";;;\r\n")
  for phone in contact.phones {
    write_field(output, "TEL", phone)
  }
  for email in contact.emails {
    write_field(output, "EMAIL", email)
  }
  output.write_string("END:VCARD\r\n")
  Some(output.to_string())
}
