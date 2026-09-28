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
- [ ] Stage 2: XPath, XSLT (15 commands) implemented, with fixtures, unit tests and e2e; merged.
- [ ] Stage 3: Validation (11 commands) implemented, with fixtures, unit tests and e2e.
- [ ] All 83 commands implemented; SDEF consistency tests pass.
- [ ] SatimageOSAX fixtures for every command and parameter replay without differences (or with documented version differences); every deviation listed here with MTC_OSAX fixtures.
- [ ] Unit tests for every command, including error cases.
- [ ] `Scripts/e2e/xml.applescript` passes, and `Scripts/parity.sh` shows no differences for shared behavior.

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
