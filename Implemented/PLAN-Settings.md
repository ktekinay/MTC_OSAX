# Settings Commands Plan

Branch: `feature/settings`

Goal: let scripts read and change MTC_OSAX's settings with commands, instead of `do shell script "defaults write …"`. This is an MTC_OSAX extension: SatimageOSAX had no settings. Noted in [PLAN.md](../PLAN.md) on 2026-09-28.

## The settings

Three today, all in MTC_OSAX's defaults domain (`com.mactechnologies.mtc-osax`), read when they're needed, so a change applies from the next command without restarting the app:

| Constant | Friendly name | `defaults` key | Type | Default | What it does |
|---|---|---|---|---|---|
| `idle_timeout` | `"idle timeout"` | `IdleTimeoutSeconds` | integer, 0 or more | 3605 (an hour and five seconds: on the hour, an hourly job met the quit every time) | Seconds without commands before the app quits; 0 means never. It doesn't quit while documents are open either way. |
| `dollar_references` | `"dollar references"` | `DollarReferences` | boolean | false | `$1`-style references in replacement templates when a command doesn't say. |
| `regex_syntax` | `"regex syntax"` | `RegexSyntax` | text: a syntax name | `"RUBY"` | The regex syntax when a command doesn't say, e.g. `"PCRE"`. |

New settings are added to one list (see Architecture) and appear in every command automatically.

## Commands

Settings are global and permanent: a change affects every script that uses MTC_OSAX, including scripts run later and after MTC_OSAX or the Mac restarts, until it's changed again or reset. The dictionary (the suite's, `mtc_set`'s and `mtc_reset`'s descriptions) and the README say so, and point to each command's own parameters (`syntax`, `dollar references`) for changing a single command (decision 5).

Three commands, named with the `mtc_` prefix so no common word becomes reserved in scripts. Commands rather than application properties keep Cocoa Scripting's object model out of the app (see PLAN.md).

```applescript
mtc_get regex_syntax                   --> "RUBY"
mtc_set regex_syntax to "PCRE"
mtc_set idle_timeout to 300
mtc_reset regex_syntax                 -- back to the default
mtc_reset all_settings                 -- every setting back to its default
mtc_get "regex syntax"                 -- the same setting, by its friendly name
mtc_get "RegexSyntax"                  -- or its defaults key
mtc_get all_settings
--> {{name:idle_timeout, key:"IdleTimeoutSeconds", value:3605, default value:3605, is default:true, description:"…"}, …}
```

- **`mtc_get <name>`:** the value in effect: the stored value if it's valid, otherwise the default (as the command that uses it would see it).
- **`mtc_get all_settings`:** a record per setting, in a fixed order: `name` (the constant, which can be passed straight back to `mtc_get` and `mtc_set`), `key` (the `defaults` key), `value` (in effect), `default value`, `description`, and `is default` (true when nothing valid is stored). It can also be written as text: `"all settings"`, `"AllSettings"` or `"all_settings"`, matched like setting names.
- **`mtc_set <name> to <value>`:** checks and stores the value. Values are normalized when stored: `"pcre"` is stored as `"PCRE"`, a real like `300.0` as the integer 300. `to missing value` is error -1700 with a message pointing to `mtc_reset` (decision 4); `mtc_set all_settings` is error -50.
- **`mtc_reset <name>`:** removes the stored value, so the default applies; `mtc_reset all_settings` resets every setting. Returns nothing.
- **Names** (decision 2): each setting is a dictionary constant written with underscores (`regex_syntax`), which shows in the dictionary viewer and is unlikely to clash with a script's own variables, since snake_case is rare in AppleScript. A setting can also be named with text: its friendly name (`"regex syntax"`), its `defaults` key (`"RegexSyntax"`) or the constant's name (`"regex_syntax"`). Text is matched ignoring case, spaces and underscores, so `"Regex Syntax"` and `"regexsyntax"` work too; it's useful when the name is in a variable. A misspelled constant (`regex_syntx`) compiles as an undefined variable and fails when it runs.

### Errors

