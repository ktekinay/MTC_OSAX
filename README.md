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
- `XMLOpen` of an http or https URL (with `query`, POST and extra headers)

**Text Additions**

- `format`: an invalid format is error -50 instead of silently reusing the previous one; `into` is required; the three sections `f1;f2;f3` (positive, negative, zero) work, each with its own layout; `^` is a space; `underflow test` works; decimals follow the placeholders.
- `readtext … starting at` without `for` reads to the end; `writetext` accepts a POSIX path string.
- `strftime` and `strptime` work for dates before 1900.
- `printf %c` gives a character.
- `change`: `only backreference` naming a group that didn't match leaves that match unchanged; `change {} into {}` returns the text unchanged; `\k<name>` inserts the named group, not the whole match.
- `resolve entities` leaves malformed numeric entities unchanged and accepts `&#X42;`.
- `atoi "-0x10"` gives -16.

**Files and folders, File Additions**

- HFS paths are accepted wherever a file or folder is.
- `mkdir` and `filenew` of a path string directly inside a system folder such as `/private/tmp` work.
- `mkdtemp` honors `wildcards`; `fileremove … with filesonly` reports the real count.
- `glob "…/.*"` doesn't return `.` and `..`; `glob … not conforming to "public.folder"` excludes folders.
- `~` is your home folder, not SatimageOSAX's sandbox container.

**Math and list utilities**

- `sortlist` of a single value gives a list of it; without a parameter it's error -1701; `missing value` sorts last and stays `missing value` (SatimageOSAX turned every number into a real).
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

### New features

- **Native on Apple silicon**, so it keeps working after Rosetta is removed.
- **Dollar references** in replacement templates (`$1`, `${12}`, `${name}`, `$$`), opt-in: `with dollar references` on `change`, `find text` and `filter text`, the `"DOLLAR REFERENCES"` regexp flag, or `defaults write com.mactechnologies.mtc-osax DollarReferences -bool YES`.
- **Idle quit** is a preference (`IdleTimeoutSeconds`; see [Building](#building)), and the app doesn't quit while property list or XML documents are open.
- **Diagnostic commands** (`mtc_ping` and others; see [Diagnostic commands](#diagnostic-commands)).

### Other differences

- MTC_OSAX uses macOS's libxml2 (2.9.13) and libxslt, newer than SatimageOSAX's. HTML output has no line break after `<br>`, XInclude leaves no blank lines for its markers, and `XMLError` has a second message when a schema file can't be loaded. The content is otherwise the same.
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

The app has no UI. It launches when a script sends it a command and quits after an hour without commands. The timeout is a preference, in seconds, where 0 means never quit:

```sh
defaults write com.mactechnologies.mtc-osax IdleTimeoutSeconds 300   # quit after 5 minutes
defaults write com.mactechnologies.mtc-osax IdleTimeoutSeconds 0     # never quit
defaults delete com.mactechnologies.mtc-osax IdleTimeoutSeconds      # back to an hour
```

A change applies from the next command, without restarting the app.

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

- **Onigmo 6.2.0** (`Packages/MTCOSAXKit/Sources/COnigmo`), the regular expression engine Satimage used, by K.Kosako and K.Takata. BSD 2-clause license; see [COPYING](Packages/MTCOSAXKit/Sources/COnigmo/COPYING). Only the engine and the encodings it needs are included. Changes to match Satimage's build: `regparse.c` has two small patches (marked `MTC_SATIMAGE_COMPATIBILITY`) so negated classes also exclude `\r` and `(?x)` comments also end at `\r` and the escapes `\n`/`\r`; our own `mtc_encoding.c` defines Satimage's line terminators. `include/COnigmoShim.h` is also ours.
