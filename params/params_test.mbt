// Tests build every input through `@vcard.parse`, so the parameter lists under
// test are exactly the ones the parser produces.

///|
/// Parameters of the `TEL` line built from `suffix`, for example `;TYPE=cell`.
fn tel_params(suffix : String) -> Array[@vcard.Param] {
  let card = "BEGIN:VCARD\nVERSION:4.0\nFN:Test\nN:T;T;;;\nTEL" +
    suffix +
    ":+100\nEND:VCARD"
  let result = @vcard.parse(card)
  result.contacts[0].phones[0].params
}

///|
test "lookup matches a parameter name regardless of case" {
  let params = tel_params(";TYPE=cell")
  match @params.lookup(params, "type") {
    Some(param) => {
      assert_eq(param.name, "TYPE")
      assert_eq(param.values, ["cell"])
    }
    None => fail("expected the TYPE parameter")
  }
}

///|
test "lookup returns None for an absent name" {
  let params = tel_params(";TYPE=cell")
  assert_true(@params.lookup(params, "PREF") is None)
}

///|
test "lookup finds the first of two equally named parameters" {
  let params = tel_params(";TYPE=cell;TYPE=voice")
  match @params.lookup(params, "TYPE") {
    Some(param) => assert_eq(param.values, ["cell"])
    None => fail("expected the TYPE parameter")
  }
}

///|
test "lookup of an empty list returns None" {
  assert_true(@params.lookup([], "TYPE") is None)
}

///|
test "has accepts any spelling of the name" {
  let params = tel_params(";TYPE=cell")
  assert_true(@params.has(params, "type"))
  assert_true(@params.has(params, "TYPE"))
  assert_true(@params.has(params, "TyPe"))
}

///|
test "has is false for an absent name" {
  assert_true(!@params.has(tel_params(";TYPE=cell"), "PREF"))
}

///|
test "has reports a bare parameter as present" {
  let params = tel_params(";PREF")
  assert_true(@params.has(params, "pref"))
  assert_eq(@params.values_of(params, "PREF").length(), 0)
}

///|
test "values_of returns every value of a multi-value parameter" {
  let params = tel_params(";TYPE=cell,voice")
  assert_eq(@params.values_of(params, "type"), ["cell", "voice"])
}

///|
test "values_of returns an empty array for an absent name" {
  assert_eq(@params.values_of(tel_params(";TYPE=cell"), "PREF").length(), 0)
}

///|
test "values_of hands back a copy of the stored values" {
  let params = tel_params(";TYPE=cell")
  let values = @params.values_of(params, "TYPE")
  values.push("voice")
  assert_eq(@params.values_of(params, "TYPE"), ["cell"])
}

///|
test "first_value returns the leading value" {
  let params = tel_params(";TYPE=cell,voice")
  assert_eq(@params.first_value(params, "TYPE"), Some("cell"))
}

///|
test "first_value returns None for an absent name" {
  assert_true(@params.first_value(tel_params(";TYPE=cell"), "PREF") is None)
}

///|
test "first_value returns None for a bare parameter" {
  assert_true(@params.first_value(tel_params(";PREF"), "PREF") is None)
}

///|
test "preference reads a single-digit rank" {
  assert_eq(@params.preference(tel_params(";PREF=1")), Some(1))
}

///|
test "preference reads a multi-digit rank" {
  assert_eq(@params.preference(tel_params(";PREF=100")), Some(100))
}

///|
test "preference reads zero" {
  assert_eq(@params.preference(tel_params(";PREF=0")), Some(0))
}

///|
test "preference returns None when PREF is absent" {
  assert_true(@params.preference(tel_params(";TYPE=cell")) is None)
}

///|
test "preference returns None for a valueless PREF" {
  assert_true(@params.preference(tel_params(";PREF")) is None)
}

///|
test "preference returns None for a non-numeric PREF" {
  assert_true(@params.preference(tel_params(";PREF=abc")) is None)
}

///|
test "preference returns None for a negative PREF" {
  assert_true(@params.preference(tel_params(";PREF=-1")) is None)
}

///|
test "preference returns None for a fractional PREF" {
  assert_true(@params.preference(tel_params(";PREF=1.5")) is None)
}

///|
test "preference ignores a later PREF parameter" {
  let params = tel_params(";PREF;PREF=2")
  assert_true(@params.preference(params) is None)
}

///|
test "with_param replaces a parameter at its first position" {
  let params = tel_params(";TYPE=cell;PREF=1")
  let updated = @params.with_param(params, "TYPE", ["voice"])
  assert_eq(@params.render(updated), "TYPE=voice;PREF=1")
}

