// Utilities over the public `Param` model. Every name comparison folds ASCII
// case, so `type` and `TYPE` address the same parameter, while value text is
// always compared verbatim.

///|
/// ASCII-only upper casing, used for every parameter-name comparison.
fn ascii_upper(input : String) -> String {
  let result = StringBuilder()
  for c in input.iter() {
    result.write_char(c.to_ascii_uppercase())
  }
  result.to_string()
}

///|
/// True when `candidate` names the same parameter as `target`, ignoring case.
fn name_is(candidate : String, target : String) -> Bool {
  ascii_upper(candidate) == ascii_upper(target)
}

///|
/// The first parameter named `name`, compared without ASCII case.
pub fn lookup(params : Array[@vcard.Param], name : String) -> @vcard.Param? {
  for param in params {
    if name_is(param.name, name) {
      return Some(param)
    }
  }
  None
}

///|
/// True when at least one parameter is named `name`. A parameter without values
/// still counts as present.
pub fn has(params : Array[@vcard.Param], name : String) -> Bool {
  match lookup(params, name) {
    Some(_) => true
    None => false
  }
}

///|
/// Values of the first parameter named `name`, or an empty array. The result is
/// a copy, so it can be changed without touching `params`.
pub fn values_of(params : Array[@vcard.Param], name : String) -> Array[String] {
  match lookup(params, name) {
    Some(param) => param.values.copy()
    None => []
  }
}

///|
/// First value of the first parameter named `name`. `None` when that parameter
/// is absent or carries no value at all.
pub fn first_value(params : Array[@vcard.Param], name : String) -> String? {
  match lookup(params, name) {
    Some(param) =>
      match param.values {
        [first, ..] => Some(first)
        [] => None
      }
    None => None
  }
}

///|
/// Reads a non-negative decimal integer, ignoring surrounding spaces.
fn parse_rank(input : String) -> Int? {
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
/// Numeric `PREF` of the first `PREF` parameter. `None` when `PREF` is absent,
/// valueless, or its first value is not a non-negative decimal integer.
pub fn preference(params : Array[@vcard.Param]) -> Int? {
  match first_value(params, "PREF") {
    Some(value) => parse_rank(value)
    None => None
  }
}

///|
/// Copy of `params` in which `name` carries `values` at its first position, or
/// is appended as a new parameter when no such name exists. Later parameters
/// that repeat the name are left alone.
pub fn with_param(
  params : Array[@vcard.Param],
  name : String,
  values : Array[String],
) -> Array[@vcard.Param] {
  let result : Array[@vcard.Param] = []
  let mut replaced = false
  for param in params {
    if !replaced && name_is(param.name, name) {
      replaced = true
      result.push({ name, values: values.copy(), })
    } else {
      result.push(param)
    }
  }
  if !replaced {
    result.push({ name, values: values.copy(), })
  }
  result
}

///|
/// Copy of `params` without any parameter named `name`.
pub fn without(
  params : Array[@vcard.Param],
  name : String,
) -> Array[@vcard.Param] {
  let result : Array[@vcard.Param] = []
  for param in params {
    if !name_is(param.name, name) {
      result.push(param)
    }
  }
  result
}

///|
/// Adds `param` to `result`, either as a new entry or by merging its values
/// into the existing entry with the same name. A value already present is not
/// added a second time.
fn add_merged(result : Array[@vcard.Param], param : @vcard.Param) -> Unit {
  for index in 0..<result.length() {
    if name_is(result[index].name, param.name) {
      let values = result[index].values
      for value in param.values {
        if !values.contains(value) {
          values.push(value)
        }
      }
      return
    }
  }
  result.push({ name: param.name, values: param.values.copy(), })
}

///|
/// Union of two parameter lists: the `left` order first, then the names only
/// `right` carries, with the values of a shared name merged without duplicates.
pub fn merge(
  left : Array[@vcard.Param],
  right : Array[@vcard.Param],
) -> Array[@vcard.Param] {
  let result : Array[@vcard.Param] = []
  for param in left {
    add_merged(result, param)
  }
  for param in right {
    add_merged(result, param)
  }
  result
}

///|
/// Copy ordered by ASCII-uppercased name, keeping the relative order of
/// parameters that share a name.
pub fn sorted(params : Array[@vcard.Param]) -> Array[@vcard.Param] {
  let keys : Array[String] = []
  for param in params {
    keys.push(ascii_upper(param.name))
  }
  let used : Array[Bool] = []
  for _ in params {
    used.push(false)
  }
  let result : Array[@vcard.Param] = []
  while result.length() < params.length() {
    let mut best = -1
    for index in 0..<params.length() {
      if used[index] {
        continue
      }
      if best < 0 || keys[index] < keys[best] {
        best = index
      }
    }
    used[best] = true
    result.push(params[best])
  }
  result
}

///|
/// vCard parameter text without a leading `;`, for example
/// `TYPE=cell,voice;PREF=1`. A parameter without values renders as its bare
/// name and an empty array renders as `""`.
pub fn render(params : Array[@vcard.Param]) -> String {
  let output = StringBuilder()
  let mut first = true
  for param in params {
    if !first {
      output.write_string(";")
    }
    first = false
    output.write_string(param.name)
    if param.values.length() > 0 {
      output.write_string("=")
      output.write_string(param.values.join(","))
    }
  }
  output.to_string()
}

///|
/// Copy with names ASCII-uppercased and values trimmed, dropping value entries
/// that are empty after trimming. Useful for comparing parameter lists.
pub fn canonical(params : Array[@vcard.Param]) -> Array[@vcard.Param] {
  let result : Array[@vcard.Param] = []
  for param in params {
    let values : Array[String] = []
    for value in param.values {
      let text = value.trim().to_owned()
      if text != "" {
        values.push(text)
      }
    }
    result.push({ name: ascii_upper(param.name), values, })
  }
  result
}
