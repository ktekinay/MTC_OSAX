# Initial Framework Plan

Branch: `feature/initial_framework`

Goal: everything the app needs before the first section (Satimage Text Additions) is started: the Xcode project, Apple event handling, value conversion, errors, the SDEF, and the test infrastructure, including a way to capture SatimageOSAX results while it still runs. A few diagnostic commands (`ping` etc.) show that it all works from end to end.

## How SatimageOSAX works

- `SatimageOSAX.app` is a faceless app (`LSBackgroundOnly`, `LSUIElement`) with `NSAppleScriptEnabled` and `OSAScriptingDefinition = SatimageOSAX.sdef`. Inside `Contents/Resources/Scripting Additions/` it has the original `Satimage`, `Files`, `Numerics`, `XMLLib` and `FITS` .osax bundles, and it passes incoming Apple events on to them.
- The SDEF has no `cocoa` elements, so it doesn't use Cocoa Scripting's object model. Every command is a plain Apple event.
- Event classes used by the SDEF: `SATI` (text, 87 codes), `XML ` (99), `PLST`, `MATH`, `Quom`, `XNF2`, `FITS`, `VI3D`, `LAPA`, `RESO`, `POOL`, `CONV`, `IMAG`, `XPLA`.
- Sending events to it requires Automation (TCC) permission for the sending app, listed under System Settings › Privacy & Security › Automation. Entries can't be added by hand; they appear after macOS asks the first time. VS Code can never get this permission because its Info.plist has no `NSAppleEventsUsageDescription`, so its sends fail with -1743 without asking. The fixture recorder and end-to-end scripts therefore run from iTerm (or Script Editor), which does ask. `Scripts/iterm-run.sh` queues a command to a single long-running runner window in iTerm and returns its output and exit code (already in place on this branch).
- MTC_OSAX itself isn't sandboxed, but macOS still protects Desktop, Documents, Downloads, iCloud Drive, removable and network volumes. File commands (`readtext`, `list files`, …) will trigger "MTC_OSAX would like to access…" prompts, or MTC_OSAX can be given Full Disk Access. This matters from the Text and File sections onward.

## Architecture

### Layout

```
MTC_OSAX.xcodeproj           app target only; a thin shell (synchronized MTC_OSAX folder)
MTC_OSAX/                    app sources: main.swift, AppDelegate, Info.plist, MTC_OSAX.sdef
Packages/MTCOSAXKit/         local Swift package holding all real code
  Sources/AppleEventCore/    dispatch, parameters, conversion, errors, fixtures, idle quit
  Sources/Diagnostics/       mtc_ping / mtc_echo / etc.
  Sources/<Suite>/           one module per section, added later
  Sources/MTCOSAX/           CommandCatalog: registers every suite; the app links only this
  Sources/FixtureRecorder/   fixture-recorder command-line tool
  Tests/...                  unit, handler, SDEF consistency and fixture replay tests
  Tests/Fixtures/<Section>/  cases.json + one recorded <name>.json per case
Scripts/                     helper scripts
  iterm-run.sh               runs a command in a shared iTerm window (for Apple event sends)
  iterm-runner.command       the runner that iterm-run.sh starts in iTerm when needed
  run-e2e.sh                 runs Scripts/e2e/*.applescript against the running app
```

All the logic lives in the package, so it can be tested with `swift test` or in Xcode without launching the app or sending real Apple events. The app target only installs handlers and forwards events.

### Event handling: raw handlers, not Cocoa Scripting

At launch (`applicationWillFinishLaunching`), the app installs `NSAppleEventManager` handlers for each event class/ID that is implemented, and they all go to one dispatcher. I recommend this over Cocoa Scripting (`NSScriptCommand` subclasses) because:

- We control the reply exactly: descriptor types, record keys (e.g. `matchrecord` uses `mPos`/`mLen`/`mRes`), and error numbers and messages. That matters for compatibility with Satimage.
- Many parameters take several types (a string *or* a list, text *or* a file). Cocoa Scripting's coercion based on the SDEF gets in the way.
- A handler is just a function from request descriptor to reply descriptor, so it's easy to unit test.

