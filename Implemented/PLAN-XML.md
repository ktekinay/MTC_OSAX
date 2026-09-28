# XML Plan

Branches, merged one after another (decision 1):

1. `feature/xml`: DOM and Documents (which the KML script needs).
2. `feature/xml_xpath`: XPath, XSLT and indexes.
3. `feature/xml_validation`: Validation.

This plan stays at the top level until the last merge.

Goal: implement Satimage's four XML suites, **Satimage XML DOM**, **XML XPath, XSLT**, **XML Documents** and **XML Validation** (priority 6 in [PLAN.md](PLAN.md)), matching SatimageOSAX where it works and following the dictionary's documentation where it doesn't.

## Scope

All four suites use the event class `XML ` and work on documents through **XMLRefs** (`XMLR`): opaque references to a document or a node, valid until the document is closed, like the PropertyList suite's CFRefs. Documents live in the same `DocumentStore` and pools. SatimageOSAX built them on libxml2 and libxslt ("Uses the Libxml2 open source project"), which macOS includes (libxml2 2.9.13 and libxslt 1.1.35 with EXSLT in the SDK, with validation, XML Schema, RelaxNG, Schematron, XInclude, canonicalization, catalogs and XPointer).

### Satimage XML DOM (39 commands)

| Group | Commands |
|---|---|
| Documents | `XMLOpen` (a file, a URL, or `from string`; `keep blanks`, `load external DTD`, `substitute entities`, `validate`, `html4`, `xmlscript`, `noCDATA`, `verbose`, `failure level`, `in pool`, `POST`, `query`, `header`, `bypassing namespace`, `encoding`), `XMLClose` |
| Navigating | `XMLRoot`, `XMLParent`, `XMLChild`/`XMLElement` (`index`; `all nodes` counts text and comments), `XMLCount`/`XMLCountElement`, `XMLNextSibling`/`XMLNextElement`, `XMLPrevSibling`/`XMLPrevElement`, `XMLExists` |
| Reading | `XMLTagName`, `XMLGetAttribute`, `XMLNodeInfo` (record `NodeInfo`), `XMLDisplayXML` (`formatting`, `xml declaration`, `nsclean`, `html4`, `encoding`), `XMLGetText` |
| Changing | `XMLSetAttribute` (`suppressing`), `XMLRemoveAttribute`, `XMLRemove`, `XMLRemoveChildren`, `XMLNewChild` (`at`, `keep blanks`, `nsclean`), `XMLNewSibling` (`after`/`before`), `XMLSetXML`, `XMLSetText`, `XMLAppendText` |
| Namespaces | `XMLGetNameSpace`, `XMLGetNameSpaces`, `XMLGetNameSpaceFromPrefix`, `XMLAddNamespace` (record `namespace`) |
| Searching | `XMLFind` (`name`, `key`/`value` attribute, `all occurrences`), `XMLFindText`, `XMLRegexp` (`conforming`) |
| URLs | `XMLBase`, `XMLSetBase`, `XMLAbsoluteURL`, `XMLRelativeURL` |
| Errors | `XMLError` (the last parsing or validation errors) |

### XML XPath, XSLT (15 commands, 6 hidden)

`XMLXPath` (`with`, `namespace`, `xpath variables`), `XMLSetContext`/`XMLGetContext` (record `XPathRef`), `XMLGetNodePath`, `XMLXPointer`, `XMLTransform` (XSLT: `with`, `xsl params`, `xsl string params`, `in`, `as`, `in pool`), and indexes: `XMLNewIndex` (`match`, `use`, like XSLT keys), `XMLLookup`, `XMLEntries`. Hidden: `XMLEscapeXPointer`, `XMLGetXPointer`, `XMLCompile`, `XMLIndexDocument`, `XMLStrings`, `XMLLocalize`.

### XML Documents (18 commands)

`XMLURL`/`XMLSetURL`, `XMLDocument`, `XMLCatalog`, `XMLCloneDocument`, `XMLXInclude`, `XMLGetEncoding`/`XMLSetEncoding`, `XMLSetIndentString`, `XMLSave` (`in`, `formatting`, `html4`, `xml declaration`, `encoding`), `XMLErrorLevel`, `XMLExtendedChar`, `XMLListDocuments`, `XMLSetDocID`/`XMLGetDocByID`, `XMLc14n` (canonicalization: `comments`, `nodelist`, `exclusive`, `inclusive prefixes`, `digest`), `XMLSetExtras`/`XMLGetExtras`.

