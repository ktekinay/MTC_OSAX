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
| 6 ✓ | Satimage XML DOM ([done](Implemented/PLAN-XML.md)) | 39 | `XMLOpen`/`XMLClose`, node navigation, attributes, text, namespaces, `XMLFind`, `XMLDisplayXML`, … |
| 6 ✓ | XML XPath, XSLT | 15 | `XMLXPath`, contexts, `XMLXPointer`, `XMLTransform` (XSLT), indexes/lookup |
| 6 ✓ | XML Documents | 18 | `XMLSave`, encoding, catalogs, XInclude, canonicalization, doc IDs |
| 6 ✓ | XML Validation | 11 | DTD / XML Schema / RelaxNG validation, ID lookup, name validity |
| 7 ✓ | Arrays ([done](Implemented/PLAN-Arrays.md)) | 33 | Matrices, reading and changing arrays, arithmetic on lists, arrays, matrices and polynomials, `statlist`, `histogram`, `evalformula`, polynomials and fitting, binary files (`createarray`, `randomarray` and `array of real` came with priority 4; the 4 hidden commands and the obsolete `extractitem` are left out) |

### Why this order

- **Text first**, as agreed. It also builds the regex engine (Onigmo) and the file-text helpers (encodings, BOM) that later suites reuse.
- **Files and folders + Symlink before File Additions.** They're the basic file operations (copy, move, rename, links). File Additions' `list files`, `glob` and `backup` build on them. File Additions also has the `navchoose` dialogs, which are the hardest part: MTC_OSAX has no UI, so it has to show a dialog while staying faceless.
- **Math and Array/List Utilities together.** Both are small and self-contained, and both accept and return the Arrays suite's `array of real`; that type is implemented with them, while the rest of Arrays stays in "May Do Later".
- **PropertyList (with Pool) before XML.** Both come from the same original module (XMLLib.osax) and need the same machinery: open documents, references that stay valid between commands, pools and document IDs. PropertyList builds that on a suite of 29 commands instead of 86. Your scripts use PropertyList in 2 places and XML in 1. It also completes `filter text … into` a plist reference, deferred from Text.
- **XML last.** It's the largest group and reuses everything above.

## MTC_OSAX extensions

Additions that Satimage never had, planned separately:

- ✓ [PCRE as an alternative regex engine](Implemented/PLAN-PCRE.md), selected with `syntax "PCRE"` or the `RegexSyntax` setting.
- ✓ **YAML and TOML for property lists** ([done](Implemented/PLAN-YAMLTOML.md)): `PlistToYAML`, `PlistFromYAML`, `PlistToTOML` and `PlistFromTOML`, and files for these and Satimage's JSON pair.
- ✓ **Settings from AppleScript** ([done](Implemented/PLAN-Settings.md)): `mtc_get`, `mtc_set` and `mtc_reset` in their own visible "MTC_OSAX Settings" suite, for `idle_timeout`, `dollar_references` and `regex_syntax`.
- ✓ **A faster `sortlist`** ([done](Implemented/PLAN-FastSort.md)): radix and merge sorts of our own and lists read without a descriptor for each item (2.5 to 16 times as fast), with text compared by full case folding however its accents are typed.
- ✓ **A `sortlist` audit** ([done](Implemented/PLAN-SortlistAudit.md)): crashes from many `with respect to` criteria, `ascending` read only as far as it's used, faster dates and numbers as text.

## May Do Later

| Suite | Cmds | What it covers |
|---|---|---|
| Applescript types (hidden, legacy text) | 6 | `find text obsolete` (`SATIFIND`) and `replace obsolete` (`SATIRPLC`), which are superseded by `find text` (`SATIFINd`) and `change` (`SATIRPLl`); `extract string` (same as `text i thru j of s`); undocumented `findxmlstag`; `gziptext`/`gunziptext` (no public equivalent). `convert to Mac` is commented out in the SDEF. |
| Resource Suite | 3 | Read classic resource forks (`load resource`, `list resources`, `get resource name`) |
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