### AppleEventCore module

- **Dispatcher.** A registry keyed by (event class, event ID). Each command conforms to a small `AppleEventCommand` protocol. An event nothing is registered for returns `errAEEventNotHandled` (-1708).
- **Parameter access.** Typed helpers such as `required(.string, "in  ")` and `optional(.bool, "CaSe", default: true)`. They coerce with the same rules as AppleScript/Satimage. A missing required parameter gives -1701 and a coercion failure gives -1700.
- **Value conversion** between Swift values and `NSAppleEventDescriptor`, in both directions: text (`utxt`/`TEXT`), integer, real, boolean, list, record (4-char keys plus `usrf` user fields), date, data, `missing value`, and file references (`alis`, `furl`, `fsrf`, and POSIX/HFS path strings, since many Satimage commands accept a string or an alias).
- **Errors.** One `OSAXError(number:, message:)` type that the dispatcher writes into the reply as `keyErrorNumber`/`keyErrorString`, so scripts get the same `try … on error n` behavior as with Satimage.

### Diagnostic commands (this branch)

A new **hidden** suite (`hidden="yes"` on the suite and its commands), **Diagnostics**, with its own event class `MTCd`, which doesn't collide with any Satimage class:

| Command | Returns | Purpose |
|---|---|---|
| `mtc_ping` | `"pong"` | Shows that the app launches and receives events |
| `mtc_version` | e.g. `"MTC_OSAX 0.1 (1)"` | Shows which build answered |
| `mtc_echo <anything>` | the direct parameter, unchanged | Tests the conversion of descriptors in and back out |
| `mtc_describe <anything>` | text showing the descriptor types/keys that were received | Debugging: shows exactly what AppleScript sent |
| `mtc_raise_error <text> number <n>` | raises that error | Checks that errors reach the script |

Hiding a suite only removes it from the dictionary viewer; its terms are still reserved in any script with `use application "MTC_OSAX"`. The `mtc_` prefix keeps these names from colliding with variable or handler names in existing scripts. Parameter names are reserved too, so `mtc_raise_error` mirrors AppleScript's own `error "text" number n` and uses the existing `number` term (code `errn`) instead of adding a new one.

### SDEF strategy

- `MTC_OSAX.sdef` is assembled from Satimage's definitions **copied verbatim** (names, codes, parameters, types, synonyms such as `ufind text`), one section at a time as each is implemented, plus the Diagnostics suite.
- If a script uses a command that isn't implemented yet, it fails at compile time with a clear error, rather than failing at run time.
- **Consistency tests**, which run with the unit tests:
  1. Every command in `MTC_OSAX.sdef` has a registered handler, and every handler has an SDEF entry.
  2. Every command, parameter, record and enumeration copied from Satimage has the same name and code as in `SatImageOSAX SDEF/dictionary.sdef`.

## Testing

Swift Testing (`@Test`) will be used in the package. These are the layers:

1. **Unit tests** of the conversion layer, the dispatcher and each command's logic. They are pure Swift and have no permission requirements.
2. **Handler tests.** Build an Apple event in the test, pass it to the dispatcher in the same process, and check the reply. No app launch and no TCC.
3. **Satimage fixtures**, so the tests keep working after SatimageOSAX is gone:
   - `FixtureRecorder` reads a case file for each section (an AppleScript snippet for each case), runs each case against SatimageOSAX, and captures the **outgoing Apple event and the reply** by installing an OSA send proc (`OSASetSendProc`). Both are written to JSON under `Tests/Fixtures/<Section>/` with the descriptor types spelled out.
   - The fixture tests feed the recorded request to our dispatcher and compare our reply with the recorded one. This checks the full event, not just the string AppleScript would show.
   - If the send-proc approach doesn't work under Rosetta, the fallback is to record only the AppleScript result (made persistent as a descriptor) and build the request by hand in the test.
   - The recorder is checked in and documented, but it can only produce new fixtures while SatimageOSAX runs. The fixtures themselves are committed.