### XML Validation (11 commands, 3 hidden)

`XMLValidate` (DTD: `against`, `verbose`, `failure level`), `XMLSchema`, `XMLRelaxNG`, `XMLCheckDTD`, `XMLGetByID`/`XMLGetxmlID`, `XMLValidName`/`XMLValidNCName`. Hidden: `XMLDu`, `XMLGetID`, `XMLFromID`.

### Your scripts

One script, "KML To Excel", uses `XMLOpen`, `XMLChild … index`, `XMLCount`, `XMLFind … name`, `XMLGetText`, `XMLNextSibling` and `XMLClose` to read placemarks from a KML file. It gets fixtures first.

## Behavior to establish from fixtures

- **Parsing.** Every `XMLOpen` option; blank text nodes (`keep blanks`), entities, CDATA, DTDs; HTML (`html4`); `encoding`; invalid documents and `failure level` (which errors stop parsing); what `XMLError` reports and how `verbose` changes it.
- **Navigation.** What counts as a child with and without `all nodes` (text, comments, processing instructions, CDATA); 1-based indices and out-of-range errors; the end of siblings.
- **Output.** `XMLDisplayXML` and `XMLSave` formatting (indentation, `XMLSetIndentString`), the XML declaration, encodings, `nsclean`, empty elements, entities and character references (`XMLExtendedChar`).
- **Text.** `XMLGetText` of elements with mixed content, whitespace, entities; `XMLSetText` escaping.
- **Records.** `NodeInfo` for each node kind, `namespace` records, `XPathRef`.
- **XPath.** Result types (node sets as XMLRefs, numbers, strings, booleans), namespaces and variables, contexts, errors in expressions.
- **XSLT.** Stylesheets from files, strings and XMLRefs; parameters (XPath vs string); output as a new document or text (`as`); `xsl:output` settings; EXSLT functions.
- **Indexes.** How `XMLNewIndex`/`XMLLookup`/`XMLEntries` behave, and the hidden `XMLStrings`/`XMLLocalize`.
- **Validation.** Results and messages for DTD, XML Schema and RelaxNG; IDs.
- **Canonicalization.** Each mode, and `digest` (which hash, and in what form).
- **Settings.** `XMLErrorLevel`, `XMLExtendedChar`, `XMLSetExtras`/`XMLGetExtras`, `XMLCatalog`: app-wide or per document.
- **Versions.** Output differences between SatimageOSAX's libxml2 (probably older) and macOS's 2.9.13, such as formatting and error messages.

## Architecture

- **Module `XML`**, registered in `CommandCatalog`, using macOS's libxml2 and libxslt from the SDK (decision 3) through a small C module map (`CLibXML`), and the `DocumentStore` and pools from the PropertyList suite, generalized to hold both kinds of document.
- **Documents** stay as libxml2 trees (`xmlDocPtr`); XMLRefs name a document and a node. Nodes are identified through a per-document table, so a removed node's references give an error instead of pointing at freed memory (the PropertyList suite's approach).
- **Errors** from libxml2's structured error callback, collected per command for `XMLError` and the `failure level` rules.
- **Network.** http and https URLs work wherever a document or resource can come from (decision 2): `XMLOpen` fetches through `URLSession` (with `POST`, `query` and `header`), and libxml2 and libxslt load the others through its input callbacks. Fixtures use a local test server started for the recording.
- **Threading.** libxml2 is used only on the main thread, where all commands run.

## Testing

