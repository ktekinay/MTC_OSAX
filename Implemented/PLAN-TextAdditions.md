# Text Additions Plan

Branch: `feature/text_tools`

Goal: implement the **Satimage Text Additions** suite (priority 1 in [PLAN.md](../PLAN.md)) so that scripts using these commands behave the same with `use application "MTC_OSAX"` as with SatimageOSAX.

## Scope

All 25 commands of the suite, plus its `matchrecord` record type:

| Group | Commands |
|---|---|
| Search and replace | `find text`, `change`, `splittext`, `re_compile`, `filter text` |
| Files | `readtext`, `writetext`, `file offset` |
| Case | `uppercase`, `lowercase`, `titlecase` (synonym `capitalize`) |
| Numbers | `format`, `atof`, `atoi` |
| XML and URLs | `encode entities`, `resolve entities`, `escapeURL`, `unescapeURL` |
| Unicode | `normalize unicode`, `transform unicode`, `hash` |
| Formatting | `join`, `printf`, `strftime`, `strptime` |

Not in scope: the hidden legacy commands (`find text obsolete`, `replace obsolete`, etc.), which stay in "May Do Later".

## What we know about Satimage's behavior

Checked against the running SatimageOSAX on 2026-09-27:

- **Regular expressions use Onigmo** (the Ruby fork of Oniguruma), linked statically. Evidence:
  - The binary contains Onigmo's version banner ("Onigmo %d.%d.%d : Copyright (C) 2002-2009 K.Kosako, 2011-2013 K.Takata") and imports no other regex library (no POSIX `regcomp`, ICU `uregex` or PCRE).
  - Six behaviors only Onigmo's Ruby syntax shows together: `\h` is a hex digit; `^` matches at every line; conditionals `(?(1)b|c)` work; class intersection `[a-z&&[^aeiou]]` works; `(?m)` makes `.` match newlines; `syntax "GREP"` accepts `\(…\)`.
  - The `syntax` names (`RUBY`, `PERL`, `JAVA`, `GNU_REGEX`, …) and `regexpflag` names (`FIND LONGEST`, `NEGATE_SINGLELINE`, …) are Onigmo's own options.