4. **End-to-end scripts** (`Scripts/e2e/*.applescript`, run with `osascript`). They run against the built app, and can also run against SatimageOSAX by switching the `use` line (parity check). They need Automation permission, so they're run by hand, not as part of `swift test`.

The recorder lives in the package (`Sources/FixtureRecorder`) rather than a separate `Tools/` folder, so it shares the fixture code with the tests.

This branch includes the recorder, fixtures for the Diagnostics commands (recorded from our own app, since Satimage has nothing to compare against), and one Satimage fixture (e.g. `uppercase "abc"`) to show that recording and replay work.

## App configuration

- `MTC_OSAX.app` (bundle ID `com.mactechnologies.mtc-osax`), so scripts use `use application "MTC_OSAX"`.
- Faceless app: `LSBackgroundOnly = YES`, `NSAppleScriptEnabled = YES`, `OSAScriptingDefinition = MTC_OSAX.sdef`. It launches on demand when a script targets it.
- **Idle quit:** the app quits after 1 hour with no Apple events. Every event resets the timer, and the app never quits while a command is running. The next script that targets it relaunches it automatically. The timeout is a single constant, and a hidden defaults key lets tests shorten it.
- Deployment target macOS 26.6, Apple silicon (arm64) only, Swift 6 language mode.
- **No App Sandbox**, because commands such as `readtext`, `filecopy` and `glob` need arbitrary file access. Hardened Runtime on.
- Signed with your development identity. Developer ID and notarization come later.

## Done when

- [x] `xcodebuild test` passes (unit, handler, consistency and fixture tests).
- [x] `use application "MTC_OSAX"` then `mtc_ping` returns `"pong"`, and the other diagnostic commands work, including errors (16 checks in `Scripts/e2e/diagnostics.applescript`, run with `osascript`).
- [x] Open MTC_OSAX's dictionary in Script Editor and confirm the Diagnostics suite is hidden (checked 2026-09-27: the dictionary shows nothing, since Diagnostics is the only suite so far).
- [x] The app quits after the idle timeout (checked with a shortened timeout) and relaunches on the next event.
- [x] `FixtureRecorder` records one SatimageOSAX case, and a test replays it against a stub handler.
- [x] A README section on building, running the tests, granting Automation permission, and recording fixtures.

## Decisions

- App name: `MTC_OSAX.app`; bundle ID `com.mactechnologies.mtc-osax`.
- Minimum macOS: 26.6.
- Diagnostic commands: `mtc_` prefix (to avoid reserving common words in scripts), suite hidden.
- Idle quit after 1 hour.

## Findings during implementation

- The OSA send-proc approach works under Rosetta: `fixture-recorder` captures the exact events AppleScript sends to SatimageOSAX and its replies. `OpenDefaultComponent` isn't available to Swift; `OSALanguageInstance.componentInstance` supplies the AppleScript component instead.
- SatimageOSAX returns text as `ut16` (UTF-16 with a byte-order mark), not `utxt`. Replay comparisons treat all text encodings as equal, and `true`/`fals`/`bool` likewise.
- AppleScript sends an omitted direct parameter as `null`, and Satimage answers -1701. `AppleEventRequest` treats `null` as missing.
- Standard errors (-1700, -1701) come back from Satimage with no `errs` message, so AppleScript supplies its usual text. `OSAXError` does the same.
- Raw `NSAppleEventManager` handlers work with `NSAppleScriptEnabled = YES`. They're installed in `applicationWillFinishLaunching` and again in `applicationDidFinishLaunching`, in case Cocoa Scripting replaced them.
- The first Apple event from a new sender waits (and times out after 2 minutes) until the user answers the Automation dialog.
- Verified: 16 end-to-end checks pass through iTerm; idle quit tested with a 5-second timeout (quit on its own, relaunched on the next command); `xcodebuild test` passes (50 + 9 + 12 + 4 test functions).
