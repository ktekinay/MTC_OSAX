# MTC_OSAX Plan

Goal: a native (Apple Silicon) scriptable app that replaces `SatimageOSAX.app` (`com.latenightsw.SatimageHost`, Intel-only) so existing scripts only need their `use application "SatimageOSAX"` line changed.

Source dictionary: [SatImageOSAX SDEF/dictionary.sdef](SatImageOSAX%20SDEF/dictionary.sdef)

## Sections

Command counts include hidden commands. Suites sharing a priority are done together.

| Priority | Suite | Cmds | What it covers |
|---|---|---|---|
| 1 ✓ | Satimage Text Additions ([done](Implemented/PLAN-TextAdditions.md)) | 25 | `find text`, `change` (regex find/replace), `splittext`, `filter text`, `readtext`/`writetext`, upper/lower/titlecase, `format`, `atof`/`atoi`, entity encode/resolve, `escapeURL`/`unescapeURL`, Unicode normalize/transform, `hash`, `join`, `printf`, `strftime`/`strptime` |
| 2 ✓ | Files and folders suite ([done](Implemented/PLAN-FilesAndFolders.md)) | 10 | `filenew`, `mkdir`, `filecopy`, `filemove`, `fileremove`, `filegetname`, `filerename`, `mkstemp`, `mkdtemp`, `chmod` |
| 2 ✓ | Symlink suite | 3 | `create symlink`, `testsymlink`, `readlink` |
| 3 ✓ | Satimage File Additions ([done](Implemented/PLAN-FileAdditions.md)) | 14 | `navchoose …` / `navask save` dialogs, `alias description for`, `URL info for`, `absoluteURL`/`relativeURL`, `list files`, `glob`, `backup` (folder sync) |
| 4 ✓ | Mathematical Functions ([done](Implemented/PLAN-MathAndLists.md)) | 27 | `abs`, trig/hyperbolic, `exp`, `ln`, `log10`, `sqrt`, `sqr`, `ceil`/`floor`/`trunc`, `erf`, `gamma`, `hypot`, … |
| 4 ✓ | Array and List Utilities | 7 | `sortlist`, `masklist`, `topological sort`, `suppress item`, `exclude items`, `keep items`, `special concat` |
| 5 ✓ | Satimage PropertyList Additions ([done](Implemented/PLAN-PropertyLists.md)) | 29 | `PlistOpen`/`PlistNew`/`PlistSave`, get/set children, `PlistToJSON`/`PlistFromJSON`, … |
| 5 ✓ | Satimage Pool Additions | 3 | Document pools shared by the Plist and XML suites |
| 6 | Satimage XML DOM | 39 | `XMLOpen`/`XMLClose`, node navigation, attributes, text, namespaces, `XMLFind`, `XMLDisplayXML`, … |
| 6 | XML XPath, XSLT | 15 | `XMLXPath`, contexts, `XMLXPointer`, `XMLTransform` (XSLT), indexes/lookup |
| 6 | XML Documents | 18 | `XMLSave`, encoding, catalogs, XInclude, canonicalization, doc IDs |
| 6 | XML Validation | 11 | DTD / XML Schema / RelaxNG validation, ID lookup, name validity |

### Why this order

- **Text first**, as agreed. It also builds the regex engine (Onigmo) and the file-text helpers (encodings, BOM) that later suites reuse.
- **Files and folders + Symlink before File Additions.** They're the basic file operations (copy, move, rename, links). File Additions' `list files`, `glob` and `backup` build on them. File Additions also has the `navchoose` dialogs, which are the hardest part: MTC_OSAX has no UI, so it has to show a dialog while staying faceless.
- **Math and Array/List Utilities together.** Both are small and self-contained, and both accept and return the Arrays suite's `array of real`; that type is implemented with them, while the rest of Arrays stays in "May Do Later".
- **PropertyList (with Pool) before XML.** Both come from the same original module (XMLLib.osax) and need the same machinery: open documents, references that stay valid between commands, pools and document IDs. PropertyList builds that on a suite of 29 commands instead of 86. Your scripts use PropertyList in 2 places and XML in 1. It also completes `filter text … into` a plist reference, deferred from Text.
- **XML last.** It's the largest group and reuses everything above.

## MTC_OSAX extensions

Additions that Satimage never had, planned separately:

- [PCRE as an alternative regex engine](PLAN-PCRE.md), selected with `syntax "PCRE"`. To be done on its own branch.
- **YAML for property lists** (noted 2026-09-28): explore commands like `PlistToYAML`/`PlistFromYAML`, alongside Satimage's existing `PlistToJSON`/`PlistFromJSON` (which cover JSON), once the PropertyList suite (priority 5) is done.
- **Settings from AppleScript** (noted 2026-09-28): explore commands in the hidden "MTC Diagnostics" suite to read and change MTC_OSAX's preferences (`IdleTimeoutSeconds`, `DollarReferences`), instead of `do shell script "defaults …"`: `mtc_get setting`, `mtc_set setting … to …` (with `missing value` to go back to the default), and something like `mtc_list settings` returning each setting that can be changed with its current value (and perhaps its default and a description). Commands rather than application properties, to keep Cocoa Scripting's object model out of the app.

## May Do Later

| Suite | Cmds | What it covers |
|---|---|---|
| Applescript types (hidden, legacy text) | 6 | `find text obsolete` (`SATIFIND`) and `replace obsolete` (`SATIRPLC`), which are superseded by `find text` (`SATIFINd`) and `change` (`SATIRPLl`); `extract string` (same as `text i thru j of s`); undocumented `findxmlstag`; `gziptext`/`gunziptext` (no public equivalent). `convert to Mac` is commented out in the SDEF. |
| Resource Suite | 3 | Read classic resource forks (`load resource`, `list resources`, `get resource name`) |
| Arrays | 33 | `array of real` / `matrix` types: create, extract/change/insert, arithmetic on lists, `statlist`, `histogram`, `evalformula`, polynomials and fitting, binary read/write. (The `array of real` type, `createarray` and `randomarray` come with priority 4.) |
| Linear algebra | 9 | `transpose`, `multmatrix`, `invertmatrix`, `solve linear system`, eigenvalues, LU decomposition, determinant |
| FFT and convolution | 6 | `fft1d`, `fft2d`, `filterarray`, `convolve`, `correlate`, `interpolate` |
| Image files | 4 | Image bounds, image → gray-level matrix, matrix → gray image, particle detection |
| 3D array handling | 9 | `open3D`/`close3D` etc., `isosurface`, `streamline` |
| FITS | 10 | Reading FITS astronomy data files |
| XNF Additions | 14 | XNF bundle datasets, arrays, scales |
| Unnamed hidden suite (misc/obsolete) | 21 | Obsolete XML variants, `XMLCookie`, URI scheme callbacks, `PlistCopy`, `XMLGetArray`/`XMLSetArray`, … |

## Notes

- For compiled scripts and existing source to keep working, every implemented command, parameter, record type and enumeration must keep **the same name and four-character codes** as the Satimage SDEF.
- The running `SatimageOSAX.app` can serve as the reference implementation: run the same script against both apps and compare results.
- The XML, Plist, and 3D/FITS suites keep state between calls (open documents, references), so they need an object store in the app, not just stateless handlers.