- **Match positions are 0-based UTF-16 offsets**, in both literal and regex searches: in `"😀b"` and in `"e" & (combining acute) & "b"`, `b` is at 2. This is the same indexing as `NSString`.
- **`hash`** = `CFHash` of the NFKD-normalized string, low 24 bits (`& 0xFFFFFF`). Matches for `""`, `"abc"`, `"ABC"` and `"abd"`.
- **Text results are `ut16`** (see the initial framework's findings); replay treats text encodings as equal.
- **Standard errors** (-1700, -1701) come back with no message.
- **`find text` with no match** makes AppleScript report -2763 ("No result was returned"). The fixtures will show exactly what Satimage replies (an empty reply or a specific error).

## How your scripts use it

From the 53 scripts in `~/Documents/AppleScript Projects` that could be decompiled (4 more use formats macOS can no longer read), 19 use Satimage. Most were compiled against the old Satimage.osax and call it by raw code. Text commands dominate:

| Command | Uses | Scripts |
|---|---|---|
| `change` | 25+ | nearly all |
| `find text` | 12+ | Copy SuperPages Data, Email Web Page, Fix/Organize iChat Transcript, Kill minirosetta, Parse Bailamos, Paste URL Into Forum, Process SpamCop, Verify websites |
| `join` | 6 | Fix iChat Transcript Dates, Recreate Folders in Mail, Verify websites |
| `splittext` | 4 | Fix iChat Transcript Dates, Parse Bailamos Dance Events |
| `resolve entities` | 4 | Email Web Page |

No other text commands appear. Outside this suite: PropertyList commands (`PlistOpen`, `PlistFromJSON`, `PlistChild`, `PlistGet`, `PlistCount`, `PlistClose`) in 2 scripts, XML DOM commands in 1, and `abs` in 1.

What the scripts depend on, so the fixtures must cover it first:

- **`find text` raises an error when nothing matches.** Scripts use `try … on error` as the "not found" branch (e.g. `ExtractWithPattern` returns `""`, Verify Website treats the error as "site is down"), and Paste URL Into Forum repeats `find text` until it errors. The exact error Satimage returns decides this; it's the first thing to record.
- `find text` forms: `with regexp and string result … using "\\1"`; `all occurrences`; `without case sensitive`; `regexpflag {"MULTILINE"}`; the full `matchrecord` (`mPos`/`mLen`/`mRes` used for text arithmetic); templates with literal line breaks (`"\\1" & return & "\\2"`).
- `change` forms: literal (`change return into linefeed`); regex with back-references (`"\\1\\r\\r\\3"`); **escapes in the replacement** (`into "\\r"` produces a carriage return); empty replacement; `without case sensitive`; replacement text built at run time.
- Regex features: `\s`, `[\s\S]`, `\A`, `\z`, `\Z`, lazy `.*?`, lookahead `(?!…)`, non-capturing groups, `[[:alnum:]]`, `\d{1,3}`, `\u0020` escapes, and `^`/`$` at line boundaries (e.g. `"^ *(\\d+) [^\\r\\n]+minirosetta"` against `ps` output).
- `splittext` with a literal separator and with a case-insensitive regex; `join` with `""`, `"-"`, `"/"`.

The fixture cases will include each of these call shapes, with inputs similar to what the scripts process (HTML fragments, `ps` output, file names).

## Architecture

### Modules

```
Packages/MTCOSAXKit/
  Sources/COnigmo/          vendored Onigmo C source (BSD 2-clause), built as a C target
  Sources/TextMatching/     Swift wrapper around Onigmo + literal search + shared option handling
  Sources/TextAdditions/    the 25 commands
```

`TextMatching` is separate from the commands because the File, XML and later suites also search text.

### Onigmo

- Vendor **Onigmo 6.2.0** (current release) as a C target with only the files needed (core engine, UTF-8/UTF-16 encodings, Unicode tables). Satimage used a 5.x release; the fixtures will show any behavior that changed.
- Search the text as **UTF-16LE** (`ONIG_ENCODING_UTF16_LE`) so match offsets divided by 2 are exactly Satimage's positions and `NSString` ranges, with no conversion.
- Map `syntax` to `OnigSyntaxRuby` (default), `OnigSyntaxPerl`, `OnigSyntaxJava`, `OnigSyntaxGnuRegex`, `OnigSyntaxGrep`, `OnigSyntaxEmacs`, `OnigSyntaxPosixBasic`, `OnigSyntaxPosixExtended`.
- Map `regexpflag` to Onigmo options: `IGNORECASE`, `EXTEND`, `MULTILINE`, `SINGLELINE`, `FIND LONGEST`, `FIND NOT EMPTY`, `NEGATE_SINGLELINE`, `DONT CAPTURE GROUP`, `NOTBOL`, `NOTEOL`, `NEWLINE IN NEGATIVE CC`. Satimage's spelling varies (spaces vs underscores), so accept both.
- Compiled patterns are cached (keyed by pattern, syntax and options), since scripts often call `find text` in loops.

### Shared matching options

`find text`, `change`, `splittext` and `filter text` share most parameters. One `MatchOptions` type reads them all once:

| Parameter | Code | Notes |
|---|---|---|
| `case sensitive` | `CaSe` | default true |
| `regexp` | `UsGR` | default false |
| `diacritic sensitive` | `DiSe` | literal only |
| `whole word` | `WhWo` | literal only |
| `backward` | `back` | `find text` only, literal only |
| `regexpflag` | `Flag` | list of flag names |
| `syntax` | `synt` | default `RUBY` |
| `options` | `Opti` | shortcut letters: `a` all occurrences, `r` regexp, `s` string result, `c` not case sensitive, `d` not diacritic sensitive |
| `starting at` / `for` | `strt` / `for ` | restrict the search to a range |

Literal searches use `NSString.range(of:options:range:)` with case, diacritic and backward options, plus a word-boundary check for `whole word`. Whether Satimage's literal search treats canonically equivalent text as equal (precomposed vs decomposed `é`) will be settled by fixtures.

### Replacement templates

`change … into`, `find text … using` and `filter text … key/using` share a template syntax: `\0`–`\9` back-references (written `"\\1"` in AppleScript), probably named references, and escapes. It gets its own small parser with unit tests. Fixtures will pin down the exact rules, e.g. what `\n`, `\\` and an unknown `\x` mean, and how `verbatim` and `only backreference` change them.

### MTC_OSAX extension: dollar references

Not Satimage behavior. Satimage treats `$` in replacement text as literal (checked: `change "(a)(b)" into "[$1|$2|$0|$$|${1}]" in "xaby" with regexp` gives `x[$1|$2|$0|$$|${1}]y`). MTC_OSAX adds `$`-style references as an opt-in, so existing scripts are unaffected unless they ask for it.

When dollar references are on, templates also accept:

| Syntax | Meaning |
|---|---|
| `$0`–`$9` | whole match / numbered group, same as `\\0`–`\\9` |
| `${12}` | any group number, including above 9 |
| `${name}` | named group |
| `$$` | a literal `$` |

A `$` followed by anything else stays literal. `\\1` and the other backslash forms keep working either way. Like the backslash forms, they only apply where Satimage interprets templates (regexp replacements and `using`), and `verbatim` turns all of them off.

Three ways to turn it on, in order of precedence:

1. **Per call, parameter:** `change … with dollar references` or `dollar references true|false`, on `change`, `find text` and `filter text` (the commands that take templates). An explicit `false` turns it off even if the app-wide setting is on. New parameter, code `DlRf` (unused anywhere in Satimage's dictionary).
2. **Per call, flag:** `regexpflag {"DOLLAR REFERENCES"}` (also `DOLLAR_REFERENCES`), alongside the regular Onigmo flags.
3. **App-wide default:** `defaults write com.mactechnologies.mtc-osax DollarReferences -bool YES`. Off by default.

The SDEF consistency test gets an explicit list of MTC_OSAX extension parameter codes (`DlRf`), which are allowed on copied commands; anything else must still match Satimage exactly. Fixtures for this recorded from MTC_OSAX go in `Fixtures/TextAdditionsExtensions/`, separate from the Satimage fixtures.

### Text from files

`find text`, `change` and `filter text` accept a file as well as a string (`in` given an alias). `change` then rewrites the file and returns the number of changes. These, along with `readtext`, `writetext` and `file offset`, share one file-text helper:

- Encodings by IANA name (`"UTF-8"`, `"MACINTOSH"`, `"UTF-16"`, `"ISO-8859-1"`, `"windows-1252"`, …) through `CFStringConvertIANACharSetNameToEncoding`.
- BOM detection when reading (`readtext` is documented as BOM-aware).
- `starting at` / `for` count **bytes** for these commands, not characters.
- `missing char` substitutes characters the encoding can't represent; without it, `writetext` raises an error.

### Per-command notes

| Command | Approach | Risk |
|---|---|---|
| `find text` | Onigmo or literal search; returns `matchrecord` (`mPos`, `mLen`, `mRes`), a list of them, or strings with `string result`; `using` builds `mRes` from a template, an integer n, or a list of templates | Medium: many parameter combinations |
| `change` | Replace in a string, a list of strings, or a file; lists of patterns and replacements; `verbatim`; `only backreference` | Medium |
| `splittext` | Split on a literal or regex separator | Low |
| `re_compile` | Compile only; error if invalid. What it returns on success comes from fixtures | Low |
| `filter text` | Group matches by a key template into an XML property list, returned as a string or written to a file | Medium. `into` a `CFRef` needs the PropertyList suite; returns an error for now (agreed) |
| `readtext` | Files only for now; `for`/`starting at` in bytes; `encoding`. URLs return an error (agreed to defer); `redirect` and `timeout` are accepted but unused | Low |
| `writetext` | Write or `append`; `encoding`; `missing char` | Low |
| `file offset` | Byte offset of a string in a file, in a given encoding; `inclusive` | Low |
| `uppercase`, `lowercase`, `titlecase` | String or list. Exact title-case rules (apostrophes, hyphens, "McDonald") from fixtures | Low |
| `format` | Satimage's own number-format mini-language (`#`, `0`, `^`, `%`, `'…'`, `+f1;-f2;f3`, `underflow test`). Implemented from its description and a large set of fixtures | **High**: undocumented edge cases |
| `atof`, `atoi` | `strtod` / `strtol` (base 0 by default, so `"0xa0"` → 160); `base` 2–36; lists. Invalid input gives -1700 (seen) | Low |
| `encode entities`, `resolve entities` | The five XML entities, plus numeric `&#…;` / `&#x…;` when resolving | Low |
| `escapeURL`, `unescapeURL` | Percent-encoding with Satimage's default safe set, extra `escaping` characters, `keeping` characters | Low; exact safe set from fixtures |
| `normalize unicode` | NFC, or NFD with `decomposition` | Low |
| `transform unicode` | ICU transform IDs through Foundation's `StringTransform`; `inverse` | Low; ICU versions differ slightly |
| `hash` | `CFHash(NFKD(s)) & 0xFFFFFF` | Low, but depends on CFHash staying stable across macOS versions; fixtures will catch a change |
| `join` | Join a list with `using` | Low |
| `printf` | Own parser for C format specs (`%d %i %u %x %o %e %f %g %s %c %%`, flags, width, precision, positional `%2$s`); each spec formatted individually. List parameters repeat the format once per item | Medium |
| `strftime`, `strptime` | C `strftime` / `strptime` on a `tm`, local or GMT; dates or lists of dates; `strptime … as real` gives seconds since 2001 | Low–medium (`%z`, `Z` handling) |

### SDEF

Copy the suite verbatim from `SatImageOSAX SDEF/dictionary.sdef`, including `matchrecord`, the synonyms (`ufind text`, `uchange`, `capitalize`) and hidden parameters. Parameters typed `CFRef`, `alias` or `file` need matching hidden type definitions, copied from Satimage's hidden suites. The SDEF consistency tests already check names and codes.

## Testing

- **Fixtures first.** Before implementing each group, write its `cases.json` in `Tests/Fixtures/TextAdditions/` and record them from SatimageOSAX. Aim for every parameter of every command, including error cases (missing or wrong-typed parameters, invalid regex, missing file) and Unicode edge cases (emoji, combining marks, CJK). Expect roughly 250–350 cases, most of them for `find text`, `change`, `format` and `printf`.
- **File cases** need fixed input files. Add them under `Tests/Fixtures/TextAdditions/Files/`. The recorder will need a way to run cases with the repository path available; the replay test will need to map the recorded paths to the checkout location. Tests that write files use a temporary folder.
- **Unit tests** for the Onigmo wrapper (syntaxes, flags, UTF-16 offsets, caching), literal search, the options parser, the template parser, the `format` and `printf` parsers, and encoding handling.
- **End to end:** `Scripts/e2e/text.applescript` runs a representative set of commands through Apple events.
- **Parity check:** new `Scripts/parity.sh` runs the same AppleScript against SatimageOSAX and MTC_OSAX (switching the `use` line) and diffs the results. It's a quick way to try your real scripts' patterns.

## Order of work

1. Vendor Onigmo; the `TextMatching` wrapper and its unit tests.
2. Copy the SDEF suite; stub handlers so the consistency tests pass.
3. `find text`, `change`, `splittext`, `re_compile` on strings. Includes the dollar references extension.
4. The simple commands: case, `atof`/`atoi`, entities, URL escaping, Unicode, `hash`, `join`.
5. Files: `readtext`, `writetext`, `file offset`, then `find text`/`change` in files.
6. `filter text`.
7. `printf`, `strftime`, `strptime`.
8. `format` last, as the riskiest.

Each step: record fixtures → implement → unit tests → replay passes.

## Done when

- [x] All 25 commands implemented and registered; SDEF consistency tests pass.
- [x] Fixtures recorded from SatimageOSAX for every command and replayed without differences (any accepted difference documented in this plan).
- [x] Unit tests for `TextMatching`, templates, `format`, `printf` and file encoding.
- [x] `Scripts/e2e/text.applescript` passes against MTC_OSAX.
- [x] `Scripts/parity.sh` exists and shows no differences on the e2e script.
- [x] Dollar references extension: parameter, flag and app-wide default, with unit tests and MTC_OSAX fixtures.
- [x] Onigmo's license included in the repo and noted in the README.

## Decisions

- Regex engine: Onigmo, as Satimage uses (confirmed by its version banner in the binary and six behavior tests).
- `readtext` from http(s) URLs: deferred. Returns an error for now.
- `filter text … into` a plist reference (`CFRef`): returns an error until the PropertyList suite (priority 5 in PLAN.md) is implemented, which will complete it.
- `$1`-style references as an opt-in MTC_OSAX extension: `with dollar references` parameter, `regexpflag {"DOLLAR REFERENCES"}`, or the `DollarReferences` app-wide default (off by default).
- Fixture priorities come from the usage in `~/Documents/AppleScript Projects` (see "How your scripts use it").

## Findings during implementation

Everything below was established from fixtures recorded from SatimageOSAX (see "Fixtures after the fixes" for where they are now).

**Regex engine.** Satimage's build of Onigmo differs from stock Onigmo in two ways, both reproduced: CR, LF, NEL, U+2028 and U+2029 are line ends (not vertical tab or form feed; CR LF counted as two in Satimage's build, and is one in MTC_OSAX: see the fixes), and negated classes like `[^x]` exclude `\r` as well as `\n` in every syntax. The first is our own `mtc_encoding.c`; the second is a small marked patch to `regparse.c`. Unnamed groups are numbered alongside named ones.

**Search and replace.** Not found is error -2763 (an empty list with `all occurrences`, `missing value` per item for list input). Literal search is canonical (precomposed and decomposed é match). Templates accept only `\0`–`\9`, `\t`, `\n`, `\r`, `\\` and `\uXXXX`; anything else is -208, a group number too big is -207, and `\k<…>` always inserts the whole match. Empty matches are never taken at the very end unless the search started before it.

**Files.** With no encoding, `readtext` uses the byte-order mark, then UTF-8 if valid, then MacRoman. `starting at` above 0 needs a `for` (else -1). `writetext` rejects POSIX path strings with error 1. `change` on a file rewrites it in its own encoding and returns the count.

**Not working in SatimageOSAX.** `file offset` and `filter text` reply -1708 ("not handled") to every call, including the documented examples. MTC_OSAX implements both from their documentation (see "Fixing Satimage's bugs").

**Formatting.** `printf` is C formatting with Satimage's argument rules (lists repeat the format; error 10 for unsupported conversions and arguments). `strftime`/`strptime` use the C library, including `mktime`'s failure before 1900. Fixtures record their time zone and replays run in it, so they pass on a Mac set to any zone.

**`format`.** Satimage's actual grammar, documented in `NumberFormat.swift`: Indian-style grouping, rounding half to even, scientific and engineering notation. Where Satimage was broken (invalid formats silently reusing the last valid one, three sections, `^`, `underflow test`), MTC_OSAX follows the documentation instead. Beyond targeted cases, 600 randomly generated formats were recorded; after fixing what the first 300 revealed, 298 of the next 300 matched before the last two rules were added.

**Framework fixes found along the way.**
- Replying -1708 through `NSAppleEventManager` made Cocoa Scripting take over and break every later command; handlers now use `AEInstallEventHandler`.
- Creating Apple events on many threads at once can hang, so creation is serialized.
- `core.autocrlf` had converted a CRLF test input; fixture inputs are now marked binary in `.gitattributes`.

## Fixing Satimage's bugs

Decided 2026-09-27: MTC_OSAX matches Satimage's working behavior but doesn't reproduce its bugs. Where SatimageOSAX fails or does something nonsensical, the dictionary's documentation is the spec. The Satimage fixtures that recorded a bug are removed (they stay in Git history); the new behavior is recorded from MTC_OSAX into `Fixtures/TextAdditionsFixes/` and covered by unit tests.

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `file offset` | Always -1708 | Byte offset of the text in the file, 0-based; `starting at` (bytes), `encoding` (default UTF-8), `inclusive` (offset after the text). Not found: -2763, like `find text` |
| `filter text` | Always -1708 | Builds the XML property list: keys from `key`, values from `using` (default `\0`); `as string` (default) joins values with `separator` (default linefeed), `as list` gives arrays, `duplicates` (default true) applies to lists. `in` a string or file; `into` a file writes it and returns nothing. `into` a plist reference waits for the PropertyList suite. Takes `dollar references` |
| CR LF in a regular expression | Two line ends: `$` and `^` matched between the CR and the LF, and `\Z` didn't match before a final CR LF (`line-end-*-crlf*`, now in `TextAdditionsFixes/Other`) | One line end, with Onigmo's `ONIG_OPTION_NEWLINE_CRLF`; with `syntax "PCRE"` too |
| `change … only backreference` naming no group | Replaced the whole match (and crashed on a group that took no part) | Error -207 (a number) or -217 (a name) |
| `format` | Invalid format reuses the previous one; no `into` reuses it too | Invalid format: error -50 with a message; `into` required (-1701) |
| `format` | Three sections invalid | `f1;f2;f3`: formats for >0, <0 and =0 |
| `format` | Second section only supplies literal text | Each section uses its own layout |
| `format` | `^` printed literally | `^` is a space, as documented |
| `format` | `underflow test` ignored | A nonzero value that would show as zero switches to scientific notation |
| `format` | `#.0#E+0` shows one decimal fewer; 9.95 gives `1E+1`; zero drops required decimals | Mantissa decimals follow the placeholders |
| `readtext` | `starting at` without `for`: error -1 | Reads to the end |
| `writetext` | POSIX path string: error 1 | Accepted |
| `strftime`, `strptime` | Before 1900: error 2, or 1969-12-31 23:59:59 | Work for any date |
| `printf` | `%c` is error 10 | A character (a number is a code point; text gives its first character) |
| `change` | `only backreference` naming an unmatched group: no result | That match is left unchanged |
| `change` | `change {} into {}`: error 5 | The text unchanged |
| Templates | `\k<name>` always inserts the whole match | The named group (or numbered group `\k<1>`); unknown name: -217 |
| `resolve entities` | Malformed numeric entity becomes U+0000 or U+FFFD | Left unchanged; `&#X42;` works |
| `atoi` | `"-0x10"` fails | -16 |

Kept on purpose: `find text`'s -2763 when nothing matches; Satimage's regex line ends (CR, NEL, LS, PS) and `[^x]` never matching `\r` (a deliberate part of its Onigmo build, relied on by patterns run on `\r` text); errors for unknown escapes, flags and encodings.

- [x] Every row above implemented, with unit tests and `TextAdditionsFixes` fixtures recorded from MTC_OSAX.
- [x] Satimage fixtures that recorded the bugs removed; all remaining Satimage fixtures still pass.
- [x] End-to-end and parity scripts updated (parity only covers behavior both apps share).

## Regex token suite

`Fixtures/TextAdditions/RegexTokens` holds 148 patterns covering as many Onigmo tokens as possible (escapes, character types, Unicode properties, anchors, bracket expressions, greedy/lazy/possessive quantifiers, groups, lookaround, backreferences, subexpression calls, conditionals, inline options, Unicode case folding, and each other syntax's own tokens), all recorded from SatimageOSAX and replayed in the unit tests. The cases are generated by `generate.py` in that folder.

- `(?x)` comments: Satimage's build ended them at a return and at the escapes `\n` and `\r` as well as at a linefeed (not at NEL, LS or PS). Reproduced with a second small `regparse.c` patch.
- Six cases where Satimage's Onigmo (about 2013) failed or used outdated Unicode data are kept as MTC_OSAX behavior, recorded into `Fixtures/TextAdditionsFixes/RegexTokens`: the absent operator `(?~…)` (Satimage: error -119), `\p{Emoji}` and lowercase property names like `\p{alpha}` (error -223), `\X` (Satimage split grapheme clusters into code points), `\R` matching U+2028, and case-insensitive `ß` matching capital `ẞ`.

## Accepted differences

Besides the bug fixes above:
- `readtext` of an http(s) URL returns an error instead of downloading (deferred, as agreed).
- `filter text … into` a plist reference returns an error until the PropertyList suite exists.

## Fixtures after the fixes

- `Fixtures/TextAdditions/*`: recorded from SatimageOSAX; behavior both apps share (1,167 fixtures). The 677 that recorded bugs were removed.
- `Fixtures/TextAdditionsFixes/*`: recorded from MTC_OSAX; the fixed behavior (682 fixtures), from the same scripts where possible.
- `Scripts/e2e/text.applescript` checks shared behavior (and is the parity script); `text-fixes.applescript` checks the fixes, MTC_OSAX only.
