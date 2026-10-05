# YAML and TOML Plan

Branch: `feature/yaml_toml`

Goal: convert property lists to and from YAML and TOML, as Satimage's `PlistToJSON` and `PlistFromJSON` do for JSON. This is an MTC_OSAX extension: SatimageOSAX had neither format. Noted in [PLAN.md](../PLAN.md) on 2026-09-28, with the TOML decisions below.

## Commands

Four commands, named like Satimage's JSON pair, so their names are distinctive enough not to reserve common words:

```applescript
set p to PlistNew {person:"Ann", tags:{"a", "b"}, address:{city:"Paris"}}
PlistToYAML p
--> "person: Ann
--   tags:
--   - a
--   - b
--   address:
--     city: Paris
--   "
PlistToTOML p
--> "person = \"Ann\"
--   tags = [\"a\", \"b\"]
--
--   [address]
--   city = \"Paris\"
--   "
set q to PlistFromYAML "name: Ann" in pool "mine"
set r to PlistFromTOML "name = \"Ann\""
```

- **`PlistToYAML <CFRef>`, `PlistToTOML <CFRef>`:** the text of the element (a whole document or any element in one), ending with a line break.
- **`PlistFromYAML <text>`, `PlistFromTOML <text>`:** a new property list document, its CFRef; `in pool` as for `PlistFromJSON`.
- Keys are written in the same order as `PlistToJSON` writes them (the property list's own order).

## Files (decision 12)

All six conversion commands, Satimage's JSON pair included, can read or write a file directly:

```applescript
PlistToJSON p in (POSIX file "/path/data.json")       -- writes the file, returns nothing
PlistToYAML p in "/path/data.yaml"                    -- a POSIX path works too, as for PlistSave
set p to PlistFromTOML (POSIX file "/path/data.toml") -- a file reference: read it
set p to PlistFromJSON "{\"a\":1}"                    -- text: always the JSON itself, as in Satimage
```

- **Writing:** `PlistToJSON`, `PlistToYAML` and `PlistToTOML` take `in` (`kfil`, the term and code of `PlistSave … in`): a file reference or a POSIX path. The file is written in UTF-8, replacing one that's there, and the command returns nothing. A folder that doesn't exist is error -1, as for `PlistSave`.
- **Reading:** `PlistFromJSON`, `PlistFromYAML` and `PlistFromTOML` take a file reference (`POSIX file`, an alias, a file URL) as the direct parameter and read it as UTF-8. Text is always the document itself, never a path, so existing scripts behave as before. A missing file is error -43, as for `PlistOpen`; a file that isn't UTF-8 is error -1.
- **Satimage's commands:** `in` is a new parameter on `PlistToJSON`, and a file is newly accepted by `PlistFromJSON`, where SatimageOSAX gave an error. The SDEF consistency test allows `in` on `PlistToJSON` only; the README's differences section lists both.

## TOML (decided)

| Property list | TOML |
|---|---|
| Dictionary | Table: keys with simple values first, then sub-tables as `[a.b]`, arrays of dictionaries as `[[a]]` |
| Array | Array (inline); an array of dictionaries is an array of tables |
| Text, integer, real, boolean | String (escaped, `"…"`), integer, float (`inf`, `nan` included), boolean |
| Date | Offset date-time in UTC with whole seconds, `2026-09-28T14:30:00Z`, as `PlistToJSON` writes dates |
| Data | Base64 text, as `PlistToJSON` writes data |
| `missing value` in a table | A comment, `# key = NULL` |

Errors (-50, with a message saying why): a top level that isn't a dictionary, and `missing value` in an array.

Reading, `PlistFromTOML`: tables are dictionaries, arrays are arrays, and the scalars map back as above. An offset date-time is that moment; a local date-time or local date is read in the Mac's time zone (a date alone is midnight); a local time is text (`"14:30:00"`). Comments are ignored, like any TOML reader, so a key written as `# key = NULL` is simply absent. Text that isn't TOML is error -1, with the parser's message (line and column).

## YAML

| Property list | YAML |
|---|---|
| Dictionary, array | Block mapping, block sequence (two-space indentation); empty ones as `{}` and `[]` |
| Text | Plain when it can't be read as anything else, otherwise quoted |
| Integer, real, boolean | As YAML 1.2 writes them (`.inf`, `.nan`, `true`, `false`) |
| `missing value` | `null` |
| Date | Plain, in UTC with whole seconds: `2026-09-28T14:30:00Z` |
| Data | `!!binary`, base64 under YAML's binary tag |

Reading, `PlistFromYAML`, with YAML 1.2's rules (decision 8): only `true`/`false` are booleans, so `yes`, `no`, `on` and `off` stay text. An unquoted value that looks like a YAML timestamp (`2026-09-28`, `2026-09-28T14:30:00Z`, `2026-09-28 14:30:00`) is a date, and one without a zone is read in the Mac's time zone; quoted, it's text (decision 9). `!!binary` is data (decision 10). Several documents in one text (separated by `---`) are error -50 (decision 11). Mappings are dictionaries (keys that are numbers or booleans become text; a key that's a mapping or sequence is error -50), sequences are arrays, `null` and `~` are `missing value`, anchors and aliases are expanded, and merge keys (`<<`) merge. Text that isn't YAML is error -1, with the parser's message (line and column).

