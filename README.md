# Moon vCard

MoonBit library for offline reading and writing of common vCard 3.0 and 4.0 contact text. It handles multiple cards in one input, folded lines, text escapes, `FN`, `N`, `TEL`, and `EMAIL`. Parsing returns accepted contacts alongside diagnostic codes. No network or platform contact permissions are required.

## Install and run

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and run these commands from this directory:

```sh
moon check --deny-warn --target all
moon build --target wasm
moon test --deny-warn --target wasm
moon run --target wasm examples/demo
```

The package is published on mooncakes.io as [`haol-05/moon-vcard`](https://mooncakes.io/docs/haol-05/moon-vcard). From another module, add it and import it under the same name:

```sh
moon add haol-05/moon-vcard
```

## Use

```moonbit
let result = parse("BEGIN:VCARD\nVERSION:4.0\nFN:Alice Smith\nN:Smith;Alice;;;\nEND:VCARD")
for contact in result.contacts {
  println(contact.full_name)
  let normalized = format(contact)
}
```

`parse` accepts LF or CRLF input and returns diagnostics such as `missing-fn:4`, `invalid-version:4`, or `unclosed-card`. `format` returns a CRLF-terminated vCard when the version and full name are valid. Review `diagnostics` before importing contacts into an address book.

## Scope

This is a deliberately small text-field core, not full RFC 6350 coverage. It does not decode quoted-printable, base64 photos, charset parameters, groups, or arbitrary `VALUE` types. Unknown properties are ignored. Serialization writes the supported fields and does not preserve unsupported fields or parameter metadata. Test data contains fictional contacts only.

## Related work

The implementation refers to the public [RFC 6350](https://www.rfc-editor.org/rfc/rfc6350) and [vCard 3.0 RFC 2426](https://www.rfc-editor.org/rfc/rfc2426) format descriptions; it does not copy parser code. MIT license.

A GitHub repository search for `moonbit vcard`, `vcard moonbit` and `moonbit contacts` returned no matching repository on 2026-09-25. A mooncakes.io search for `vcard` on the same date returned one package, `angela/vcf@0.0.5` ("Parse vCard strings", Apache-2.0, last published 2026-01-12). Reading that package's source showed it parses a single vCard, accepts only `VERSION:3.0`, and rejects an input holding more than one card; it does not unfold folded lines or decode text escapes, it keeps `println` debug output inside `parse` and `validate`, its tests are the toolchain template's `fib`/`sum` rather than vCard cases, and its manifests still use the older `moon.mod.json`/`moon.pkg.json` form. Moon vCard differs by accepting multiple cards, both 3.0 and 4.0, folded lines and text escapes, non-fatal diagnostics, and CRLF serialization, with no third-party dependency. Both searches are limited and are not proof of uniqueness. See [申报书.md](申报书.md).

## Environment note

Locally verified on 2026-09-25 with moon 0.1.20260807 on Windows: `moon check --deny-warn --target all`, `moon build` and `moon test --deny-warn` on `wasm`, `wasm-gc` and `js` (5 tests each), and the demo through `moon run`. The `native` target does not build on that host because the toolchain's own runtime source `<moon-home>/lib/runtime/env.c` calls `rand_s` without a declaration; a two-line test package fails identically, so this is a toolchain issue on that machine, not a defect in this library.

GitHub Actions runs the same steps on `ubuntu-latest` with the latest released toolchain (moon 0.1.20260920 at the time of writing), including the `native` target, and passes. Note that `moon fmt` output can differ between toolchain releases: 0.1.20260807 strips the trailing comma of an untagged struct literal while 0.1.20260920 keeps it, so this repository stores the form produced by the newer release that CI installs.
