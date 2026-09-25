// `derive(Eq, Debug)` promotes the trait methods onto the type as regular methods.
// The newest toolchain asks for that promotion to be declared, so every public type
// carries the matching `extend` below it.

///|
/// A single attribute parameter, for example `TYPE=cell` or a bare `PREF`.
pub struct Param {
  name : String
  values : Array[String]
} derive(Eq, Debug)

///|
pub extend Param with Eq::{not_equal, equal}

///|
pub extend Param with @debug.Debug::{to_repr}

///|
/// A property value together with the parameters written on its own line.
pub struct Field {
  value : String
  params : Array[Param]
} derive(Eq, Debug)

///|
pub extend Field with Eq::{not_equal, equal}

///|
pub extend Field with @debug.Debug::{to_repr}

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
pub extend Contact with Eq::{not_equal, equal}

///|
pub extend Contact with @debug.Debug::{to_repr}

///|
pub struct ParseResult {
  contacts : Array[Contact]
  diagnostics : Array[String]
} derive(Eq, Debug)

///|
pub extend ParseResult with Eq::{not_equal, equal}

///|
pub extend ParseResult with @debug.Debug::{to_repr}

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
/// ASCII-only upper casing, enough for parameter names and encoding values.
fn ascii_upper(input : String) -> String {
  let result = StringBuilder()
  for c in input.iter() {
    result.write_char(c.to_ascii_uppercase())
  }
  result.to_string()
}

///|
/// Values of the first parameter named `name`, which is expected in upper case.
fn param_values(params : Array[Param], name : String) -> Array[String]? {
  for param in params {
    if ascii_upper(param.name) == name {
      return Some(param.values)
    }
  }
  None
}