| Case | Error |
|---|---|
| Unknown setting name (text) | -1728 (no such object), with a message listing the settings |
| A value of the wrong kind (text for `idle_timeout`, a list, …) | -1700 (can't make it into the expected type) |
| A value of the right kind that isn't allowed (a negative timeout, an unknown syntax name) | -50 (parameter error), with a message saying what's allowed |
| No name, or `mtc_set` without `to` | -1701 (missing parameter) |
| `mtc_set all_settings` | -50 |

## Dictionary

A new suite of its own, "MTC_OSAX Settings" (event class `MTCs`), visible in the dictionary (decision 1), with an enumeration `setting` of the constants, and a record type `setting info` for `mtc_get all_settings`'s records:

| Command | Code | Parameters |
|---|---|---|
| `mtc_get` | `MTCsget ` | direct: a `setting` constant or text; result: the value, or a list of `setting info` for `all_settings` |
| `mtc_set` | `MTCsset ` | direct: a `setting` constant or text; `to` (`to  `): any value |
| `mtc_reset` | `MTCsrset` | direct: a `setting` constant or text |

Enumeration `setting` (`MTst`): `all_settings` (`MTsa`), `idle_timeout` (`MTsi`), `dollar_references` (`MTsd`), `regex_syntax` (`MTsr`). Record properties: `name` (`pnam`), `key` (`MTky`), `value` (`valL`), `default value` (`MTdv`), `description` (`dscr`), `is default` (`MTid`). The SDEF consistency test treats `MTCs` as MTC_OSAX's own, like `MTCd`.

## Architecture

- **`Sources/Settings`**, a new module: a `Setting` type (constant and its code, friendly name, `defaults` key, description, default, and a function that checks and normalizes a value), the list of settings, and the three commands. The commands read and write a `UserDefaults` given to them (the app passes `.standard`; tests pass a separate suite).
- **One source of truth.** The code that uses each setting reads it through the same definitions: `IdleMonitor`'s timeout, and `TextContext`'s `dollarReferencesDefault` and `regexSyntaxDefault`. Their current behavior is kept (a missing or invalid stored value means the default).
- **Where settings live:** `Settings` depends on `AppleEventCore` and `TextMatching` (for the syntax names); `TextAdditions` and the app use `Settings` for the keys and parsing.

## Testing

- Unit tests with a separate `UserDefaults` suite: get, set, reset, list, names as constants and as each kind of text (ignoring case, spaces and underscores), normalization, each error, and that the text commands and idle timeout see a value set by `mtc_set` (and the default after `mtc_reset`).
- Fixtures recorded from MTC_OSAX in `Fixtures/Settings`: each case sets what it reads and resets it at the end, so the recording doesn't depend on (or leave behind) the machine's settings; replays use a fresh suite.
- End to end: `Scripts/e2e/settings.applescript` (MTC_OSAX only), which saves each setting's value first and restores it at the end.

## Order of work

1. The `Settings` module and its list; existing readers switched to it, with their tests unchanged.
2. The three commands, the SDEF suite, enumeration and record type; unit tests.
3. Fixtures, the e2e script.
4. README: the settings commands (with the `defaults` commands kept as an alternative) and "New features" in "Differences from SatimageOSAX".

## Done when

- [x] `mtc_get` (including `all_settings`), `mtc_set` and `mtc_reset` (including `all_settings`) work for all three settings, with the errors above.
- [x] A change made with `mtc_set` or `mtc_reset` applies from the next command.
- [x] Unit tests, fixtures and the e2e script pass; all existing tests still pass.
- [x] README updated, including the differences section.

## Findings

- **Reused terms.** The `setting info` record's `key` and `value` use the codes those words already have in Satimage's dictionary (`key `, `val `), so the terms don't conflict; `name` and `description` use AppleScript's usual `pnam` and `dscr`.
- **The enumeration's name isn't reserved:** a script can still have a variable called `setting`.
- **Fixture replays and tests** get a defaults suite of their own (`CommandCatalog.makeDispatcher(settings:)`, `TextAdditions.commands(settings:)`), so they never read or change the machine's settings. The fixtures were recorded with the settings at their defaults, and each case resets what it sets.
- **Values written with `defaults`** read as the code using them always has: numeric text for `IdleTimeoutSeconds`, `YES`/`NO` text for `DollarReferences`, and an invalid value means the default (`is default` is then true).
- Recorded from MTC_OSAX in `Fixtures/Settings` (12 cases); `Scripts/e2e/settings.applescript` (19 checks) saves the settings first and restores them.

## Decisions

Made 2026-09-28:

1. The settings commands are visible in the dictionary, in a suite of their own (not the hidden diagnostics suite).
2. Settings are named by dictionary constants written with underscores (`regex_syntax`), or by text: the friendly name (`"regex syntax"`), the `defaults` key (`"RegexSyntax"`) or the constant's name, matched ignoring case, spaces and underscores.
3. The commands are `mtc_get <name>`, `mtc_set <name> to <value>` and `mtc_reset <name>`; `all_settings` (or the text `"all settings"`, `"AllSettings"`, any case) stands for every setting with `mtc_get` and `mtc_reset`.
4. `mtc_set … to missing value` is error -1700, with a message pointing to `mtc_reset`: there's one way to reset.
5. The dictionary and the README make clear that a setting is a global change that affects all scripts from then on (asked for 2026-09-28).
