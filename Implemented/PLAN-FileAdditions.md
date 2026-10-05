# File Additions Plan

Branch: `feature/file_additions`

Goal: implement the **Satimage File Additions** suite (priority 3 in [PLAN.md](../PLAN.md)), matching SatimageOSAX where it works and following the dictionary's documentation where it doesn't.

## Scope

All commands use the event class `SATI` (like Text Additions). The suite also defines one record type:

- `URL information` (`URLI`), the result of `URL info for`, with the properties `scheme`, `host`, `path` (escaped), `unix path` (unescaped), `name`, `user name`, `password`, `name extension`, `url parameters`, `url query`, `url fragment` and `type identifier`.

| Command | Code | What it does |
|---|---|---|
| `alias description for` | `SATIALIS` | Resolve a Finder alias file; returns the original item |
| `URL info for` | `SATIIURL` | Parse a URL (or an alias) into a `URL information` record; `size` adds the item's size |
| `absoluteURL` | `SATIaURL` | Resolve a relative URL against a base (`from`), or convert an alias or POSIX path (or a list) to a URL; `as` picks the result type (text URL, alias, `unix path`, `path`) |
| `relativeURL` | `SATIrURL` | The shortest relative URL from a base (`from`) to a URL |
| `list files` | `SATIlsfl` | List a folder's contents (or several folders'): `recursively` (default true; false also lists folders), `invisibles`, `of extension`, `conforming to` / `not conforming to` (UTIs), `starting with`, `ignoring packages`, `after` / `before` (modification dates), `names only`, `as` |
| `glob` | `SATIGlob` | List items matching shell patterns: `from` (working folder), `invisibles`, `of extension`, `not conforming to`, `after` / `before`, `names only`, `as` |
| `backup` | `SATISYNC` | Synchronize a folder `onto` another: `level` (0 report only, 1 sync, 2 sync and report), `after`, `recursively`, `except folders`, `except extensions`, `only extensions`; returns the report |
| `navchoose file` | `SATIstdf` | Open dialog for files: `with prompt`, `of type`, `of extension`, `starting at`, `multiple files` (default true), `show packages`, `open packages`, `invisibles`, `key` |
| `navchoose folder` | `SATIstfl` | Open dialog for folders: `with prompt`, `starting at`, `multiple files`, `open packages`, `key` |
| `navchoose object` | `SATIstob` | Open dialog for files or folders; same parameters as `navchoose folder` plus `show packages` |
| `navchoose volume` | `SATIstvo` | Choose a volume: `with prompt`, `starting at` |
| `navchoose file name` | `SATInwfl` | Save dialog (doesn't create the file): `with prompt`, `default name`, `with menu` / `menu index` (a popup menu), `starting at`, `show packages`, `open packages`, `key` |
| `navnew folder` | `SATIstnf` | Save dialog for a new folder name: `with prompt`, `starting at`, `open packages`, `key` |
| `navask save` | `SATInask` | The "save changes to …?" alert: `file name`, `action` (1 closing, 2 quitting); returns 1 Save, 2 Cancel, 3 Don't Save |

`key` means: remember the folder the user ends up in under this number, and start there next time when no `starting at` is given.

None of the scripts in `~/Documents/AppleScript Projects` use these commands (the only `backup` matches are `tmutil`), so there are no call shapes to prioritize; every parameter gets fixtures.

## Behavior to establish from fixtures

Recorded from SatimageOSAX; where Satimage fails, the documentation wins, per the project rule.

- **Result types.** The dictionary says aliases, but the Files and folders suite returned POSIX paths as text. For each command: alias, file URL or text, and in what form (`file://localhost/…` as in the `absoluteURL` examples, or `file:///…`); trailing `/` on folders; what each `as` value gives (`Unicode text`, `alias`, `unix path`, `path`, `file`, others).
- **`list files`.** Order of results (sorted? by name, case-insensitive?), whether folders are listed when `recursively` is true, packages as items or folders, invisibles (dot files, the hidden flag), `starting with` case sensitivity, extension matching case, UTI checks against folders and packages, a list of folders (one flat list or one list per folder), dates exclusive or inclusive.
- **`glob`.** Which features (`*`, `?`, `[…]`, `{a,b}`, `~`), order, whether folders are included and marked, relative patterns with `from` (results relative or absolute), no matches (empty list or error), a list of patterns.
- **URLs.** `URL info for` on file, http, mailto and malformed URLs; which properties are missing or empty text; what `size` returns for a folder. `absoluteURL` and `relativeURL` with `..`, queries and fragments, different hosts, and aliases.
- **`alias description for`.** Result format, and errors for an item that isn't an alias file or whose original is gone.
- **`backup`.** The report's format; whether sync copies only newer files, deletes items missing from the source, and how `after` and the `except`/`only` filters apply to folders. Recorded only inside `$TMP`.
- **Errors.** Missing items, a file where a folder is expected, invalid URLs, bad `as` types.

The dialogs can't be recorded automatically unless they're driven by UI scripting (see open question 2). What can be recorded without a person: errors from invalid parameters, and `navask save`'s button numbers.

## Architecture

- **Module `FileAdditions`**, next to `FilesAndFolders`, registered in `CommandCatalog`. It reuses `Paths` (moved to `AppleEventCore` if both modules need it) and the path input from `URL(scriptPath:)`.
- **Records.** `URL information` needs record keys with the suite's codes; results built with `AppleEventRecord`. If a result is an alias, it's made by coercing a file URL descriptor to `typeAlias`.
- **Listing.** `FileManager` enumerators with resource keys (`isHidden`, `isPackage`, `contentModificationDate`, `contentType`); UTI checks with `UTType.conforms(to:)`. `glob` uses `glob(3)` with `GLOB_BRACE | GLOB_TILDE | GLOB_MARK` as needed to match Satimage.
- **URLs.** `absoluteURL` and `relativeURL` built on `URL(string:relativeTo:)` and a path-component walk for relative results; `URL info for` from `URLComponents` and resource values.
- **Dialogs** (in the app target, since they need AppKit; the module defines a protocol and the app provides the implementation):
  - The app is `LSBackgroundOnly`. To show a panel it switches to the `.accessory` activation policy (no Dock icon, no menu bar), activates, runs `NSOpenPanel` / `NSSavePanel` / `NSAlert` modally, then goes back to the background.
  - Cancel returns error -128 ("User canceled"), as `choose file` does.
  - The idle timer doesn't count time while a dialog is open.
  - A long wait can hit the script's Apple event timeout (2 minutes by default), as in Satimage. Scripts can use `with timeout`; the reply is still sent when the user answers.
  - `key` folders are stored in the app's user defaults.
  - Unit tests use a fake panel through the protocol, so they check parameters and results without UI.

## Testing

- Fixtures from SatimageOSAX for every non-dialog command and parameter, in `Fixtures/FileAdditions`, generated by a `generate.py` as in `FilesAndFolders`. Cases build their folder trees inside `$TMP` with `mkdir`, `filenew` and `writetext`, and set modification dates where `after`/`before` matter (with `do shell script "touch -t …"`, since the recorder skips only `syso`/`ascr`/`misc` events and doesn't need to see it).
- Fixture tooling: may need `URL information` records and results that contain `$TMP` in URL form (`file:///private/tmp/…`, percent-encoded), which `replacingText` already handles for `furl` descriptors but not yet for URL text.
- Unit tests for every command, including the dialogs through the fake panel.
- `Scripts/e2e/file-additions.applescript` through `Scripts/parity.sh`, and a `*-fixes` script for deviations.
- Dialogs get a manual checklist script, `Scripts/manual/dialogs.applescript`, that opens each dialog in both apps so the look and results can be compared by hand (or automatically, if open question 2 is answered yes).

## Order of work

1. Copy the suite into the SDEF, with placeholder handlers.
2. Record SatimageOSAX fixtures for the non-dialog commands; settle the behaviors above.
3. `absoluteURL`, `relativeURL`, `URL info for`, `alias description for`.
4. `list files`, `glob`.
5. `backup`.
6. Dialog support in the app (activation, the protocol, `key` folders), then the six `navchoose`/`navnew` commands and `navask save`.
7. Anything Satimage gets wrong: implement from the documentation, record from MTC_OSAX into `FileAdditionsFixes`, and list it in this plan.
8. End-to-end, parity and manual dialog scripts.

## Done when

- [x] All 14 commands and the `URL information` record implemented; SDEF consistency tests pass.
- [x] SatimageOSAX fixtures for every non-dialog command and parameter replay without differences; every deviation listed here with MTC_OSAX fixtures.
- [x] Unit tests for every command, including error cases and the dialogs through a fake panel.
- [x] Every dialog checked by hand in MTC_OSAX against the dictionary (`Scripts/manual/dialogs.sh`); SatimageOSAX's never worked.
- [x] `Scripts/e2e/file-additions.applescript` passes, and `Scripts/parity.sh` shows no differences for shared behavior.

## Decisions

Made 2026-09-27:

1. All seven dialogs are implemented.
2. Dialogs are checked by hand against SatimageOSAX (no UI scripting); unit tests use a fake panel.
3. `backup` matches Satimage, including deleting destination items if Satimage's sync does. (It turned out not to delete anything.)
4. A dialog's `key` remembers the folder containing the chosen item (also for folder dialogs), so the next dialog with that key opens where the user was browsing.

## Findings during implementation

Recorded from SatimageOSAX in `Fixtures/FileAdditions` (255 cases, generated by `generate.py` there), all replaying without differences:

- **Default results.** `list files` and `glob` return FSRefs (`fsrf`), which Swift can't make; the `CFileReferences` C target makes them with the (deprecated, still working) FSRef API, and aliases are made by coercing one. Fixtures store FSRefs as paths, like aliases. `absoluteURL` returns a URL as text.
- **`as`.** `alias`; `file` and `«class furl»` give file URLs, and so does any other type (`integer` included); `Unicode text`, `text` and `string` give URLs as text; `unix path` the POSIX path; `path` the percent-encoded path. `unix path` and `path` arrive as property specifiers of the suite's `URL information` record. Folders end with `/`.
- **`list files`.** File system order (not sorted), or by modification date when `after` or `before` is given (`glob` too). Recursively, only files and packages are listed; without, folders too. Symbolic links are skipped. Extensions and `starting with` are case-sensitive; `of extension` takes no dot. `conforming to` with `not conforming to` is error -50. A missing folder lists nothing; a file lists itself.
- **`glob`.** `*`, `?`, `[…]`, `{a,b}` and `~`; folders included; no matches is an empty list; `from` is the base for relative patterns. Without `from`, a relative pattern is relative to `/` (a launched app's working folder; MTC_OSAX uses `/` explicitly, so tests don't depend on how it was started).
- **`URL info for`.** For local items, Standard Additions' `info for` record (whose fields differ for files, folders and packages) followed by `scheme`, `unix path` and `path`; symbolic links are followed for the information but not the paths. Dates and the default application depend on the machine, so fixtures accept any value there (`mark_volatile.py`, and `{"type": "any"}` in replays). For other URLs, only the URL's parts; a missing file is -43, text that isn't a URL -1700.
- **`absoluteURL` / `relativeURL`.** Standard URL resolution, with `.` and `..` removed. Path strings aren't checked on disk, so only a trailing `/` (or an alias) marks a folder; the same holds for `alias description for`, which also returns the path of an item that isn't an alias, even a missing one. Empty text is error 111.
- **`backup`.** Never deletes; skips invisible items; copies packages whole; updates only when the source is newer. Level 0 lists a missing folder once; level 2 lists each file. The report has "Items to update"/"Items updated", "Items to create"/"Items created" and "Errors" sections (a header, `return`, then tab-indented paths each ending with `linefeed`); "OK" when there's nothing to report, and always for level 1. A missing destination is created; a missing or non-folder source is -50.
- My first recording replaced every `@` in the case scripts with the case's folder, mangling `user:pw@host` URLs and making Satimage look broken; the generator now only replaces `@/` and `"@"`.

## Fixing Satimage's bugs

Recorded from MTC_OSAX in `Fixtures/FileAdditionsFixes`, with unit tests and `Scripts/e2e/file-additions-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| Dialogs | Every `navchoose` command, `navnew folder` and `navask save` replied -1708 (never worked) | Implemented from the dictionary with AppKit panels; unit tests through a fake, checked by hand |
| `show packages false` | (Dialogs never worked) | Documented as "not displayed"; open panels can't hide items, so packages are greyed out and can't be opened or chosen |
| `glob "…/.*"` | Also returned `.` and `..` (the folder and its parent) | Only real items |
| `glob … not conforming to "public.folder"` | Kept folders | Excludes them |
| HFS paths | `list files`: error -1700 | Accepted wherever an item is, as decided for Files and folders (unit tests, since an HFS path in a fixture names the folder it was recorded in) |
| `~` | The sandbox container of SatimageOSAX | The home folder (unit and e2e tests) |
| `backup` reports | A destination folder that couldn't be made was left out of the report with everything under it (`backup-mixed-errors`, `backup-file-where-folder`, now in `FileAdditionsFixes`); a source folder that couldn't be read counted as empty; a new package whose copy failed part way stayed partial, and newer, so later runs took it as done; a destination that couldn't be made gave "OK" | Each is an error in the report (the folder with its code), a new package is copied under a temporary name and renamed in, and a destination that can't be made is the command's error |