///|
test "with_param appends a name that is not present yet" {
  let params = tel_params(";TYPE=cell")
  let updated = @params.with_param(params, "PREF", ["1"])
  assert_eq(@params.render(updated), "TYPE=cell;PREF=1")
}

///|
test "with_param replaces a differently cased name in place" {
  let params = tel_params(";type=cell;PREF=1")
  let updated = @params.with_param(params, "TYPE", ["voice"])
  assert_eq(@params.render(updated), "TYPE=voice;PREF=1")
}

///|
test "with_param keeps later parameters that repeat the name" {
  let params = tel_params(";TYPE=cell;TYPE=voice")
  let updated = @params.with_param(params, "TYPE", ["fax"])
  assert_eq(@params.render(updated), "TYPE=fax;TYPE=voice")
}

///|
test "with_param does not mutate the input" {
  let params = tel_params(";TYPE=cell")
  let _ = @params.with_param(params, "PREF", ["1"])
  assert_eq(@params.render(params), "TYPE=cell")
}

///|
test "without drops every parameter with the name" {
  let params = tel_params(";TYPE=cell;PREF=1;TYPE=voice")
  let kept = @params.without(params, "type")
  assert_eq(kept.length(), 1)
  assert_eq(@params.render(kept), "PREF=1")
}

///|
test "without keeps the order of the remaining parameters" {
  let params = tel_params(";A=1;B=2;C=3")
  let kept = @params.without(params, "b")
  assert_eq(@params.render(kept), "A=1;C=3")
}

///|
test "without does not mutate the input" {
  let params = tel_params(";TYPE=cell")
  let _ = @params.without(params, "TYPE")
  assert_eq(params.length(), 1)
}

///|
test "merge keeps left order and appends right-only names" {
  let left = tel_params(";TYPE=cell;PREF=1")
  let right = tel_params(";EMAIL=x;type=voice")
  let merged = @params.merge(left, right)
  assert_eq(@params.render(merged), "TYPE=cell,voice;PREF=1;EMAIL=x")
}

///|
test "merge does not repeat a value that both sides carry" {
  let left = tel_params(";TYPE=cell,voice")
  let right = tel_params(";TYPE=cell,voice,fax")
  let merged = @params.merge(left, right)
  assert_eq(merged.length(), 1)
  assert_eq(merged[0].values, ["cell", "voice", "fax"])
}

///|
test "merge of two empty lists is empty" {
  assert_eq(@params.merge([], []).length(), 0)
}

///|
test "merge with an empty right side copies the left side" {
  let left = tel_params(";TYPE=cell")
  let merged = @params.merge(left, [])
  assert_eq(@params.render(merged), "TYPE=cell")
  merged[0].values.push("voice")
  assert_eq(left[0].values, ["cell"])
}

///|
test "merge with an empty left side copies the right side" {
  let right = tel_params(";TYPE=cell")
  let merged = @params.merge([], right)
  assert_eq(@params.render(merged), "TYPE=cell")
}

///|
test "sorted orders by uppercased name and keeps equal names stable" {
  let params = tel_params(";B=1;a=2;b=3")
  let ordered = @params.sorted(params)
  assert_eq(@params.render(ordered), "a=2;B=1;b=3")
}

///|
test "sorted does not mutate the input" {
  let params = tel_params(";B=1;A=2")
  let _ = @params.sorted(params)
  assert_eq(@params.render(params), "B=1;A=2")
}

///|
test "sorted of an empty list is empty" {
  assert_eq(@params.sorted([]).length(), 0)
}

///|
test "render writes a name with its values" {
  let params = tel_params(";TYPE=cell,voice;PREF=1")
  assert_eq(@params.render(params), "TYPE=cell,voice;PREF=1")
}

///|
test "render writes a bare parameter as its name" {
  assert_eq(@params.render(tel_params(";PREF")), "PREF")
}

///|
test "render of an empty list is empty text" {
  assert_eq(@params.render(tel_params("")), "")
}

///|
test "canonical uppercases names and keeps trimmed values" {
  let params = tel_params(";type= cell ")
  let canonical = @params.canonical(params)
  assert_eq(canonical.length(), 1)
  assert_eq(canonical[0].name, "TYPE")
  assert_eq(canonical[0].values, ["cell"])
}

///|
test "canonical drops values that are empty after trimming" {
  let canonical = @params.canonical(tel_params(";TYPE= "))
  assert_eq(canonical.length(), 1)
  assert_eq(canonical[0].name, "TYPE")
  assert_eq(canonical[0].values.length(), 0)
}

///|
test "canonical leaves the input untouched" {
  let params = tel_params(";type=cell")
  let _ = @params.canonical(params)
  assert_eq(params[0].name, "type")
}