- Fixtures from SatimageOSAX in `Fixtures/XML` (with an `Input` folder of documents, stylesheets, DTDs and schemas), generated by `generate.py`, the KML script's calls first. XMLRef mapping as for CFRefs.
- If macOS's libxml2 formats or reports errors differently from SatimageOSAX's, differences are sorted into (a) version differences in text that scripts shouldn't depend on (for example error message wording), documented and matched loosely, and (b) behavior, matched exactly.
- Unit tests for the node table, conversions, each command and error handling.
- `Scripts/e2e/xml.applescript` through `Scripts/parity.sh` (including the KML script's pattern), and a `*-fixes` script.

## Order of work

Stage 1 (`feature/xml`):

1. Copy the four suites into the SDEF, with placeholder handlers; the `CLibXML` module and linking.
2. Generalize the `DocumentStore` for XML documents.
3. Record SatimageOSAX fixtures for the DOM and Documents suites.
4. DOM: opening (with URLs), navigating, reading (the KML script's commands first), then changing, namespaces, searching, URLs, errors.
5. Documents: saving, encodings, cloning, XInclude, canonicalization, settings.
6. Fixes, end-to-end and parity scripts for this stage. Merge.

Stage 2 (`feature/xml_xpath`): fixtures, then XPath and contexts, XPointer, XSLT, indexes and the hidden commands; fixes and e2e. Merge.

Stage 3 (`feature/xml_validation`): fixtures, then DTD, XML Schema and RelaxNG validation, IDs and names; fixes and e2e. Move this plan to `Implemented/` and merge.

Anything Satimage gets wrong, in any stage: implement from the documentation, record from MTC_OSAX into `XMLFixes`, and list it in this plan.

## Done when

- [x] Stage 1: DOM and Documents (57 commands) implemented, with fixtures, unit tests and e2e; merged.
- [x] Stage 2: XPath, XSLT (15 commands) implemented, with fixtures, unit tests and e2e; merged.
- [x] Stage 3: Validation (11 commands) implemented, with fixtures, unit tests and e2e.
- [x] All 83 commands implemented; SDEF consistency tests pass.
- [x] SatimageOSAX fixtures for every command and parameter replay without differences (or with documented version differences); every deviation listed here with MTC_OSAX fixtures.
- [x] Unit tests for every command, including error cases.
- [x] `Scripts/e2e/xml.applescript`, `xml-xpath.applescript` and `xml-validation.applescript` pass, and `Scripts/parity.sh` shows no differences for shared behavior.

## Decisions

Made 2026-09-28:

1. Three branches and merges: DOM and Documents, then XPath and XSLT, then Validation.
2. http and https URLs are supported wherever the dictionary allows them.
3. macOS's libxml2 and libxslt; vendoring a specific version only if fixtures show differences that matter.

## Findings: stage 1 (DOM and Documents)

Recorded from SatimageOSAX in `Fixtures/XML` (225 cases, generated by `generate.py`, with input files from `make_inputs.py`), all replaying without differences:

- **Recording.** The first XML command after SatimageOSAX launches is sent three times while it loads its XML library, so recordings start with a throwaway `XMLOpen`. `XMLAppendText` to an element with mixed content crashed SatimageOSAX (it relaunched).
- **References.** XMLRefs are a document number and a node; replays map them like CFRefs. `XMLClose` of any node closes its document. A removed node's references, and those of anything in it, give -1728: libxml2's deregistration callback (per thread, set for the current thread as well as by default) forgets freed nodes.
- **Errors** are libxml2's own numbers (76 tag mismatch, 534 validation, 1549 can't load, 1450 bad regular expression, 1524 can't write); `XMLError` lists each problem as `show "<file URL>" selection <line>:` (or `line <n>`), the message and a blank line. `failure level` (default `XMLErrorLevel`, 2) is the lowest libxml2 level that fails parsing.
- **Navigation.** `all nodes` is on by default (text, comments, processing instructions count); indices are 1-based (-1719 out of range, -1700 for a list, -1701 missing). `XMLFind` looks only at direct children, by local name and/or an attribute `key` with `value` (-1701 without both, -50 on a document); lists answer with lists.
- **Text.** `XMLGetText` is libxml2's text content (entities resolved, comments left out; a document's is its elements'). `XMLFindText` and `XMLRegexp` search text, CDATA and comment nodes; `XMLRegexp` uses XML Schema regular expressions, which match the whole text.
- **`XMLNodeInfo` of a file** reads only its start: the document type declaration or else the root element, with the line where it starts, `hdtd`, `stnd` and the declared encoding (`enco`); files malformed further on work. -43 for a missing file.
- **`XMLNodeInfo`**: `kind` (as `TEXT`), name (`pnam`), attributes as a flat list, namespace record, `cpar` (the line), and for documents `hdtd`, DTD IDs, `stnd` (HTML) and `imod` (changed since opened).
- **Output.** Formatting indents with `XMLSetIndentString` (a tab at launch); documents without an encoding are written as UTF-8 with it in the declaration; elements get the namespace declarations they need (`nsclean`); an HTML document written as HTML uses libxml2's HTML writer (named entities), any other document HTML syntax in UTF-8. `XMLSave` saves the whole document.
- **Settings** are app-wide: `XMLErrorLevel` (2), `XMLExtendedChar` (on: XML 1.1's control characters like `&#1;` are accepted; libxml2 rejects them, so they're swapped for private characters while parsing), `XMLSetIndentString`.
- **Documents.** `XMLDocument` returns a list when a file is open more than once in the pool; `XMLCatalog` finds nothing without system catalogs (-2763); `XMLc14n` digests are base64 SHA1 or MD5.

## Fixing Satimage's bugs: stage 1

Recorded from MTC_OSAX in `Fixtures/XMLFixes` (which shares `XML/Input`) and `Fixtures/XMLNetwork`, with unit tests and `Scripts/e2e/xml-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `XMLExists` of a removed node or closed document | Error -1728 | False |
| `XMLAppendText` to an element with mixed content | Crashed | Appends to its last text |
| `XMLSetXML` of a text node | Left a document `XMLDisplayXML` returned nothing for | Replaces the text node |
| `XMLError` after a command without problems | Stale text from an earlier command | "" |
| `XMLSave … in` a POSIX path | Error 1535 | Saves |
| `XMLOpen` of an http or https URL | Error 4 for every URL (even public ones) | Fetches it (decision 2): GET with `query`, POST with `query` as a form body, extra `header`s; a failure status or no connection is 1549. Fixtures in `XMLNetwork`, replayed against a test server the tests start (`NetworkFixtureServer`, the Swift version of `serve.py`) |

**libxml2 version differences** (not bugs; recorded from MTC_OSAX in `XMLFixes`): macOS's libxml2 2.9.13 writes no line break after `<br>` in HTML and no blank lines for XInclude markers, where SatimageOSAX's older one did. The content is the same.

`XMLGetID`/`XMLFromID` numbers are a counter in the app, so unit tests cover them rather than fixtures.

## Findings: stage 2 (XPath, XSLT)

Recorded from SatimageOSAX in `Fixtures/XML` (109 cases, generated by `generate_xpath.py` into `cases-xpath.json`), all replaying without differences:

- **XPath results.** Node sets are lists of XMLRefs (attributes too: `XMLNodeInfo` gives `ATTRIBUTE_NODE`, the name and the owner's line; `XMLGetText` the value); whole numbers are integers, others reals; strings and booleans as they are. A list of nodes gives a list of results.
- **XPath errors.** A syntax error is libxml2's number (1207); anything that fails when evaluated (an undeclared prefix, an unknown function or variable) is 3. An odd `xpath variables` list is -1700; no `with` is -1701.
- **Contexts** are per document. `XMLXPath`'s and `XMLNewIndex`'s `namespace` and `xpath variables` are kept in the document's context, as `XMLSetContext` would keep them (`XMLXPointer`'s aren't); `XMLGetContext` gives `{namespace:{…}, xpath variables:{{name, value}, …}}`. A `missing value` variable is removed.
- **Extension functions**, through a declared prefix: XPath 2.0's compare, upper-case, lower-case, ends-with and base-uri; EXSLT math, sets, strings (not replace: see below) and dates; crypto md5, sha1, sha224 and sha256 as base64; Satimage's parent-uri (up to the last `/`) and relative-uri. **AppleScript handlers** as functions (`http://satimage.fr/software/xpath-functions-applescript`) aren't supported: an app can't reach the handlers of the script that sent the event, and SatimageOSAX's app gave error -3 too (MTC_OSAX: 3, an unknown function).
- **`XMLGetNodePath`** writes its own paths, not libxml2's: `xpointer(/library[1]/book[2]/year[1])`, `*[n]` for an element in a namespace, `text()[n]`, `@name`, and `comment()` or `processing-instruction('name')` with `[n]` only when there are several; `xpointer(/)` for the document. `XMLGetXPointer` is the document's URL, `#` and that path (-50 for a document).
- **`XMLXPointer`** evaluates with libxml2's XPointer: IDs (from the DTD, without `validate`), `xpointer(…)`, a missing ID gives `{}`, a syntax error 1216. A link to another file opens it into the pool (`in pool`, `from`'s, or the current one) unless it's open there, or error 11 without `read permission`. `XMLEscapeXPointer` escapes `(`, `)` and `^` with `^`.
- **`XMLTransform`**: the stylesheet can be a file, a path, an XMLRef (compiled once with `XMLCompile`), or XSLT text; without `with`, the `xml-stylesheet` processing instruction (-1701 if none). An invalid stylesheet is 3, one that can't be read 4. `xsl params` are XPath expressions, `xsl string params` quoted text (lists or records). The result is a new document without a URL (`XMLURL` -2763), `as string` (the text for `method="text"`, otherwise as `XMLDisplayXML` writes it), `as CFRef` a property list, or written `in` a file as libxslt writes it (the declaration without an encoding). A node is transformed by applying the templates to it (so the root template doesn't run); MTC_OSAX does this with a root template, added to a copy of the stylesheet, that applies the templates to the node's path. EXSLT works.
- **Indexes.** `XMLLookup` gives a list (`{}` for no entry); `XMLEntries` lists keys in the order of libxml2 2.9's hash table without its random seed (256 buckets), reproduced by `HashOrder`; `duplicate match` true or false filters them. Nothing matched is 3; an unknown index -1; an empty `match` removes an index. Indexes belong to the document.
- **Hidden commands.** `XMLStrings` gives a text node's text, or an element's text with each start tag, end tag or empty element as `%n$s`. `XMLLocalize` replaces text nodes' text from a `.strings` file and leaves other nodes (as SatimageOSAX did). `XMLIndexDocument` orders the document's elements for faster XPath.

