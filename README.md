# MTC_OSAX

A native, faceless scriptable app that replaces the Intel-only `SatimageOSAX.app`. Existing scripts only need their `use` line changed:

```applescript
use application "MTC_OSAX" -- was: use application "SatimageOSAX"
```

MTC_OSAX is a rough clone of SatimageOSAX: [Mark Alldritt](https://github.com/alldritt/SatimageOSAX)'s (Late Night Software) app that hosts the free scripting additions by [Satimage](https://www.satimage.fr) of Paris ([download page](https://www.satimage.fr/software/en/downloads/downloads_companion_osaxen.html)). It's written from their dictionary and from recordings of what SatimageOSAX actually does. It isn't a complete copy: some suites aren't implemented, some of SatimageOSAX's bugs are fixed rather than reproduced, and a few features are new. [Differences from SatimageOSAX](#differences-from-satimageosax) lists them all.

Commands, parameters and codes are copied exactly from Satimage's dictionary ([SatImageOSAX SDEF/dictionary.sdef](SatImageOSAX%20SDEF/dictionary.sdef)). See [PLAN.md](PLAN.md) for which sections are planned and their order, and `PLAN-<Section>.md` for each section's plan. Plans that have been fully implemented are moved into `Implemented/`.

Requires macOS 26.6 on Apple silicon.

## Differences from SatimageOSAX

This section is kept up to date as sections are added. Each implemented section's plan in `Implemented/` has the details, and the `…Fixes` fixture folders and `Scripts/e2e/*-fixes.applescript` scripts check them.

### Not implemented

These suites aren't implemented and aren't in MTC_OSAX's dictionary, so a script that uses them doesn't compile (an already compiled one gets error -1708):

- Arrays, except the `array of real` type, `createarray` and `randomarray`
- Linear algebra, FFT and convolution
- Image files, 3D array handling, FITS, XNF Additions
- Resource Suite
- The hidden legacy text commands (`find text obsolete`, `replace obsolete`, `extract string`, `findxmlstag`, `gziptext`, `gunziptext`)
- The unnamed hidden suite of obsolete commands (old XML variants, `XMLCookie`, `PlistCopy`, `XMLGetArray`/`XMLSetArray`, …)

Within the implemented suites:

- `readtext` of an http or https URL returns an error instead of downloading it.
- XPath functions written as AppleScript handlers (the `http://satimage.fr/software/xpath-functions-applescript` namespace) aren't supported: an app can't reach the handlers of the script that sent the command. They didn't work in SatimageOSAX's app either (error -3); MTC_OSAX gives 3, an unknown function.

### Fixes

Where SatimageOSAX failed or misbehaved, MTC_OSAX does what the dictionary describes.

**Commands that never worked in SatimageOSAX** (they replied -1708 or an error for every input) and now do:

- `file offset`, `filter text` (including `into` a property list reference)
- The `navchoose …` dialogs, `navnew folder` and `navask save`
- `topological sort`
- `XMLOpen` of an http or https URL (with `query`, POST and extra headers; characters a URL can't hold in `query` are percent-encoded)

**Text Additions**

- `format`: an invalid format is error -50 instead of silently reusing the previous one; `into` is required; the three sections `f1;f2;f3` (positive, negative, zero) work, each with its own layout; `^` is a space; `underflow test` works; decimals follow the placeholders.
- `readtext … starting at` without `for` reads to the end; `writetext` accepts a POSIX path string.
- `strftime` and `strptime` work for dates before 1900.
- `printf %c` gives a character.
- `change`: `only backreference` naming a group that didn't match leaves that match unchanged; `change {} into {}` returns the text unchanged; `\k<name>` inserts the named group, not the whole match (so `\k<-1>` is an unknown name, error -217); `only backreference -1` is error -208, as `find text … using -1` is.
- `resolve entities` leaves malformed numeric entities unchanged and accepts `&#X42;`.
- `atoi "-0x10"` gives -16.

**Files and folders, File Additions**

- HFS paths are accepted wherever a file or folder is.
- `mkdir` and `filenew` of a path string directly inside a system folder such as `/private/tmp` work.
- `filemove` to the same name in another case, and `filerename` to another case, rename the item (SatimageOSAX gave -48).
- `mkdtemp` honors `wildcards`; `fileremove … with filesonly` reports the real count.
- `glob "…/.*"` doesn't return `.` and `..`; `glob … not conforming to "public.folder"` excludes folders.
- `~` is your home folder, not SatimageOSAX's sandbox container.
- `backup` onto a folder inside the source backs up everything but that folder (SatimageOSAX created it and then gave -50); onto the source itself is -50.
- `backup` copies symbolic links as links (SatimageOSAX made an empty folder for each).
- `backup` never deletes anything: a newer file where the destination has a folder of that name is reported as error 21 (SatimageOSAX replaced the folder and everything in it), and an update that fails leaves the old item.

**Math and list utilities**

- `sortlist` of a single value gives a list of it; `with respect to 1.5` is error -1700, as 1.0E+19 is (SatimageOSAX left the lists unsorted); without a parameter it's error -1701; `missing value` sorts last and stays `missing value` (SatimageOSAX turned every number into a real).
- `suppress item` with a single index works (including the dictionary's example).
- `exclude items` and `keep items` `without case sensitive` ignore case; `keep items {}` gives `{}`.
- `special concat` of text with a record is error -1700 instead of garbage; empty text gives empty cells.
- `randomarray … seed` beyond 32 bits uses the seed's low 32 bits instead of ignoring it.

**Property lists**

- A `using` path ending in `/` works (in SatimageOSAX it broke every later property list command).
- Integers beyond 32 bits come back as reals instead of 0.
- A removed element's reference is error -1728, as for a closed document.
- `PlistSave … in` a POSIX path works.
- `PlistToJSON` writes dates as ISO 8601 text and data as base64; `PlistFromJSON` reads `null` as `missing value`.
- `PlistSet` with a list of keys stores `missing value` `without suppressing`; `PlistNew … without typed` stores raw bytes, as `PlistSet` does.

**XML**

- `XMLExists` of a removed node or closed document is false instead of error -1728.
- `XMLAppendText` to an element with mixed content works (it crashed SatimageOSAX); `XMLSetXML` of a text node replaces it (SatimageOSAX left the document unreadable).
- `XMLError` after a command without problems is `""` instead of stale text; `XMLSave … in` a POSIX path works.
- `XMLSetContext` with `nsurl ""` removes the namespace; `str:replace` works in XPath.
- `XMLGetNodePath … from` works from any ancestor, without a leading space; `XMLGetXPointer … suffix` adds the suffix as a further step.
- `XMLXPointer` works in documents opened `from string` and for relative `xpointer(…)` links from an element.
- `XMLXPath` of nodes in two documents with `xpath variables` works.
- `XMLValidate` of an element with ID attributes works (SatimageOSAX reported every ID as already defined).
- `XMLValidName` and `XMLValidNCName` return false for an invalid name instead of error 1821.
- `XMLc14n … nodelist` canonicalizes only those nodes (SatimageOSAX ignored it and output the whole document).

### New features

- **Native on Apple silicon**, so it keeps working after Rosetta is removed.
- **PCRE** as a second regex engine, with `syntax "PCRE"` on `find text`, `change`, `splittext`, `filter text` and `re_compile` (`splittext` gains the `syntax` parameter for this). Patterns get PCRE2's features (`\h`, `\K`, recursion, possessive quantifiers, Unicode-aware `\w` and case), and any line ending counts. As with Onigmo, `^` and `$` match at every line unless the pattern says `(?-m)` or the call gives `regexpflag {"SINGLELINE"}`; `"DOTALL"` makes `.` match newlines. Onigmo-only flags (`FIND LONGEST`, `NEGATE SINGLELINE`, `NEWLINE IN NEGATIVE CC`) are error -1, and a pattern error is -3000 minus PCRE2's number, with PCRE2's message. To make PCRE the default: `mtc_set regex_syntax to "PCRE"` (see [Settings](#settings); an explicit `syntax` still wins).
- **YAML and TOML for property lists:** `PlistToYAML`, `PlistFromYAML`, `PlistToTOML` and `PlistFromTOML`, like Satimage's `PlistToJSON` and `PlistFromJSON`, in their own "MTC_OSAX Property List Formats" suite. All three formats, JSON included, can go straight to and from a file: `PlistToJSON p in (POSIX file "…")` (or a POSIX path) writes the file in UTF-8 and returns nothing, and `PlistFromJSON (POSIX file "…")` reads one; text is always the document itself, never a path. For Satimage's two JSON commands, `in` is a new parameter and a file a newly accepted direct parameter (SatimageOSAX gave an error). YAML follows YAML 1.2's rules (`yes` and `no` stay text); unquoted timestamps are dates, `null` is `missing value`, and data is `!!binary`. TOML needs a dictionary at the top; a `missing value` in a dictionary is written as the comment `# key = NULL` (so it's absent when read back) and in a list is error -50; data is base64 text. Dates are written in UTC (`2026-09-28T14:30:00Z`), and dates without a zone are read in the Mac's time zone; a TOML time without a date is read as text.
- **Dollar references** in replacement templates (`$1`, `${12}`, `${name}`, `$$`), opt-in: `with dollar references` on `change`, `find text` and `filter text`, the `"DOLLAR REFERENCES"` regexp flag, or as the default with `mtc_set dollar_references to true`.
- **Settings commands:** `mtc_get`, `mtc_set` and `mtc_reset`, in their own "MTC_OSAX Settings" suite, read and change MTC_OSAX's settings from a script. Settings are global and permanent: a change affects every script that uses MTC_OSAX until it's changed again or reset (see [Settings](#settings)).
- **Idle quit** is a setting (`idle_timeout`), and the app doesn't quit while property list or XML documents are open.
- **Diagnostic commands** (`mtc_ping` and others; see [Diagnostic commands](#diagnostic-commands)).

### Other differences

- MTC_OSAX uses macOS's libxml2 (2.9.13) and libxslt, newer than SatimageOSAX's. HTML output has no line break after `<br>`, XInclude leaves no blank lines for its markers, and `XMLError` has a second message when a schema file can't be loaded. The content is otherwise the same.
- `XMLChild` of a DTD gives its declarations (SatimageOSAX gave -2763); they can be read but not changed or removed (-50). `XMLNewChild` at a text node is error -1700, as at an attribute (SatimageOSAX did nothing).
- `XMLTransform` with a stylesheet the script gives (`with`) can write files with `exsl:document`, as the script itself could (SatimageOSAX's sandbox refused, error 1535). A stylesheet the document chooses with its `xml-stylesheet` instruction is the document's code, so it can't write files, make folders or write to the network (1535).
- `XMLXInclude` includes local files (relative to the document, or any `file:` URL) but nothing from the network.
- Math results can differ from SatimageOSAX's Intel math library in the last digits (up to 15 units in the last place for `lgamma` near its roots).

## Layout

| Path | Contents |
|---|---|
| `MTC_OSAX/` | The app: `AppDelegate`, `Info.plist`, `MTC_OSAX.sdef` |
| `Packages/MTCOSAXKit/` | All the real code and its tests (Swift package) |
| `Packages/MTCOSAXKit/Sources/AppleEventCore` | Dispatch, parameter conversion, errors, fixtures, idle quit |
| `Packages/MTCOSAXKit/Sources/<Suite>` | One module per implemented section |
| `Packages/MTCOSAXKit/Sources/MTCOSAX` | Registers every suite; the only module the app links |
| `Packages/MTCOSAXKit/Sources/FixtureRecorder` | `fixture-recorder` command-line tool |
| `Packages/MTCOSAXKit/Tests/Fixtures` | Recorded Apple events and replies, one folder per section |
| `Scripts/` | End-to-end AppleScript checks and helper scripts |

## Building

Open `MTC_OSAX.xcodeproj` and build the `MTC_OSAX` scheme, or:

```sh
xcodebuild -project MTC_OSAX.xcodeproj -scheme MTC_OSAX -derivedDataPath build/DerivedData build
```

The app is signed with the Developer ID Application certificate (team 8A6WVHL579). A stable signature matters: macOS ties Automation permission to it, so ad-hoc builds would ask for permission again after every build.

So that `use application "MTC_OSAX"` finds a command-line build, register it once with Launch Services:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/DerivedData/Build/Products/Debug/MTC_OSAX.app
```

The app has no UI. It launches when a script sends it a command and quits after an hour without commands (the `idle_timeout` setting; see [Settings](#settings)).

## Settings

MTC_OSAX has three settings. Scripts read and change them with the commands of the "MTC_OSAX Settings" suite, and a change applies from the next command, without restarting the app.

**Settings are global and permanent.** A change affects every script that uses MTC_OSAX, not just the one that made it, including scripts run later and after MTC_OSAX or the Mac restarts, until it's changed again or reset. To change how a single command behaves, use its own parameter instead (`syntax "PCRE"`, `with dollar references`); a command's parameter always wins over the setting.


| Setting | Default | What it does |
|---|---|---|
| `idle_timeout` | 3600 | Seconds without commands before the app quits; 0 means never. It doesn't quit while property lists or XML documents are open either way. |
| `dollar_references` | false | Whether replacement templates also accept `$1`-style references when a command doesn't say. |
| `regex_syntax` | `"RUBY"` | The regex syntax when a command doesn't give one, e.g. `"PCRE"`. |

```applescript
mtc_get regex_syntax                    --> "RUBY"
mtc_set regex_syntax to "PCRE"
mtc_set idle_timeout to 300             -- quit after 5 minutes (0: never)
mtc_reset regex_syntax                  -- back to the default
mtc_get all_settings                    --> {{name:idle_timeout, key:"IdleTimeoutSeconds", value:300, default value:3600, …}, …}
mtc_reset all_settings                  -- every setting back to its default
```

A setting can also be named with text: its friendly name (`"regex syntax"`), its `defaults` key (`"RegexSyntax"`) or the constant's name, ignoring case, spaces and underscores; `"all settings"` stands for `all_settings`. A value of the wrong kind is error -1700 and one that isn't allowed -50 (both with a message); an unknown setting is -1728. To go back to a default, use `mtc_reset` (`mtc_set … to missing value` is an error).

The settings are kept in MTC_OSAX's defaults, so they can also be changed from the shell:

```sh
defaults write com.mactechnologies.mtc-osax IdleTimeoutSeconds 300
defaults write com.mactechnologies.mtc-osax DollarReferences -bool YES
defaults write com.mactechnologies.mtc-osax RegexSyntax PCRE
defaults delete com.mactechnologies.mtc-osax RegexSyntax              # back to the default
```

## Untrusted documents

A script is trusted: it can already do anything you can. The files it opens (XML, stylesheets, property lists, JSON, YAML, TOML, text) and the text it takes from them often aren't, so MTC_OSAX limits what a document can make happen on its own:

- A stylesheet chosen by the document's `xml-stylesheet` instruction (`XMLTransform` without `with`) is code from the document: it can't write files, make folders or write to the network (error 1535). A stylesheet the script gives with `with` can, as the script could.
- `XMLXInclude` includes local files, but nothing from the network.
- What libxml2 and libxslt load by URL themselves (external DTDs and entities, `xsl:import`, `document()`, schemas) comes from local files or over http and https (with URLSession, so https works and is checked); ftp isn't supported.
- `XMLOpen … with substitute entities`, `with validate` and `with load external DTD` let the document load what its DTD names: an entity such as `<!ENTITY x SYSTEM "file:///etc/passwd">` becomes text the script can read, and a DTD at an http URL is fetched. Use them only with documents you trust.

## Diagnostic commands

A hidden suite for checking that the app works. It doesn't appear in the dictionary viewer.

| Command | Result |
|---|---|
| `mtc_ping` | `"pong"` |
| `mtc_version` | e.g. `"MTC_OSAX 0.1 (1)"` |
| `mtc_echo <anything>` | the value, unchanged |
| `mtc_describe <anything>` | the Apple event descriptor received, e.g. `list [long 1, doub 2.5]` |
| `mtc_raise_error "message" number n` | raises that error |

## Tests

Unit, handler, SDEF-consistency and fixture-replay tests don't send Apple events and need no permissions:

```sh
swift test --package-path Packages/MTCOSAXKit
# or all targets through the app's scheme:
xcodebuild -project MTC_OSAX.xcodeproj -scheme MTC_OSAX -derivedDataPath build/DerivedData test
```

- **SDEF consistency** checks that every command in `MTC_OSAX.sdef` has a handler (and the reverse), and that everything copied from Satimage keeps its names and codes.
- **Fixture replay** sends each recorded Apple event to the app's commands and compares the reply with the recorded one. Text encodings (`utxt`, `ut16`, …) and boolean encodings (`true`, `fals`, `bool`) count as equal, since scripts can't tell them apart.

### Automation permission

Anything that sends Apple events to SatimageOSAX or MTC_OSAX needs Automation permission for the sending app (System Settings › Privacy & Security › Automation). Entries appear only after macOS has asked once.

VS Code can't get this permission (its Info.plist lacks `NSAppleEventsUsageDescription`), so commands run from VS Code, including by Claude Code, fail with -1743. Run them in iTerm instead. `Scripts/iterm-run.sh` does this from anywhere: it queues the command to a single runner window in iTerm (opening one if needed), waits, and prints the output and exit code.

```sh
Scripts/iterm-run.sh 'osascript -e "tell application \"MTC_OSAX\" to mtc_ping"'
```

### End-to-end checks

`Scripts/e2e/*.applescript` send real commands to the running app. Scripts that only check behavior shared with Satimage (like `text.applescript`) also work with `Scripts/parity.sh`; `*-fixes.applescript` scripts check MTC_OSAX's fixes and only pass against MTC_OSAX.

```sh
Scripts/iterm-run.sh Scripts/run-e2e.sh            # all
Scripts/iterm-run.sh Scripts/run-e2e.sh diagnostics
```

Dialogs need a person: `Scripts/manual/dialogs.sh [MTC_OSAX|SatimageOSAX]` opens each `navchoose` dialog and the `navask save` alert in turn (each prompt says what to do) and prints the results, to check them by hand. (SatimageOSAX's dialogs never worked; they all reply -1708.) Run it in iTerm or Terminal.

### Recording fixtures

While SatimageOSAX still runs, record its behavior so the tests keep working after it's gone (it's Intel-only and will stop working once Rosetta is removed).

1. Add cases to `Packages/MTCOSAXKit/Tests/Fixtures/<Section>/cases.json`:
   ```json
   [
   	{ "name": "uppercase-text", "script": "uppercase \"abc déf\"" }
   ]
   ```
   Each script runs with `use application "<app>"` prepended.
2. Build and record:
   ```sh
   swift build --package-path Packages/MTCOSAXKit
   Scripts/iterm-run.sh "Packages/MTCOSAXKit/.build/debug/fixture-recorder --app SatimageOSAX --cases Packages/MTCOSAXKit/Tests/Fixtures/<Section>/cases.json"
   ```
   Add `--only <name>` to record a single case. Each case is saved as `<name>.json` next to `cases.json`, containing the exact Apple events sent and the replies received.
3. Commit the fixtures. Replay tests pick them up automatically.

Fixtures in `Fixtures/Examples` are replayed against a stand-in rather than the real commands; they demonstrate the mechanism. The `Diagnostics`, `TextAdditionsExtensions` and `TextAdditionsFixes` fixtures are recorded from MTC_OSAX itself.

**Satimage's bugs aren't reproduced.** Where SatimageOSAX fails or misbehaves, MTC_OSAX follows the documentation instead. The Satimage fixture that recorded the bug is removed, and the case's script moves to a `…Fixes` folder to be recorded from MTC_OSAX. Each section's plan lists these differences, and [Differences from SatimageOSAX](#differences-from-satimageosax) summarizes them.

**Files and paths.** Cases can use `$FILES` (read-only inputs, the `Input` folder next to `cases.json`) and `$TMP` (a scratch folder). Pass them when recording, using copies outside `~/Documents` so neither app needs privacy permission:

```sh
rm -rf /private/tmp/mtc-fixtures && mkdir -p /private/tmp/mtc-fixtures/tmp
cp -R Packages/MTCOSAXKit/Tests/Fixtures/TextAdditions/Files/Input /private/tmp/mtc-fixtures/files
Scripts/iterm-run.sh "Packages/MTCOSAXKit/.build/debug/fixture-recorder --app SatimageOSAX --cases …/cases.json --var FILES=/private/tmp/mtc-fixtures/files --var TMP=/private/tmp/mtc-fixtures/tmp"
```

Fixtures store the values used, and replays substitute the checkout's `Input` folder and a fresh temporary folder. Input files are marked binary in `.gitattributes` so Git keeps their exact bytes.

**Time zones.** Each fixture records the time zone it was recorded in, and replays run date commands in that zone.

**State.** Commands that keep state between calls (such as `format`) are recorded with a known first call in the same script, so each fixture replays the same way on its own.

**Case names** must differ by more than letter case, since the disk is usually case-insensitive; the recorder refuses names that would collide.

## Third-party code

- **libyaml 0.2.5** (`Packages/MTCOSAXKit/Sources/CYAML`), the YAML reader for `PlistFromYAML`, by Kirill Simonov and the YAML project. MIT license; see [License](Packages/MTCOSAXKit/Sources/CYAML/License). Only `src` and `include` are included, unchanged; the version is defined in `Package.swift` instead of a generated `config.h`.
- **tomlc17 R260821** (`Packages/MTCOSAXKit/Sources/CTOML`, commit e0e8868), the TOML 1.1 reader for `PlistFromTOML`, by CK Tan. MIT license; see [LICENSE](Packages/MTCOSAXKit/Sources/CTOML/LICENSE). Only `tomlc17.c` and `tomlc17.h`, unchanged.

- **PCRE2 10.49** (`Packages/MTCOSAXKit/Sources/CPCRE2`), the engine for `syntax "PCRE"`, by Philip Hazel and the PCRE2 project. BSD 3-clause license (with the PCRE2 exemption); see [LICENCE.md](Packages/MTCOSAXKit/Sources/CPCRE2/LICENCE.md). Only the 16-bit library's sources are included, without JIT. `config.h` is PCRE2's `config.h.generic` with the changes marked `MTC_OSAX` (16-bit and Unicode support, macOS's headers, any line ending by default), `pcre2.h` is `pcre2.h.generic`, `pcre2_chartables.c` is `pcre2_chartables.c.dist`, and `include/CPCRE2Shim.h` is ours.

- **Onigmo 6.2.0** (`Packages/MTCOSAXKit/Sources/COnigmo`), the regular expression engine Satimage used, by K.Kosako and K.Takata. BSD 2-clause license; see [COPYING](Packages/MTCOSAXKit/Sources/COnigmo/COPYING). Only the engine and the encodings it needs are included. Changes to match Satimage's build: `regparse.c` has two small patches (marked `MTC_SATIMAGE_COMPATIBILITY`) so negated classes also exclude `\r` and `(?x)` comments also end at `\r` and the escapes `\n`/`\r`; our own `mtc_encoding.c` defines Satimage's line terminators. `include/COnigmoShim.h` is also ours.
