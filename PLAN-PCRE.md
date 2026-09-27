# PCRE Engine Plan

Branch: to be created (e.g. `feature/pcre`), after `feature/text_tools` is merged.

Goal: offer PCRE as an alternative regular expression engine in the Text Additions commands, chosen per call or as an app-wide default. This is an MTC_OSAX extension: Satimage only has Onigmo. Nothing changes for scripts that don't ask for PCRE.

## Scope

The commands that take a regex: `find text`, `change`, `splittext`, `filter text` and `re_compile`. Later suites that search text (XML, File Additions) can use the same switch.

## How PCRE is selected

The existing `syntax` parameter, with a new value `"PCRE"`.

```applescript
change "(\\w+)@(\\w+)" into "\\2 at \\1" in theText with regexp syntax "PCRE"
```

- It adds no new term, so no word becomes reserved in scripts (a new `engine` parameter would make `engine` reserved in every script that uses MTC_OSAX).
- It can't clash with existing scripts: Satimage rejects unknown syntaxes with error -1.
- `re_compile … syntax "PCRE"` checks a PCRE pattern.

App-wide default syntax, like `DollarReferences`: `defaults write com.mactechnologies.mtc-osax RegexSyntax PCRE`. Any syntax name is accepted (`PCRE`, `RUBY`, `PERL`, …); an unknown one is ignored, so the default stays `RUBY`. An explicit `syntax` always wins, so `syntax "RUBY"` forces Onigmo when the default is PCRE. Not set by default, so existing scripts behave as with Satimage.

## PCRE's behavior

PCRE keeps its own semantics; the point of choosing it is to get PCRE, not Ruby, behavior:

- `^` and `$` match only at the start and end of the text unless `(?m)` or the `MULTILINE` flag (PCRE's meaning) is used; `.` doesn't match newlines unless `(?s)`.
- `\h` is horizontal white space; `\d`, `\w`, `\s` and POSIX classes are Unicode-aware (`PCRE2_UCP`).
- Line ends: any Unicode line ending by default (`PCRE2_NEWLINE_ANY`): LF, CR, CR LF (as one), vertical tab, form feed, NEL, LS and PS. A pattern can still choose otherwise with PCRE's own start-of-pattern settings, e.g. `(*LF)` or `(*CRLF)`.
- Named groups `(?<name>…)`, lookbehind, possessive quantifiers, `\K`, recursion and so on, as PCRE documents them.

Positions stay in UTF-16 units, as with Onigmo: PCRE2 is built for 16-bit code units, so its offsets map directly.

### `regexpflag` with PCRE

Flag names keep their PCRE meaning when PCRE is selected:

| Flag | PCRE option |
|---|---|
| `IGNORECASE` | `PCRE2_CASELESS` (also from `without case sensitive`) |
| `EXTEND` | `PCRE2_EXTENDED` |
| `MULTILINE` | `PCRE2_MULTILINE`: `^`/`$` at every line (not Onigmo's "dot matches newline") |
| `SINGLELINE`, `DOTALL` | `PCRE2_DOTALL`: `.` matches newlines |
| `FIND NOT EMPTY` | `PCRE2_NOTEMPTY` |
| `NOTBOL`, `NOTEOL` | match options of the same names |
| `DONT CAPTURE GROUP` | `PCRE2_NO_AUTO_CAPTURE` |
| `DOLLAR REFERENCES` | unchanged (templates are ours, not the engine's) |
| `FIND LONGEST`, `NEGATE_SINGLELINE`, `NEWLINE IN NEGATIVE CC` | error -1: no PCRE equivalent |

### Errors

Compile errors return a PCRE-specific number and PCRE's message, e.g. `-3000 - code` so they can't be confused with Onigmo's codes (which are -100…-400), with `errs` set to PCRE's text including the offset in the pattern.

## Architecture

- **`Sources/CPCRE2`:** PCRE2 (current 10.4x release, BSD license), 16-bit code units only, JIT off. Only the library sources needed; `config.h` and `pcre2.h` generated once and checked in, as for Onigmo. License noted in the README.
- **`TextMatching`:** a small protocol for a compiled pattern (group count, named groups, first match from/within), implemented by the existing Onigmo `CompiledRegex` and a new `PCRERegex`. `RegexCache` keys on the syntax, which now includes the engine.
- **`TextAdditions`:** `SearchOptions` reads `syntax` and the app-wide `RegexSyntax` default (injectable for tests, like `DollarReferences`); `TextSearcher` asks the cache for the right engine. Templates, iteration (including the empty-match rules), list input and files are unchanged.
- **JIT:** not in the first version. Enabling it later needs the `com.apple.security.cs.allow-jit` entitlement under the hardened runtime.

## Testing

- Unit tests for `PCRERegex`: UTF-16 offsets (emoji, combining marks), groups and named groups, each flag mapping, the line-end setting, errors, and the cache keeping engines apart.
- The same behaviors through the commands: `find text`, `change`, `splittext`, `filter text`, `re_compile` with `syntax "PCRE"`, and the app-wide default with an explicit `syntax` overriding it.
- Fixtures recorded from MTC_OSAX in `Fixtures/TextAdditionsPCRE/` (Satimage has nothing to compare against), including patterns that behave differently under the two engines (`^` without `(?m)`, `\h`, `\w` with accents).
- A check that every existing fixture still passes: the default engine must not change.
- End to end: `Scripts/e2e/text-pcre.applescript` (MTC_OSAX only).

## Order of work

1. Vendor PCRE2 as `CPCRE2`; build and a smoke test.
2. The engine protocol in `TextMatching`, with Onigmo moved behind it; all existing tests still pass.
3. `PCRERegex` with flag mapping and errors; unit tests.
4. `syntax "PCRE"` and the app-wide default in the commands; tests and fixtures.
5. README and dictionary descriptions (the `syntax` parameter's description lists `"PCRE"` as an MTC_OSAX extension).

## Done when

- [ ] `syntax "PCRE"` works in all five commands, and the app-wide default works and is overridable.
- [ ] Flag mapping and errors as above, with unit tests.
- [ ] PCRE fixtures recorded from MTC_OSAX; all existing fixtures still pass.
- [ ] End-to-end PCRE checks pass.
- [ ] PCRE2's license included and noted in the README.

## Decisions

Made 2026-09-27:

1. PCRE is selected with `syntax "PCRE"`; no new parameter.
2. `regexpflag` names take PCRE's meaning when PCRE is selected.
3. Any line ending counts by default (`PCRE2_NEWLINE_ANY`).
4. An app-wide default syntax (`RegexSyntax`), overridden by an explicit `syntax`.