## Fixing Satimage's bugs: stage 2

Recorded from MTC_OSAX in `Fixtures/XMLFixes` (`cases-xpath.json`), with unit tests and `Scripts/e2e/xml-xpath-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `XMLSetContext` with `nsurl ""` | Kept the prefix, bound to "" | Removes it, as the dictionary says |
| `str:replace` in XPath | Unknown function (3), though the dictionary lists it | Replaces every occurrence |
| `XMLGetNodePath … from` a parent | The path with a space before it | The path |
| `XMLGetNodePath … from` another ancestor | Ignored `from` | The path from it (the full path when `from` isn't an ancestor) |
| `XMLGetXPointer … suffix` | Added without a `/` (`book[2]title`) | Added as a further step |
| `XMLXPointer` of a relative `xpointer(…)` from an element | Error -1 | Evaluated at the element, as the dictionary says |
| `XMLXPointer` in a document without a URL (`from string`) | Error -1700 for every pointer | Resolved |
| `XMLXPath` of nodes in two documents with `xpath variables` | Error -1 | A result for each |

## Findings: stage 3 (Validation)

Recorded from SatimageOSAX in `Fixtures/XML` (52 cases, generated by `generate_validation.py` into `cases-validation.json`), all replaying without differences:

- **Results.** Validation commands return nothing when valid, and otherwise libxml2's number for the first problem: DTDs 504 (content), 522 (no DTD); XML Schema 1868, 1845 (no declaration for the root), 3004 (a bad schema); RelaxNG 24 (attributes) and 1115 (a bad schema); 55 for a malformed DTD and 1549 for a file that can't be loaded. `XMLError` lists the problems (only the message when there's neither a file nor a line).
- **`XMLValidate`** uses the document's DTD (loading an external one), or `against` (a file or a path); `failure level` sets which problems fail (3: none of validation's). `verbose` changes nothing visible.
- **`XMLSchema`** takes the schema as a file, a path, a file URL, XML text or an XMLRef; without one, it follows the document's `xsi:` locations (libxml2 does, with an empty schema otherwise, so a document without them is 1845); without a document, it only checks the schema; with neither, -1701. An element is validated on its own.
- **`XMLRelaxNG`** is the same, but the schema is required (-1701). MTC_OSAX validates an element as the root of a copy.
- **`XMLCheckDTD`** takes a file, a path or URL, or the DTD's text.
- **IDs.** `XMLGetByID` finds xml:id and DTD IDs (without `validate`), from any node of the document; -2763 if none, and a list of IDs gives a list with `missing value` for those not found. `XMLGetxmlID` gives an element's ID (-2763 otherwise).
- **`XMLDu`** outlines the elements under a node by local name, a line each, indented with tabs; a document's starts with `/`.

## Fixing Satimage's bugs: stage 3

Recorded from MTC_OSAX in `Fixtures/XMLFixes` (`cases-validation.json`), with unit tests and `Scripts/e2e/xml-validation-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `XMLValidate` of an element with ID attributes | Error 513 (ID already defined): validating registered the IDs again | Validates it; only an ID repeated in the element counts |
| `XMLError` after a validation that succeeded | Stale text, prefixed with the command's name | "" (as stage 1's fix) |
| `XMLValidName`, `XMLValidNCName` of an invalid name | Error 1821 (and 5 for `{}`) | False, as the dictionary's boolean result says; a list is true only if every name is valid |

**libxml2 version difference** (recorded from MTC_OSAX in `XMLFixes`): for a schema file that can't be loaded, macOS's libxml2 adds a second message to `XMLError` ("Failed to locate the main schema resource at …"), which is kept.
