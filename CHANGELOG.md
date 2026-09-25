# Changelog

Notable changes to this project, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each entry names the GitHub issue that carried the work, and every change is visible in the repository history and in the merged pull requests.

## 0.2.0 - 2026-09-25

### Added

- `Field` and `Param` types, and keep-and-write-back of the parameters on `TEL` and `EMAIL` lines: `TYPE=cell,voice` multi-values, bare `;PREF`, and quoted values such as `TYPE="work,voice"` (#1).
- Quoted-printable decoding for `ENCODING=QUOTED-PRINTABLE` values, soft line breaks included, so vCard 3.0 exports with non-ASCII text parse correctly (#2).
- `sort_by_preference`, a stable ordering of multi-value fields by numeric `PREF` (#3).
- Diagnostics `invalid-quoted-printable:<line>` and `unsupported-charset:<line>`; unsupported charsets are reported instead of being guessed (#2).
- The demo now prints parameters, a quoted-printable decoded name and `PREF` order (#7).

### Changed

- **Breaking:** `Contact.phones` and `Contact.emails` are `Array[Field]` instead of `Array[String]`. Read `contact.phones[0].value` where 0.1.x code read `contact.phones[0]` (#1).
- Values decoded from quoted-printable drop the consumed `ENCODING` parameter, and `format` never re-encodes quoted-printable (#2).
- `moon.pkg` imports the `moonbitlang/core/debug` package that ships with the toolchain; the library still has no third-party dependency (#8).
- Public types declare the trait methods that `derive(Eq, Debug)` promotes, as the newest toolchain requires, so both the local and the CI toolchain report no warnings (#8).

## 0.1.1 - 2026-09-25

### Changed

- Documentation: Mooncakes publication details, local and CI verification results, and the `moon fmt` difference between toolchain releases are recorded in the README and the proposal.

## 0.1.0 - 2026-09-25

### Added

- First release: `parse` reads several vCard 3.0/4.0 cards in one input with folded lines, text escapes, `FN`, `N`, `TEL` and `EMAIL`, returning accepted contacts next to non-fatal diagnostics; `format` writes the supported fields as CRLF-terminated vCard text.
- Unit tests, a runnable demo, README, CI and an MIT license.
