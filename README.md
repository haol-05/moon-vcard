# Moon vCard

MoonBit library for offline reading and writing of common vCard 3.0 and 4.0 contact text. It handles multiple cards in one input, folded lines, text escapes, quoted-printable values, `FN`, `N`, `TEL`, `EMAIL`, and the attribute parameters written on those lines (`TYPE`, `PREF`, and others). Parsing returns accepted contacts alongside diagnostic codes. No network or platform contact permissions are required.

## Install and run

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and run these commands from this directory:

```sh
moon check --target all
moon build --target wasm
moon test --target wasm
moon run --target wasm examples/demo
```

The package is published on mooncakes.io as [`haol-05/moon-vcard`](https://mooncakes.io/docs/haol-05/moon-vcard). From another module, add it and import it under the same name:

```sh
moon add haol-05/moon-vcard
```

## Use

```moonbit
let card = "BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nTEL;TYPE=cell;PREF=1:+8613800000000\nEND:VCARD"
let result = parse(card)
for contact in result.contacts {
  println(contact.full_name)
  for phone in contact.phones {
    println(phone.value)
    for param in phone.params {
      println(param.name + "=" + param.values.join(","))
    }
  }
  let normalized = format(contact)
}
```

`parse` accepts LF or CRLF input and returns diagnostics such as `missing-fn:4`, `invalid-version:4`, `invalid-quoted-printable:3`, `unsupported-charset:3`, or `unclosed-card`. `format` returns a CRLF-terminated vCard when the version and full name are valid, and writes the parameters back on the same line. Review `diagnostics` before importing contacts into an address book.

Each `TEL` and `EMAIL` line becomes a `Field`:

| Type | Fields | Meaning |
| --- | --- | --- |
| `Field` | `value`, `params` | one property value together with the parameters on its line |
| `Param` | `name`, `values` | one parameter; `values` is empty for a bare parameter such as `;PREF`, and holds one entry per comma-separated value otherwise |

Use `sort_by_preference` when a card carries several numbers or addresses and the caller wants the preferred one first. It orders numeric `PREF` values ascending, puts fields without a usable `PREF` last, keeps the original order within each group, and leaves the parsed array untouched:

```moonbit
let ordered = sort_by_preference(result.contacts[0].phones)
println(ordered[0].value)
```

## API change in 0.2.0

`Contact.phones` and `Contact.emails` are `Array[Field]` instead of `Array[String]`: read `contact.phones[0].value` where 0.1.x code read `contact.phones[0]`. Parameters such as `TYPE` and `PREF` are preserved and written back instead of being dropped.

## Scope

This is a deliberately small text-field core, not full RFC 6350 coverage. It keeps the parameters of `TEL` and `EMAIL` lines, including quoted values such as `TYPE="work,voice"`, and writes them back. Values marked `ENCODING=QUOTED-PRINTABLE` are decoded, soft line breaks included, and the consumed `ENCODING` parameter is dropped so that the written line never claims an encoding the value no longer has; `format` never re-encodes quoted-printable. Only UTF-8 and ASCII are decoded: a `CHARSET` naming anything else reports `unsupported-charset` and its bytes are decoded as UTF-8 with replacement characters rather than silently guessed. Base64 payloads, property groups such as `item1.TEL`, and the parameters of `FN` or `N` are not supported, and unknown properties are ignored. Serialization writes the supported fields only. Test data contains fictional contacts only.

## Related work

The implementation refers to the public [RFC 6350](https://www.rfc-editor.org/rfc/rfc6350) and [vCard 3.0 RFC 2426](https://www.rfc-editor.org/rfc/rfc2426) format descriptions; it does not copy parser code. MIT license.

A GitHub repository search for `moonbit vcard`, `vcard moonbit` and `moonbit contacts` returned no matching repository on 2026-09-25. A mooncakes.io search for `vcard` on the same date returned one package, `angela/vcf@0.0.5` ("Parse vCard strings", Apache-2.0, last published 2026-01-12). Reading that package's source showed it parses a single vCard, accepts only `VERSION:3.0`, and rejects an input holding more than one card; it does not unfold folded lines or decode text escapes, it keeps `println` debug output inside `parse` and `validate`, its tests are the toolchain template's `fib`/`sum` rather than vCard cases, and its manifests still use the older `moon.mod.json`/`moon.pkg.json` form. Moon vCard differs by accepting multiple cards, both 3.0 and 4.0, folded lines and text escapes, non-fatal diagnostics, and CRLF serialization, with no third-party dependency. Both searches are limited and are not proof of uniqueness. See [申报书.md](申报书.md).

## Environment note

Locally verified on 2026-09-25 with moon 0.1.20260807 on Windows: `moon check --target all`, `moon build` and `moon test` on `wasm`, `wasm-gc` and `js` (14 tests each), and the demo through `moon run`. With that release `moon check --deny-warn --target all` also reports zero warnings. The `native` target does not build on that host because the toolchain's own runtime source `<moon-home>/lib/runtime/env.c` calls `rand_s` without a declaration; a two-line test package fails identically, so this is a toolchain issue on that machine, not a defect in this library.

GitHub Actions runs the same steps on `ubuntu-latest` with the latest released toolchain (moon 0.1.20260920 at the time of writing), including the `native` target, and passes. Two differences between toolchain releases are worth knowing:

- `moon fmt` output differs: 0.1.20260807 strips the trailing comma of an untagged struct literal while 0.1.20260920 keeps it, so this repository stores the form produced by the newer release that CI installs.
- 0.1.20260920 adds `implicit_impl_as_method` deprecation warnings for the trait methods that `derive(Eq, Debug)` promotes on public types, so `moon check --deny-warn` reports them there. The documented commands therefore match what CI runs; the derivations themselves are kept because they are part of the public API.