///|
fn has_quoted_printable_encoding(params : Array[Param]) -> Bool {
  match param_values(params, "ENCODING") {
    Some(values) => {
      for value in values {
        if ascii_upper(value) == "QUOTED-PRINTABLE" {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
/// True when the `CHARSET` parameter is absent or names UTF-8 / ASCII.
fn has_supported_charset(params : Array[Param]) -> Bool {
  match param_values(params, "CHARSET") {
    Some(values) => {
      if values.length() == 0 {
        return true
      }
      let name = ascii_upper(values[0])
      name == "UTF-8" || name == "US-ASCII" || name == "ASCII"
    }
    None => true
  }
}

///|
/// Drops the parameters whose meaning has already been applied to the stored value.
fn drop_consumed_params(
  params : Array[Param],
  keep_charset : Bool,
) -> Array[Param] {
  let kept : Array[Param] = []
  for param in params {
    let name = ascii_upper(param.name)
    if name == "ENCODING" {
      continue
    }
    if name == "CHARSET" && !keep_charset {
      continue
    }
    kept.push(param)
  }
  kept
}

///|
/// Reads a non-negative decimal integer, ignoring surrounding spaces.
fn parse_preference(input : String) -> Int? {
  let text = input.trim()
  if text.length() == 0 {
    return None
  }
  let zero = Char::to_int('0')
  let mut value = 0
  for c in text.iter() {
    let digit = Char::to_int(c) - zero
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
/// Numeric `PREF` of a field, or `None` when it is absent or not a number.
fn preference_rank(field : Field) -> Int? {
  match param_values(field.params, "PREF") {
    Some(values) => {
      if values.length() == 0 {
        return None
      }
      parse_preference(values[0])
    }
    None => None
  }
}

///|
/// True when `left` should be ordered before `right`.
fn preference_before(left : Field, right : Field) -> Bool {
  match (preference_rank(left), preference_rank(right)) {
    (Some(a), Some(b)) => a < b
    (Some(_), None) => true
    (None, Some(_)) => false
    (None, None) => false
  }
}

///|
/// Orders multi-value fields by `PREF`: numeric preferences ascending, then every
/// field whose `PREF` is missing or not a number. Fields that share a rank keep
/// their original order, and the input array is left untouched.
pub fn sort_by_preference(fields : Array[Field]) -> Array[Field] {
  let used : Array[Bool] = []
  for _ in fields {
    used.push(false)
  }
  let ordered : Array[Field] = []
  while ordered.length() < fields.length() {
    let mut best = -1
    for index in 0..<fields.length() {
      if used[index] {
        continue
      }
      if best < 0 || preference_before(fields[index], fields[best]) {
        best = index
      }
    }
    used[best] = true
    ordered.push(fields[best])
  }
  ordered
}

///|
fn drop_last(input : String) -> String {
  let chars = input.iter().to_array()
  if chars.length() == 0 {
    return ""
  }
  let result = StringBuilder()
  let last = chars.length() - 1
  for index in 0..<last {
    result.write_char(chars[index])
  }
  result.to_string()
}

///|
fn hex_value(c : Char) -> Int? {
  let code = Char::to_int(c.to_ascii_uppercase())
  let zero = Char::to_int('0')
  let nine = Char::to_int('9')
  let upper_a = Char::to_int('A')
  let upper_f = Char::to_int('F')
  if code >= zero && code <= nine {
    return Some(code - zero)
  }
  if code >= upper_a && code <= upper_f {
    return Some(code - upper_a + 10)
  }
  None
}

///|
fn is_continuation(byte : Int) -> Bool {
  byte >= 0x80 && byte <= 0xBF
}

///|
/// Reads a byte, or `-1` past the end, so callers can check without a length test.
fn byte_at(bytes : Array[Int], index : Int) -> Int {
  if index < bytes.length() {
    bytes[index]
  } else {
    -1
  }
}

///|
fn utf8_bytes(code : Int) -> Array[Int] {
  if code < 0x80 {
    return [code]
  }
  if code < 0x800 {
    return [0xC0 | (code >> 6), 0x80 | (code & 0x3F)]
  }
  [0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F)]
}

///|
/// Builds a `Char` from a code unit whose range the caller has already checked.
/// Surrogate halves are valid `Char` values, so the safe conversion is not enough.
fn char_of(code : Int) -> Char {
  code.unsafe_to_char()
}

///|
/// Decodes UTF-8 bytes and reports whether every sequence was well formed.
fn decode_utf8(bytes : Array[Int]) -> (String, Bool) {
  let result = StringBuilder()
  let replacement = char_of(0xFFFD)
  let mut index = 0
  let mut ok = true
  while index < bytes.length() {
    let first = bytes[index]
    if first < 0x80 {
      result.write_char(char_of(first))
      index += 1
    } else if first < 0xC2 {
      ok = false
      result.write_char(replacement)
      index += 1
    } else if first <= 0xDF {
      let second = byte_at(bytes, index + 1)
      if is_continuation(second) {
        let code = ((first - 0xC0) << 6) + (second - 0x80)
        result.write_char(char_of(code))
        index += 2
      } else {
        ok = false
        result.write_char(replacement)
        index += 1
      }
    } else if first <= 0xEF {
      let second = byte_at(bytes, index + 1)
      let third = byte_at(bytes, index + 2)
      let second_ok = is_continuation(second)
      let third_ok = is_continuation(third)
      if second_ok && third_ok {
        let lead = (first - 0xE0) << 12
        let middle = (second - 0x80) << 6
        let code = lead + middle + (third - 0x80)
        result.write_char(char_of(code))
        index += 3
      } else {
        ok = false
        result.write_char(replacement)
        index += 1
      }
    } else if first <= 0xF4 {
      let second = byte_at(bytes, index + 1)
      let third = byte_at(bytes, index + 2)
      let fourth = byte_at(bytes, index + 3)
      let second_ok = is_continuation(second)
      let third_ok = is_continuation(third)
      let fourth_ok = is_continuation(fourth)
      if second_ok && third_ok && fourth_ok {
        let lead = (first - 0xF0) << 18
        let high = (second - 0x80) << 12
        let middle = (third - 0x80) << 6
        let code = lead + high + middle + (fourth - 0x80)
        let value = code - 0x10000
        let unit_high = 0xD800 + (value >> 10)
        let unit_low = 0xDC00 + (value & 0x3FF)
        result.write_char(char_of(unit_high))
        result.write_char(char_of(unit_low))
        index += 4
      } else {
        ok = false
        result.write_char(replacement)
        index += 1
      }
    } else {
      ok = false
      result.write_char(replacement)
      index += 1
    }
  }
  (result.to_string(), ok)
}

///|
/// Decodes one quoted-printable value. `false` means a `=XX` sequence was malformed
/// or the decoded bytes were not valid UTF-8.
fn decode_quoted_printable(input : String) -> (String, Bool) {
  let chars = input.iter().to_array()
  let bytes : Array[Int] = []
  let mut index = 0
  let mut ok = true
  while index < chars.length() {
    let current = chars[index]
    let mut step = 1
    if current == '=' {
      let has_two = index + 2 < chars.length()
      if has_two {
        let upper = hex_value(chars[index + 1])
        let lower = hex_value(chars[index + 2])
        match (upper, lower) {
          (Some(high), Some(low)) => {
            bytes.push(high * 16 + low)
            step = 3
          }
          _ => {
            ok = false
            bytes.push(0x3D)
          }
        }
      } else {
        ok = false
        bytes.push(0x3D)
      }
    } else {
      let code = Char::to_int(current)
      if code < 0x80 {
        bytes.push(code)
      } else {
        for byte in utf8_bytes(code) {
          bytes.push(byte)
        }
      }
    }
    index += step
  }
  let (text, valid) = decode_utf8(bytes)
  (text, ok && valid)
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
  let lines = unfold(input)
  let mut active = false
  let mut version = ""
  let mut full_name = ""
  let mut family_name = ""
  let mut given_name = ""
  let mut phones : Array[Field] = []
  let mut emails : Array[Field] = []
  let mut line_number = 0
  let mut index = 0
  while index < lines.length() {
    let line = lines[index]
    index += 1
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
    let property_line = line_number
    let (head, maybe_raw) = split_once(line, ":")
    let raw = match maybe_raw {
      Some(text) => text
      None => {
        diagnostics.push("invalid-line:" + line_number.to_string())
        continue
      }
    }
    let (key, params) = parse_property_head(head)
    let mut field_params = params
    let mut text = raw
    if has_quoted_printable_encoding(params) {
      let supported = has_supported_charset(params)
      if !supported {
        diagnostics.push("unsupported-charset:" + property_line.to_string())
      }
      while text.has_suffix("=") && index < lines.length() {
        text = drop_last(text) + lines[index]
        index += 1
        line_number += 1
      }
      let (decoded, ok) = decode_quoted_printable(text)
      if !ok {
        diagnostics.push(
          "invalid-quoted-printable:" + property_line.to_string(),
        )
      }
      text = decoded
      field_params = drop_consumed_params(params, supported)
    }
    if key == "N" {
      match name_parts(text) {
        Some(names) => {
          family_name = names[0]
          given_name = names[1]
        }
        None => diagnostics.push("invalid-n:" + property_line.to_string())
      }
      continue
    }
    let value = match unescape_text(text) {
      Some(inner) => inner
      None => {
        diagnostics.push("invalid-escape:" + property_line.to_string())
        continue
      }
    }
    match key {
      "VERSION" => version = value
      "FN" => full_name = value
      "TEL" => if value != "" { phones.push({ value, params: field_params, }) }
      "EMAIL" =>
        if value != "" {
          emails.push({ value, params: field_params, })
        }
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
