# Potential issues

What an audit of MTC_OSAX (October 2026) found and left unaddressed. Nothing here loses files, corrupts data or stops the app on its own: everything rated high or medium was fixed on the `feature/audit_fixes` branch, and these are the low-severity leftovers, plus a few performance notes and two steps that only the maintainer can take.

Line numbers were refreshed at commit `fc3b8bb` (2026-10-02). They will drift; the function names won't.

## How to read this

Each issue keeps the ID the audit gave it (`L33`, …). Commit messages on the audit branch use the same IDs ("Audit L49"), so `git log --grep "L49"` finds how a neighbouring issue was fixed. The audit document itself was not kept.

**Evidence** says how sure the finding is:

| Label | Meaning |
|---|---|
| Reproduced | The behaviour was seen, in a unit test or against the running app. |
| Read only | Found by reading the code. Nobody has run it. Reproduce it before fixing it. |
| Mitigated | Partly fixed; what's left is described. |

"SatimageOSAX" is the app MTC_OSAX replaces. The project's rule is to match what it does where it works, and to do what its dictionary says where it's broken.

## Before changing anything

These are the project's working rules. The README's Tests section has the details.

- **Run tests only with `Scripts/test.sh`.** It runs `swift test` in a sandbox, and the tests refuse to run outside one. A test of a file command may only name paths inside its own temporary folder: never `/`, `~`, a home or system path, or a `..` that climbs out, not even to check that the command refuses it.
- **Send Apple events only through `Scripts/iterm-run.sh`.** A process started from an editor has no Automation permission (error -1743). End-to-end scripts run with `Scripts/run-e2e.sh`.
- **Every fix needs a unit test.** Where SatimageOSAX's behaviour is the reference, record it as a fixture; where MTC_OSAX deliberately differs, the fixture goes in the matching `…Fixes` folder.
- **Keep the README's "Differences from SatimageOSAX" section current** for anything a script could notice.
- **Check what SatimageOSAX does before deciding a fix**, while it still runs (it's Intel-only and needs Rosetta). Where that was already checked, the issue says so.

## Summary

| ID | Area | Issue | Evidence | Size of fix |
|---|---|---|---|---|
| [L42](#l42-plistnew-builds-trees-past-the-depth-limit-through-references) | Property lists | `PlistNew` builds trees past the depth limit | Reproduced | Small |
| [L43](#l43-yaml-timestamps-large-offsets-and-daylight-saving-gaps) | Property lists | YAML timestamps: large offsets, daylight-saving gaps | Reproduced | Small |
| [L44](#l44-plisttojson-fails-on-text-with-a-lone-surrogate) | Property lists | `PlistToJSON` fails on text with a lone surrogate | Reproduced | Small |
| [L53](#l53-integer-text-just-under-the-32-bit-limit-becomes--2147483648) | Lists and numbers | Integer text just under 2³¹ becomes -2147483648 | Reproduced | Small |
| [L55](#l55-a-huge-array-of-real-is-turned-into-one-descriptor-per-number) | Lists and numbers | A huge `array of real` becomes one descriptor per number | Read only | Medium |
| [L56](#l56-a-fractional-idle-timeout-from-defaults-write-is-used) | Settings | A fractional idle timeout from `defaults write` is used | Reproduced | Small |
| [L57](#l57-xmlerror-is-empty-after-xmlopen--with-html4-and-xmlscript) | XML | `XMLError` is empty after `XMLOpen … with html4 and xmlscript` | Reproduced | Small |
| [L58](#l58-xmlnodeinfo-counts-lines-wrongly-for-return-only-line-endings) | XML | `XMLNodeInfo` line for return-only line endings | Reproduced | Comment only |
| [L60](#l60-a-command-can-arrive-just-as-the-app-quits-for-being-idle) | App | A command can arrive just as the app quits for being idle | Mitigated | Hard |
| [L61](#l61-the-event-handlers-failure-paths-return--1708) | App | The event handler's failure paths return -1708 | Read only | Small |
| [L63](#l63-end-to-end-scripts-use-fixed-names-in-privatetmp) | Tooling | End-to-end scripts use fixed names in `/private/tmp` | Read only | Medium |
| [L64](#l64-iterm-runsh-has-no-signal-trap-and-joins-its-arguments) | Tooling | `iterm-run.sh`: no signal trap, arguments joined | Read only | Small |
| [L65](#l65-paritysh-and-dialogssh-report-success-wrongly) | Tooling | `parity.sh` and `dialogs.sh` report success wrongly | Read only | Small |
| [L66](#l66-mtc_test_time_limit-is-read-loosely) | Tooling | `MTC_TEST_TIME_LIMIT` is read loosely | Read only | Small |
| [L67](#l67-fixture-recorder-accepts-things-it-shouldnt) | Tooling | `fixture-recorder` accepts things it shouldn't | Read only | Small |
| [L68](#l68-some-tests-depend-on-the-mac-they-run-on) | Tooling | Some tests depend on the Mac they run on | Read only | Medium |

Further down: [performance notes](#performance-notes) and [steps for the maintainer](#steps-for-the-maintainer).

---

## Property lists

### L42. `PlistNew` builds trees past the depth limit through references

- **What happens:** values are limited to 512 levels of nesting. `PlistNew` of a list that holds a reference to an existing element copies that element in without counting its height: a 400-level list around a reference, three times over, gave a tree 1,600 deep.
- **Where:** `node(from:)` in [Conversion.swift:117-120](Packages/MTCOSAXKit/Sources/PropertyLists/Conversion.swift#L117-L120): the reference branch returns the copy without a check.
- **Evidence:** Reproduced.
- **Suggested fix:** in that branch, throw `tooDeep` unless `depth + source.height <= maximumDepth`. `PlistSet`, `PlistNewChild` and `PlistAdd` already check (see `checkDepth` at line 29).
- **Why it matters:** the limit exists because very deep trees made later commands slow or crashed them. The script is trusted, so this is only reachable by a script doing it to itself.

### L43. YAML timestamps: large offsets and daylight-saving gaps

- **What happens:** two things.
  - An offset past ±18 hours (`+19:00`) is read in the Mac's time zone, because `TimeZone` refuses the offset and the fallback is the local zone.
  - A local time that doesn't exist (`2026-03-08 02:30:00` in New York) becomes text rather than a date.
- **Where:** [YAML.swift:213](Packages/MTCOSAXKit/Sources/PropertyLists/YAML.swift#L213) (the `?? timeZone` fallback), `offsetZone` at line 222, `isValidDate` at line 238.
- **Evidence:** Reproduced.
- **Suggested fix:** do as the TOML reader does: read the fields as UTC and subtract the offset. Decide what a time in a gap should be (TOML's behaviour is the precedent).

### L44. `PlistToJSON` fails on text with a lone surrogate

- **What happens:** error -1 for a property list whose text holds half of a surrogate pair. A binary property list file can carry such text.
- **Where:** `stringify` in [JSON.swift:21-26](Packages/MTCOSAXKit/Sources/PropertyLists/JSON.swift#L21-L26) (`JSONSerialization` refuses it).
- **Evidence:** Reproduced, including with text read from a binary property list.
- **Suggested fix:** replace lone surrogates with U+FFFD before serializing, or write them as `\uD800`-style escapes, which JSON allows. Say which in the README.

## Lists, numbers and settings

### L53. Integer text just under the 32-bit limit becomes -2147483648

- **What happens:** `"2147483647.6"` given where an integer is expected passes the range check, which is made on the unrounded number, and then rounds to 2³¹, which the coercion turns into -2147483648.
- **Where:** `Int.init(appleEventDescriptor:)` in [AppleEventConvertible.swift:72-80](Packages/MTCOSAXKit/Sources/AppleEventCore/AppleEventConvertible.swift#L72-L80).
- **Evidence:** Reproduced.
- **Suggested fix:** check the rounded value (`real.rounded()`), so this is -1700 like `"3000000000"`.
- **SatimageOSAX:** checked; it rounds text (`starting at "2.6"` is 3), which must stay, and takes text past 32 bits as garbage.

### L55. A huge `array of real` is turned into one descriptor per number

- **What happens:** an `array of real` is a compact block of numbers, but a few places expand it to a list with one descriptor per number, which for a hundred million numbers takes gigabytes and minutes.
- **Where:** the result of `exclude items` and `keep items` in [ListUtilities.swift:199-201](Packages/MTCOSAXKit/Sources/ListUtilities/ListUtilities.swift#L199-L201); `suppress item`'s parameters at line 126; `mtc_describe` in [Diagnostics.swift:25](Packages/MTCOSAXKit/Sources/Diagnostics/Diagnostics.swift#L25).
- **Evidence:** Read only. At ordinary sizes it's fine: `exclude items` from 200,000 reals takes 0.15 s.
- **Suggested fix:** needs a decision. The result of `exclude items` is documented as a list, so either cap the size (as `createarray` caps at 100,000,000 with -50) or build the list's bytes directly instead of one descriptor at a time.

### L56. A fractional idle timeout from `defaults write` is used

- **What happens:** `defaults write … IdleTimeoutSeconds 0.001` makes the app quit a millisecond after each command. The README says anything but a whole number counts as not set, and `mtc_set` enforces that, but the reader of the stored value doesn't.
- **Where:** `IdleMonitor.seconds(in:key:)` in [IdleMonitor.swift:43-53](Packages/MTCOSAXKit/Sources/AppleEventCore/IdleMonitor.swift#L43-L53).
- **Evidence:** Reproduced.
- **Suggested fix:** return nil unless `seconds == seconds.rounded()`.

## XML

### L57. `XMLError` is empty after `XMLOpen … with html4 and xmlscript`

- **What happens:** the same HTML opened with `html4` alone leaves "Unexpected end tag : b" in `XMLError`. With `xmlscript` added, `XMLError` is empty: the check of each script element starts a new collection of problems, which replaces the parse's own.
- **Where:** `checkScripts` in [Parsing.swift:90-108](Packages/MTCOSAXKit/Sources/XML/Parsing.swift#L90-L108), called at line 76. `XMLIssues.collect` in [Documents.swift](Packages/MTCOSAXKit/Sources/XML/Documents.swift) empties the collection each time it's called.
- **Evidence:** Reproduced.
- **Suggested fix:** keep the parse's problems and add the scripts' to them.
- **SatimageOSAX:** can't be compared. It fails to open any HTML with a recoverable error (801 or 76), so it never has an `XMLError` for this case. This is about MTC_OSAX being consistent with itself.

### L58. `XMLNodeInfo` counts lines wrongly for return-only line endings

- **What happens:** for a file with CR-only line endings, the line reported is 1, where the same file with LF or CR LF gives 4.
- **Where:** `firstTag` in [DOMCommands.swift:586](Packages/MTCOSAXKit/Sources/XML/DOMCommands.swift#L586).
- **Evidence:** Reproduced.
- **SatimageOSAX:** checked; it reports line 1 for the return-only file too. So this matches it, and the project's rule says leave it.
- **Suggested fix:** none to the behaviour. Add a comment at that line saying SatimageOSAX counts this way, so nobody "fixes" it.

## App and events

### L60. A command can arrive just as the app quits for being idle

- **What happens:** the app quits after `idle_timeout` seconds without a command. A command sent in the instant the process is going fails with error -609 (connection is invalid) in the sending script.
- **Evidence:** Mitigated. Before quitting, the app now handles any event already in its queue and then exits at once (commit `dcbb3e5`; see `drain` in [IdleMonitor.swift](Packages/MTCOSAXKit/Sources/AppleEventCore/IdleMonitor.swift) and its use in [AppDelegate.swift](MTC_OSAX/AppDelegate.swift)). In trials of 300 commands sent exactly one timeout apart, 3 to 5 still failed, out of about 20 quits. Those were sent after the last check, which nothing inside the app can catch.
- **What was done about the rest:** the default timeout is 3605 seconds rather than 3600 (commit `13f280f`), so a job that runs every hour no longer lands on the quit.
- **If it needs more:** the remaining window can only be closed from outside the app. A script can retry once on -609, and the README could say so. Never quitting (`mtc_set idle_timeout to 0`) avoids it entirely.

### L61. The event handler's failure paths return -1708

- **What happens:** when the handler can't copy the incoming event, or is called without its arguments, it returns -1708 ("not handled") to the system. The header of the same file explains that -1708 makes Cocoa Scripting take over, after which every later command fails until the app quits. Separately, the result of `AEInstallEventHandler` is ignored.
- **Where:** [AppleEventHandlerInstaller.swift:66-73](Packages/MTCOSAXKit/Sources/AppleEventCore/AppleEventHandlerInstaller.swift#L66-L73) and line 25.
- **Evidence:** Read only. The consequence couldn't be checked: there is no way to make `AEDuplicateDesc` fail on demand. It would take running out of memory.
- **Suggested fix:** return a different error from those paths (`errAEEventFailed`, -10000), and log or assert when a handler can't be installed.

## Tests and tooling

None of these affect the app a script talks to.

### L63. End-to-end scripts use fixed names in `/private/tmp`

- **What happens:** the scripts in [Scripts/e2e/](Scripts/e2e/) write to fixed names such as `/private/tmp/mtc-e2e-files` and `/private/tmp/mtc-e2e-text.txt`, delete those folders outside any sandbox, and leave files behind (17 at the last count). [parity.sh](Scripts/parity.sh) runs the same deletes through both apps. `/private/tmp` is shared between users, and the save commands follow links, so a link planted under one of those names would be written through. The README's `rm -rf /private/tmp/mtc-fixtures` is the same kind of name.
- **Evidence:** Read only (the leftover files were seen).
- **Suggested fix:** have `run-e2e.sh` make a folder with `mktemp -d`, pass it to each script, and remove it at the end.

### L64. `iterm-run.sh` has no signal trap and joins its arguments

- **What happens:** four things in [iterm-run.sh](Scripts/iterm-run.sh).
  - Interrupted before its timeout, its job stays in the queue and runs whenever a runner next looks, even days later.
  - `"$*"` joins the arguments (line 46), so an argument with spaces is split when the job is read back.
  - The job's `cd` has no `|| exit`.
  - A job's input is the terminal, so a command that reads input stalls the queue.
- **Evidence:** Read only.
- **Suggested fix:** a trap that removes the queued job on INT, TERM and HUP; write the arguments with `${(q)@}`; `cd … || exit`; run jobs with input from `/dev/null`.

### L65. `parity.sh` and `dialogs.sh` report success wrongly

- **What happens:** [parity.sh:24-26](Scripts/parity.sh#L24-L26) prints ✓ and exits 0 when both apps fail in the same way, because it only compares their output. [dialogs.sh:18](Scripts/manual/dialogs.sh#L18) returns `sed`'s status, not `osascript`'s.
- **Evidence:** Read only.
- **Suggested fix:** in `parity.sh`, say "both failed" and exit non-zero when the recorded exit status isn't 0; in `dialogs.sh`, `setopt pipefail` or test `$pipestatus[1]`.

### L66. `MTC_TEST_TIME_LIMIT` is read loosely

- **What happens:** the variable is read with `atof`. Empty or non-numeric text gives 0, which means no limit; `3m` is 3 seconds. Unset, the default of 180 seconds applies.
- **Where:** [TestTimeLimit.m:29](Packages/MTCOSAXKit/Sources/AppleScriptPreload/TestTimeLimit.m#L29).
- **Evidence:** Read only.
- **Why it's minor:** the limit is the second line of defence. The sandbox in `Scripts/test.sh` is what keeps a runaway test from doing harm.
- **Suggested fix:** parse with `strtod`, and end the process with a message when the text isn't wholly a number of 0 or more.

### L67. `fixture-recorder` accepts things it shouldn't

- **What happens:** three things.
  - A send that fails (no Automation permission, for one) is recorded as a good fixture, with a ✓.
  - `--only` with a name that matches no case exits 0.
  - A case named `cases-…` is recorded but never replayed: replay skips every file whose name starts with `cases`, while the check on names only refuses the cases file's own name.
- **Where:** `problem(withCaseName:casesFile:)` in [Fixture.swift:234-240](Packages/MTCOSAXKit/Sources/AppleEventCore/Fixture.swift#L234-L240), and the recorder's command-line tool.
- **Evidence:** Read only.
- **Suggested fix:** fail on a transport error (as opposed to an error the app replied with, which is a legitimate thing to record); exit non-zero when `--only` matches nothing; refuse any case name starting with `cases`.

### L68. Some tests depend on the Mac they run on

- **What happens:** three groups of tests can fail on another Mac or under load, though the code is right. None can pass wrongly.
  - About 20 `url-*` fixtures compare `kind`, a localized description that depends on the system language and on which apps are installed.
  - Three tests assume a case-insensitive volume.
  - About a dozen tests have wall-clock limits that heavy load or a sanitizer can exceed. One did, under AddressSanitizer, and was narrowed.
- **Evidence:** Read only (apart from the one that failed).
- **Suggested fix:** each group needs its own. Leave `kind` out of the comparison, or compare it only when the language is English; skip the case tests on a case-sensitive volume (`pathconf` with `_PC_CASE_SENSITIVE`); replace time limits with a measure of work done, or scale them by an environment variable.
- **When it matters:** on moving to another machine, changing the system language, or adding continuous integration.

---

## Performance notes

From benchmarks on 2026-10-02 against the Release build. The benchmark scripts lived in a scratch folder and weren't kept. The method was an AppleScript that runs each command once to warm up, then several times, timing with `NSDate`, on generated data: 1 MB of text, 5,000 JSON records (600 KB), a 1.3 MB XML document of 10,000 items. The same script ran against SatimageOSAX where it could.

**Slower than SatimageOSAX** (everything else measured was equal or faster):

| Command | MTC_OSAX | Ratio | Notes |
|---|---|---|---|
| `PlistToJSON`, 5,000 records | 0.043 s | 2.4× slower | The maintainer chose to leave these three. |
| `PlistFromJSON`, 5,000 records | 0.055 s | 2.3× slower | Cost is in building MTC_OSAX's own node tree. |
| `PlistOpen`, 1 MB file | 0.055 s | 2.2× slower | Two micro-optimizations were tried and gave nothing. |
| `XMLTransform`, 10,000 elements | 0.023 s | 1.7× slower | The time is in macOS's libxslt, not MTC_OSAX's code. |

**No SatimageOSAX counterpart, mild:**

- `PlistToYAML` and `PlistFromYAML` take about twice as long as the JSON commands (0.10 s for 5,000 records). Values that start with a digit, a sign or a point still go through up to six Swift regexes in `resolve(plain:)` in [YAML.swift](Packages/MTCOSAXKit/Sources/PropertyLists/YAML.swift); a hand-written scanner would be faster.
- `PlistToTOML` takes about three times as long as `PlistToJSON` (0.12 s for 5,000 records). Not investigated.

**A known slow path in libxml2:** when it reports an error for a node in a document that has a URL, it walks back through all of that node's earlier siblings. A document opened from a file that really has thousands of validation errors therefore takes time that grows with the square of their number. The case where MTC_OSAX itself caused those errors (`XMLValidate` of an element) was fixed in `a230ebc`; a genuinely invalid large document still goes this way. Only the error path is affected.

## Steps for the maintainer

These need a person, not code.

- **Notarization.** [Scripts/release.sh](Scripts/release.sh) builds the Release app, checks its signature, and submits it for notarization. It has only been run as far as the signature checks. It needs credentials in the keychain first: `xcrun notarytool store-credentials mtc-osax-notary` (or set `MTC_NOTARY_PROFILE` to another profile name).
- **The pre-push hook is opt-in.** [Scripts/hooks/pre-push](Scripts/hooks/pre-push) does nothing until `git config core.hooksPath Scripts/hooks` is run in the clone.
- **`chmod` with text that isn't a mode** replies a bare -1 with no message. That was left on purpose: the SatimageOSAX fixtures record it that way, and fixture replay compares error messages exactly.
