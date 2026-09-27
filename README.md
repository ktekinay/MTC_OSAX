# MTC_OSAX

A native, faceless scriptable app that replaces the Intel-only `SatimageOSAX.app`. Existing scripts only need their `use` line changed:

```applescript
use application "MTC_OSAX" -- was: use application "SatimageOSAX"
```

Commands, parameters and codes are copied exactly from Satimage's dictionary ([SatImageOSAX SDEF/dictionary.sdef](SatImageOSAX%20SDEF/dictionary.sdef)). See [PLAN.md](PLAN.md) for which sections are planned and their order, and `PLAN-<Section>.md` for each section's plan. Plans that have been fully implemented are moved into `Implemented/`.

Requires macOS 26.6 on Apple silicon.

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

The app has no UI. It launches when a script sends it a command and quits after an hour without commands. To test the idle quit, shorten the timeout: `defaults write com.mactechnologies.mtc-osax IdleTimeoutSeconds 5` (remove it again with `defaults delete com.mactechnologies.mtc-osax IdleTimeoutSeconds`).

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

**Satimage's bugs aren't reproduced.** Where SatimageOSAX fails or misbehaves, MTC_OSAX follows the documentation instead. The Satimage fixture that recorded the bug is removed, and the case's script moves to a `…Fixes` folder to be recorded from MTC_OSAX. Each section's plan lists these differences.

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
