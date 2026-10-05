# Files and Folders Plan

Branch: `feature/files_and_folders`

Goal: implement Satimage's **Files and folders suite** and **Symlink suite** (priority 2 in [PLAN.md](../PLAN.md)), matching SatimageOSAX where it works and following the dictionary's documentation where it doesn't.

## Scope

Both suites use the event class `Quom` (from Satimage's Files.osax):

| Command | Code | What it does |
|---|---|---|
| `filenew` | `QuomNewF` | Create an empty file (fails if it exists); `name`, `recursively` |
| `mkdir` | `QuomMkDi` | Create a folder; `name`, `recursively` (default true) |
| `filecopy` | `QuomCopy` | Copy file(s): `from` (base for relative paths), `to` + `name`, or `filepath`/`into`; `replacing`, `full copy` |
| `filemove` | `QuomMove` | Move file(s); same parameters as `filecopy` |
| `fileremove` | `QuomRemo` | Delete file(s) or folder(s): `from`, `filesonly` (a folder means its files), `after`/`before` (dates, with `filesonly`), `locked files`, `busy files` |
| `filegetname` | `QuomGFNa` | A file's name, or each name of a list |
| `filerename` | `QuomRenF` | Rename in place; returns the renamed file |
| `mkstemp` | `Quommkst` | Create a uniquely named file from a template: `name`, `suffix`, `wildcards`, `mode` |
| `mkdtemp` | `Quommkdt` | Create a uniquely named folder: `name`, `wildcards`, `mode` |
| `chmod` | `Quomchmd` | Get, or set with `to`, permissions as an octal string; returns the previous permissions |
| `create symlink` | `QuomSymL` | Create a symbolic link to a target (alias or absolute/relative POSIX path) `in` a folder; `name`, `replacing` (default true) |
| `testsymlink` | `QuomIsSy` | Whether a path is a symbolic link (an alias would be resolved, so a path or URL) |
| `readlink` | `Quomrdsy` | A symbolic link's contents |

None of the scripts in `~/Documents/AppleScript Projects` use these commands, so there are no call shapes to prioritize; every parameter gets fixtures.

## Behavior to establish from fixtures

The dictionary leaves these open; recording SatimageOSAX settles them (and where Satimage fails, the documentation wins, per the project rule):

- **Accepted paths.** "Alias must be understood as alias or posix path or url": aliases, file references, POSIX paths (with `~`), `file://` URLs, and probably HFS paths. Relative POSIX paths with `from`.
- **Results.** Commands documented to return an alias: whether Satimage returns an alias (`alis`), a file URL (`furl`) or a path. Scripts use the result with `POSIX path of`, `as text` or the Finder, so the type matters.
- **Errors.** Numbers for an existing file (`filenew`), a missing file or folder, a missing intermediate folder without `recursively`, a destination that exists without `replacing`, invalid permission strings, and parameters documented as not allowed together (`name` or `filepath` with a list).
- **Details.** `filecopy`'s `full copy` (which attributes); `filemove` across volumes; `fileremove` with `filesonly` and dates (modification or creation date? inclusive?), locked files (`uchg`), busy files; `filerename` to an existing name; `mkstemp`'s `suffix` counting; `chmod` string format (`"644"` or `"0644"`); `create symlink` relative targets and `replacing`; `testsymlink` on a missing path; `readlink` on a non-link.

## Architecture

- **Module `FilesAndFolders`**, next to `TextAdditions`, registered in `CommandCatalog`. File work through `FileManager` and POSIX calls (`mkstemp`, `mkdtemp`, `chmod`, `symlink`, `readlink`, `lstat`, `chflags`).
- **Path input** shared in `AppleEventCore`: extend `URL(appleEventDescriptor:)` with `file://` URL strings and a base URL for relative paths (`from`). Lists accepted wherever the dictionary allows them.
- **Alias results.** If Satimage returns aliases, results are made by coercing a file URL descriptor to `typeAlias` (which requires the item to exist, as it always will for these results). A shared helper in `AppleEventCore` so File Additions can use it too.
- **Dictionary.** Copy both suites verbatim. Add hidden definitions for `posix path` and `url`, which Satimage's dictionary uses but never defines, if the SDEF tools need them.

## Testing

Everything that touches files runs only inside temporary folders: `$TMP` in fixtures, a new temporary folder per unit test. `fileremove` tests never point outside them.

The fixture tooling needs three additions:

- **Aliases in fixtures.** An alias descriptor's data holds the absolute path and volume information, so it can't be moved to another checkout. Snapshots will store an alias as its POSIX path (like file URLs), so `$TMP` substitution works, and recreate it by coercion. Replays compare aliases and file URLs by path.
- **Setting up files.** Cases create what they need with `filenew`, `mkdir` or `writetext` (MTC_OSAX has it now) inside `$TMP` in the same script, so every fixture is self-contained. `$FILES` inputs only where fixed content matters.
- **Random names.** `mkstemp` and `mkdtemp` return random names. Their fixtures will store the random part as a wildcard, and replays match it by pattern (same prefix, suffix and length).

Also: unit tests per command (including permissions, flags, dates and symbolic links), SDEF consistency (already automatic), and `Scripts/e2e/files.applescript` in `/private/tmp`, run through `Scripts/parity.sh` against both apps for shared behavior. The Automation permission for iTerm is already in place; nothing here touches protected folders, so no new privacy prompts are expected.

## Order of work

1. Fixture tooling: alias snapshots, path comparison, wildcard names; unit tests for them.
2. Copy both suites into the SDEF, with placeholder handlers.
3. Record SatimageOSAX fixtures for all 13 commands; review and settle the open behaviors above.
4. `filegetname`, `filenew`, `mkdir`, `filerename`, `chmod`.
5. `filecopy`, `filemove`, `fileremove`.
6. `mkstemp`, `mkdtemp`.
7. `create symlink`, `testsymlink`, `readlink`.
8. Anything Satimage gets wrong: implement from the documentation, record from MTC_OSAX into a `FilesAndFoldersFixes` fixture folder, and list it in this plan.
9. End-to-end and parity scripts.

## Done when

- [x] All 13 commands implemented; SDEF consistency tests pass.
- [x] SatimageOSAX fixtures for every command and parameter replay without differences; every deviation (a Satimage bug fixed) listed here with MTC_OSAX fixtures.
- [x] Unit tests for every command, including error cases.
- [x] Fixture tooling handles aliases and random names, with unit tests.
- [x] `Scripts/e2e/files.applescript` passes, and `Scripts/parity.sh` shows no differences for shared behavior.

## Decisions

Made 2026-09-27:

1. HFS path strings (`"Macintosh HD:Users:…"`) are accepted wherever a file is, alongside aliases, file references, POSIX paths and `file://` URLs.
2. `fileremove` deletes permanently, as documented. No Trash option.

## Findings during implementation

Recorded from SatimageOSAX in `Fixtures/FilesAndFolders` (117 cases, generated by `generate.py` there), all replaying without differences:

- **Results are POSIX paths as text**, not aliases as the dictionary says; folders end with `/` (except `filerename`'s result). `fileremove` returns the number of items removed, `create symlink` nothing, `chmod` octal text (`"644"`).
- **Errors:** -48 for an existing item, -43 for a missing one, -50 for `name` or `filepath` with a list, -1 for invalid input (bad permissions text, `/` in a new name, a date without `filesonly`, `readlink` of a non-link), and POSIX numbers from `mkdir` (17 exists, 2 missing folder).
- **Kept although it differs from the dictionary:** `filenew` creates missing folders on the way even without `recursively`. That's more lenient than documented, but it works, so scripts may rely on it.
- `filesonly` removes only the files directly in the folder; subfolders and their contents stay. Dates compare modification dates.
- `create symlink` keeps text targets as written (relative stays relative); file references and aliases become absolute. `replacing` only replaces links, never files.
- Aliases sent by scripts are stored in fixtures as paths (they hold absolute binary paths) and replayed as file URLs. `mkstemp`/`mkdtemp` names are stored with `{{random:N}}`, marked by `mark_random.py`.

## Fixing Satimage's bugs

Recorded from MTC_OSAX in `Fixtures/FilesAndFoldersFixes`, with unit tests and `Scripts/e2e/files-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| HFS paths | `filegetname` of an HFS path: error 143 | Accepted, as decided |
| Path strings in system folders | `mkdir`/`filenew` of a string path directly in a root-owned folder such as `/private/tmp`: error 1 | Work |
| `mkdtemp` | Ignores `wildcards` (always 6) | Honors it |
| `fileremove … with filesonly` | Always reports 0 removed (and a later `mkdir` of a kept subfolder gave error 1) | The real count (and 17 for the existing folder) |

## Framework fix found along the way

`POSIX file` of a variable makes AppleScript ask the app to evaluate it (`core/getd`). Cocoa Scripting answers, but the first time it does, it loads the dictionary and installs its own handlers for every command, replacing MTC_OSAX's; every command then failed with -1708 until the app quit. The app now loads Cocoa Scripting's registry at launch, before installing its own handlers. `Scripts/e2e/diagnostics.applescript` checks this.
