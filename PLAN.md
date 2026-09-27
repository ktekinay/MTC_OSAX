# MTC_OSAX Plan

Goal: a native (Apple Silicon) scriptable app that replaces `SatimageOSAX.app` (`com.latenightsw.SatimageHost`, Intel-only) so existing scripts only need their `use application "SatimageOSAX"` line changed.

Source dictionary: [SatImageOSAX SDEF/dictionary.sdef](SatImageOSAX%20SDEF/dictionary.sdef)

## Sections

Command counts include hidden commands. The XML suites share priority 5; Satimage Pool Additions is included with them because it manages the pools that `XMLOpen` and `XMLListDocuments` use.

| Priority | Suite | Cmds | What it covers |
|---|---|---|---|
| 1 | Satimage Text Additions | 25 | `find text`, `change` (regex find/replace), `splittext`, `filter text`, `readtext`/`writetext`, upper/lower/titlecase, `format`, `atof`/`atoi`, entity encode/resolve, `escapeURL`/`unescapeURL`, Unicode normalize/transform, `hash`, `join`, `printf`, `strftime`/`strptime` |
| 2 | Satimage File Additions | 14 | `navchoose …` / `navask save` dialogs, `alias description for`, `URL info for`, `absoluteURL`/`relativeURL`, `list files`, `glob`, `backup` (folder sync) |
| 3 | Files and folders suite | 10 | `filenew`, `mkdir`, `filecopy`, `filemove`, `fileremove`, `filegetname`, `filerename`, `mkstemp`, `mkdtemp`, `chmod` |
| 3 | Symlink suite | 3 | `create symlink`, `testsymlink`, `readlink` |
| 4 | Mathematical Functions | 27 | `abs`, trig/hyperbolic, `exp`, `ln`, `log10`, `sqrt`, `sqr`, `ceil`/`floor`/`trunc`, `erf`, `gamma`, `hypot`, … |
| 5 | Satimage XML DOM | 39 | `XMLOpen`/`XMLClose`, node navigation, attributes, text, namespaces, `XMLFind`, `XMLDisplayXML`, … |
| 5 | XML XPath, XSLT | 15 | `XMLXPath`, contexts, `XMLXPointer`, `XMLTransform` (XSLT), indexes/lookup |
| 5 | XML Documents | 18 | `XMLSave`, encoding, catalogs, XInclude, canonicalization, doc IDs |
| 5 | XML Validation | 11 | DTD / XML Schema / RelaxNG validation, ID lookup, name validity |
| 5 | Satimage Pool Additions | 3 | Document pools shared by the XML and Plist suites |

## May Do Later

| Suite | Cmds | What it covers |
|---|---|---|
| Applescript types (hidden, legacy text) | 6 | `find text obsolete` (`SATIFIND`) and `replace obsolete` (`SATIRPLC`), which are superseded by `find text` (`SATIFINd`) and `change` (`SATIRPLl`); `extract string` (same as `text i thru j of s`); undocumented `findxmlstag`; `gziptext`/`gunziptext` (no public equivalent). `convert to Mac` is commented out in the SDEF. |
| Resource Suite | 3 | Read classic resource forks (`load resource`, `list resources`, `get resource name`) |
| Arrays | 33 | `array of real` / `matrix` types: create, extract/change/insert, arithmetic on lists, `statlist`, `histogram`, `evalformula`, polynomials and fitting, binary read/write |
| Array and List Utilities | 7 | `sortlist`, `masklist`, `topological sort`, `suppress item`, `exclude items`, `keep items`, `special concat` |
| Linear algebra | 9 | `transpose`, `multmatrix`, `invertmatrix`, `solve linear system`, eigenvalues, LU decomposition, determinant |
| FFT and convolution | 6 | `fft1d`, `fft2d`, `filterarray`, `convolve`, `correlate`, `interpolate` |
| Image files | 4 | Image bounds, image → gray-level matrix, matrix → gray image, particle detection |
| 3D array handling | 9 | `open3D`/`close3D` etc., `isosurface`, `streamline` |
| FITS | 10 | Reading FITS astronomy data files |
| XNF Additions | 14 | XNF bundle datasets, arrays, scales |
| Satimage PropertyList Additions | 29 | `PlistOpen`/`PlistNew`/`PlistSave`, get/set children, `PlistToJSON`/`PlistFromJSON`, … |
| Unnamed hidden suite (misc/obsolete) | 21 | Obsolete XML variants, `XMLCookie`, URI scheme callbacks, `PlistCopy`, `XMLGetArray`/`XMLSetArray`, … |

## Notes

- For compiled scripts and existing source to keep working, every implemented command, parameter, record type and enumeration must keep **the same name and four-character codes** as the Satimage SDEF.
- The running `SatimageOSAX.app` can serve as the reference implementation: run the same script against both apps and compare results.
- The XML, Plist, and 3D/FITS suites keep state between calls (open documents, references), so they need an object store in the app, not just stateless handlers.