## Dictionary

A new visible suite, "MTC_OSAX Property List Formats" (event class `MTCp`), next to Satimage's PropertyList suite:

| Command | Code | Parameters |
|---|---|---|
| `PlistToYAML` | `MTCpTYML` | direct: a CFRef |
| `PlistFromYAML` | `MTCpFYML` | direct: text; `in pool` (`pool`) |
| `PlistToTOML` | `MTCpTTML` | direct: a CFRef |
| `PlistFromTOML` | `MTCpFTML` | direct: text; `in pool` (`pool`) |

`in pool` reuses the term and code Satimage's commands have. The SDEF consistency test treats `MTCp` as MTC_OSAX's own.

## Architecture

- **Parsers** (decision 7): libyaml 0.2.5 (MIT) for YAML and tomlc17 (MIT, TOML 1.1, release R260821) for TOML, vendored as C sources in `Sources/CYAML` and `Sources/CTOML`, as Onigmo and PCRE2 are. Their licenses go in the README's "Third-party code".
- **Writers** are ours, in Swift: YAML and TOML output is simple, and writing it ourselves gives the exact format above (key order, quoting, the `# key = NULL` comment), which the libraries don't.
- **`Sources/PropertyLists/YAML.swift` and `TOML.swift`**, beside `JSON.swift`: converting between the parsers' trees and property list values, and the writers. The commands are registered with the other PropertyList commands.
- `missing value` is recognized the way `PlistFromJSON` stores it (data holding AppleScript's `missing value`).

## Testing

- Unit tests: each value type both ways, round trips, key order, quoting and escaping, the TOML table layout and the `# key = NULL` comment, dates in each TOML form, YAML anchors, aliases and merge keys, and each error.
- Fixtures recorded from MTC_OSAX in `Fixtures/PropertyListsFormats` (Satimage has nothing to compare against).
- End to end: `Scripts/e2e/plists-formats.applescript` (MTC_OSAX only).
- Parser conformance: valid and invalid cases from the TOML 1.1 and YAML 1.2 specifications, in the unit tests.

## Order of work

1. Vendor the parsers; build and a smoke test.
2. TOML: reading and writing, with unit tests.
3. YAML: reading and writing, with unit tests.
4. The commands and the SDEF suite; fixtures and the e2e script.
5. README: "New features" in "Differences from SatimageOSAX", and the parsers under "Third-party code".

## Done when

- [x] The four commands work, with the formats and errors above.
- [x] Round trips keep every value that each format can hold.
- [x] Unit tests, fixtures and the e2e script pass; all existing tests still pass.
- [x] README updated, including the differences and third-party sections.
- [x] Files (decision 12): the six commands read and write files, with unit tests, fixtures and e2e checks; the README lists it.

## Findings

- **Record keys in examples:** `PlistNew {name:…}` stores the key as `«class pnam»`, because `name` is a dictionary term (as in Satimage); `list` and `items` likewise. The examples and fixtures use plain keys (`person`, `sample`).
- **libyaml tags untagged scalars `!!str`,** so a plain scalar with an explicit `!!str` is still resolved (`!!str 123` reads as 123); quoted scalars are always text.
- **YAML text that YAML 1.1 readers take for booleans** (`yes`, `no`, `on`, `off`, `y`, `n`) is written quoted, so older readers get text too.
- **Recording:** the fixtures check dates through `PlistToJSON` text and use only dates with a zone, so replays don't depend on the Mac's time zone; local-zone dates are in the unit tests, with an explicit zone.
- Recorded from MTC_OSAX in `Fixtures/PropertyListsFormats` (25 cases, 6 of them files); `Scripts/e2e/plists-formats.applescript` (17 checks).
- **Files:** a UTF-8 byte order mark at the start of a file is skipped. Satimage's JSON fixtures all still pass: `PlistFromJSON` of text behaves as before.

## Decisions

Made 2026-09-28 (TOML):

1. A top level that isn't a table is an error.
2. `missing value` in a table is written as the comment `# key = NULL`; in an array it's an error.
3. `PlistFromTOML` ignores comments, like any TOML reader.
4. Data is base64 text, as in `PlistToJSON`.
5. Dates are written in UTC with whole seconds (`2026-09-28T14:30:00Z`).
6. A local date-time or local date is read in the Mac's time zone (a date alone is midnight); a local time is read as text.

Made 2026-09-28 (YAML and libraries):

7. libyaml 0.2.5 and tomlc17 are vendored as C sources, as Onigmo and PCRE2 are (no package dependencies).
8. YAML 1.2's rules: only `true`/`false` are booleans and only `null`/`~` are null.
9. YAML dates are written plain in UTC; an unquoted timestamp is read as a date (without a zone, in the Mac's time zone), a quoted one as text.
10. YAML data is written and read as `!!binary`.
11. Several YAML documents in one text are error -50.

Made 2026-09-28 (files):

12. The six conversion commands read and write files: `in` (a file or POSIX path) on the three `PlistTo…` commands, and a file reference as the direct parameter of the three `PlistFrom…` commands, whose text stays the document itself.
