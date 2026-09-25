///|
pub struct Contact {
  version : String
  full_name : String
  family_name : String
  given_name : String
  phones : Array[String]
  emails : Array[String]
}

///|
pub struct ParseResult {
  contacts : Array[Contact]
  diagnostics : Array[String]
}

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
fn property_name(input : String) -> String {
  let parts = input.split(";").to_array()
  parts[0].to_owned()
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
  let mut phones : Array[String] = []
  let mut emails : Array[String] = []
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
    let pieces = line.split(":").to_array()
    if pieces.length() < 2 {
      diagnostics.push("invalid-line:" + line_number.to_string())
      continue
    }
    let key = property_name(pieces[0].to_owned())
    let raw_builder = StringBuilder()
    for index in 1..<pieces.length() {
      if index > 1 {
        raw_builder.write_string(":")
      }
      raw_builder.write_string(pieces[index].to_owned())
    }
    let raw = raw_builder.to_string()
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
      "TEL" => if value != "" { phones.push(value) }
      "EMAIL" => if value != "" { emails.push(value) }
      _ => ()
    }
  }
  if active {
    diagnostics.push("unclosed-card")
  }
  { contacts, diagnostics }
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
    output.write_string("TEL:")
    output.write_string(escape_text(phone))
    output.write_string("\r\n")
  }
  for email in contact.emails {
    output.write_string("EMAIL:")
    output.write_string(escape_text(email))
    output.write_string("\r\n")
  }
  output.write_string("END:VCARD\r\n")
  Some(output.to_string())
}
