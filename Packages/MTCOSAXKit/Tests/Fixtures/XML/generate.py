# Generates cases.json for the XML DOM and XML Documents suites (stage 1 of PLAN-XML.md), recorded from SatimageOSAX.
# Cases open files in Input/ (made by make_inputs.py) through $FILES and write to $TMP. Each case closes what it
# opens; cases that list documents use their own pool, since a case that stops at an error leaves its document open.
# The first XML command after SatimageOSAX launches is sent three times (it loads its XML library), so warm it up
# with any XMLOpen before recording. Run: python3 generate.py
import json, os

cases, names = [], set()
def case(name, *lines):
    assert name.lower() not in names, name
    names.add(name.lower())
    cases.append({"name": name, "script": "\n".join(lines)})

def q(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

F = lambda name: f'(POSIX file "$FILES/{name}")'
T = lambda name: f'(POSIX file "$TMP/{name}")'
OPEN = lambda name="simple.xml", var="d", options="": f"set {var} to XMLOpen {F(name)}{options}"
ROOT = "set r to XMLRoot d"
CLOSE = "XMLClose d"
BOOK1 = "set b to XMLChild r index 1"
S = lambda text, var="d", options="": f"set {var} to XMLOpen from string {q(text)}{options}"

# The "KML To Excel" script
case("script-kml", f"set xmlTop to XMLOpen {F('places.kml')}", "set xml to XMLChild xmlTop index 1", "set xml to XMLChild xml index 1",
     "set cnt to XMLCount xml", 'set xml to XMLFind xml name "Placemark"',
     "set node to XMLChild xml index 1", "XMLGetText node", "set node to XMLChild xml index 2", "XMLGetText node",
     "set pointNode to XMLChild xml index 4", "set node to XMLChild pointNode index 1", "XMLGetText node",
     "set xml to XMLNextSibling xml", "set node to XMLChild xml index 1", "XMLGetText node", "XMLClose xmlTop")
case("script-kml-end", f"set xmlTop to XMLOpen {F('places.kml')}", 'set xml to XMLFind (XMLChild xmlTop index 1) name "Placemark"',
     "set xml to XMLNextSibling xml", "XMLNextSibling xml")

# XMLOpen
case("open-file", OPEN(), "XMLNodeInfo d", CLOSE)
case("open-alias", f"set d to XMLOpen ({F('simple.xml')} as alias)", "XMLTagName (XMLRoot d)", CLOSE)
case("open-path-string", 'set d to XMLOpen "$FILES/simple.xml"', "XMLTagName (XMLRoot d)", CLOSE)
case("open-file-url-string", 'set d to XMLOpen "file://$FILES/simple.xml"', "XMLTagName (XMLRoot d)", CLOSE)
case("open-missing", OPEN("nope.xml"))
case("open-invalid", OPEN("invalid.xml"))
case("open-invalid-error", f"try\n{OPEN('invalid.xml')}\nend try", "XMLError")
case("open-invalid-level-3", OPEN("invalid.xml", options=" failure level 3"), "XMLDisplayXML d", CLOSE)
case("open-invalid-verbose", f"try\n{OPEN('invalid.xml', options=' with verbose')}\nend try", "XMLError")
case("open-from-string", S("<a x='1'><b>text</b></a>"), "XMLDisplayXML d", CLOSE)
case("open-from-string-invalid", S("<a><b></a>"))
case("open-from-string-empty", S(""))
case("open-keep-blanks", OPEN(options=" with keep blanks"), ROOT, "XMLCount r", "XMLCountElement r", "XMLNodeInfo (XMLChild r index 1)", CLOSE)
case("open-no-keep-blanks", OPEN(), ROOT, "XMLCount r", "XMLCount r without all nodes", CLOSE)
case("open-dtd", OPEN("dtd.xml"), "XMLNodeInfo d", "XMLDisplayXML d", CLOSE)
case("open-substitute-entities", OPEN("dtd.xml", options=" with substitute entities"), "XMLGetText (XMLChild (XMLRoot d) index 1)", "XMLDisplayXML (XMLRoot d)", CLOSE)
case("open-no-substitute-entities", OPEN("dtd.xml"), "XMLGetText (XMLChild (XMLRoot d) index 1)", "XMLCount (XMLChild (XMLRoot d) index 1)", CLOSE)
case("open-validate", OPEN("dtd.xml", options=" with validate"), "XMLTagName (XMLRoot d)", CLOSE)
case("open-validate-invalid", S("<!DOCTYPE a [<!ELEMENT a (b)><!ELEMENT b EMPTY>]><a><c/></a>", options=" with validate"))
case("open-validate-invalid-error", "try", S('<!DOCTYPE a [<!ELEMENT a (b)><!ELEMENT b EMPTY>]><a><c/></a>', options=' with validate'), "end try", "XMLError")
case("open-no-cdata", OPEN(options=" with noCDATA"), 'XMLDisplayXML (XMLFind (XMLRoot d) name "note")', CLOSE)
case("open-html", OPEN("page.html", options=" with html4"), "XMLNodeInfo d", "XMLDisplayXML d", CLOSE)
case("open-html-as-xml", OPEN("page.html"))
case("open-html-script", S("<html><body><script>if (a < b) x();</script></body></html>", options=" with html4 and xmlscript"), "XMLDisplayXML d", CLOSE)
case("open-html-no-script", S("<html><body><script>if (a < b) x();</script></body></html>", options=" with html4"), "XMLDisplayXML d", CLOSE)
case("open-latin1", OPEN("latin1.xml"), "XMLGetText (XMLRoot d)", "XMLGetEncoding d", CLOSE)
case("open-encoding", S("<a>caf\u00e9</a>", options=' encoding "ISO-8859-1"'), "XMLGetText (XMLRoot d)", CLOSE)
case("open-bypassing-namespace", OPEN("namespaces.xml", options=" with bypassing namespace"), "XMLDisplayXML d", CLOSE)
case("open-in-pool", OPEN(options=' in pool "mtc-x1"'), "GetPool d", 'XMLListDocuments "mtc-x1"', CLOSE)
case("open-no-parameter", "XMLOpen")
case("open-twice", OPEN(), OPEN(var="e"), "XMLTagName (XMLRoot e)", CLOSE, "XMLClose e")

# Closing and references
case("close-then-use", OPEN(), ROOT, CLOSE, "XMLTagName r")
case("close-twice", OPEN(), CLOSE, CLOSE)
case("close-node", OPEN(), ROOT, "XMLClose r", "XMLTagName (XMLRoot d)")
case("exists", OPEN(), ROOT, "XMLExists r", "XMLExists {d, r}", CLOSE, "XMLExists r")
case("exists-removed", OPEN(), ROOT, BOOK1, "XMLRemove b", "XMLExists b", CLOSE)
case("not-a-reference", 'XMLTagName "text"')

# Navigation
for name, lines in [
    ("root", [ROOT, "XMLTagName r"]),
    ("count", [ROOT, "XMLCount r", "XMLCount r with all nodes", "XMLCount r without all nodes", "XMLCountElement r", "XMLCount d", "XMLCount d without all nodes"]),
    ("count-text", [ROOT, 'XMLCount (XMLFind r name "note")', 'XMLCountElement (XMLFind r name "note")']),
    ("child", [ROOT, "XMLTagName (XMLChild r index 3)", "XMLTagName (XMLChild r index 3 without all nodes)", "XMLTagName (XMLElement r index 3)"]),
    ("child-of-document", ["XMLNodeInfo (XMLChild d index 1)", "XMLNodeInfo (XMLChild d index 2)", "XMLNodeInfo (XMLChild d index 3)", "XMLChild d index 1 without all nodes"]),
    ("child-text-nodes", [ROOT, 'set n to XMLFind r name "note"', "XMLNodeInfo (XMLChild n index 1)", "XMLNodeInfo (XMLChild n index 2)", "XMLNodeInfo (XMLChild n index 5)", "XMLTagName (XMLChild n index 1 without all nodes)"]),
    ("child-out-of-range", [ROOT, "XMLChild r index 6"]),
    ("child-zero", [ROOT, "XMLChild r index 0"]),
    ("child-negative", [ROOT, "XMLChild r index -1"]),
    ("child-no-index", [ROOT, "XMLChild r"]),
    ("child-list", [ROOT, "XMLChild r index {1, 2}"]),
    ("element-out-of-range", [ROOT, "XMLElement r index 6"]),
    ("parent", [ROOT, BOOK1, "XMLTagName (XMLParent b)", "XMLNodeInfo (XMLParent r)", "XMLParent d"]),
    ("parent-list", [ROOT, BOOK1, "XMLParent {b, XMLChild b index 1}"]),
    ("siblings", [ROOT, BOOK1, "XMLTagName (XMLNextSibling b)", "XMLTagName (XMLNextElement b)", "set l to XMLChild r index 5", "XMLTagName (XMLPrevSibling l)", "XMLTagName (XMLPrevElement l)"]),
    ("siblings-end", [ROOT, "XMLNextSibling (XMLChild r index 5)"]),
    ("siblings-start", [ROOT, "XMLPrevSibling (XMLChild r index 1)"]),
    ("siblings-of-root", [ROOT, "XMLNodeInfo (XMLPrevSibling r)", "XMLPrevElement r"]),
    ("siblings-text", [ROOT, 'set n to XMLFind r name "note"', "XMLNodeInfo (XMLNextSibling (XMLChild n index 1))", "XMLTagName (XMLNextElement (XMLChild n index 1))"]),
    ("siblings-list", [ROOT, BOOK1, "XMLNextSibling {b, XMLChild r index 2}"]),
]:
    case(f"nav-{name}", OPEN(), *lines, CLOSE)
case("nav-keep-blanks", OPEN(options=" with keep blanks"), ROOT, "XMLNodeInfo (XMLChild r index 1)", "XMLTagName (XMLChild r index 1 without all nodes)", "XMLNodeInfo (XMLNextSibling (XMLChild r index 2))", CLOSE)

# Reading
for name, lines in [
    ("tag-name", [ROOT, "XMLTagName r", "XMLTagName (XMLChild (XMLChild r index 1) index 2)", "XMLTagName d"]),
    ("tag-name-text", [ROOT, 'XMLTagName (XMLChild (XMLFind r name "note") index 1)']),
    ("tag-name-list", [ROOT, "XMLTagName {r, XMLChild r index 1}"]),
    ("attribute", [ROOT, BOOK1, 'XMLGetAttribute b name "id"', 'XMLGetAttribute r name "version"']),
    ("attribute-missing", [ROOT, BOOK1, 'XMLGetAttribute b name "nope"']),
    ("attribute-no-name", [ROOT, BOOK1, "XMLGetAttribute b"]),
    ("attribute-list-names", [ROOT, BOOK1, 'XMLGetAttribute b name {"id", "lang", "nope"}']),
    ("attribute-list-nodes", [ROOT, 'XMLGetAttribute {XMLChild r index 1, XMLChild r index 2} name "id"']),
    ("attribute-of-text", [ROOT, 'XMLGetAttribute (XMLChild (XMLFind r name "note") index 1) name "x"']),
    ("node-info-document", ["XMLNodeInfo d"]),
    ("node-info-element", [ROOT, "XMLNodeInfo r", "XMLNodeInfo (XMLChild r index 1)", 'XMLNodeInfo (XMLFind r name "empty")']),
    ("node-info-namespaced", [ROOT, "XMLNodeInfo (XMLChild (XMLChild r index 1) index 2)"]),
    ("node-info-kinds", ["XMLNodeInfo (XMLChild d index 1)", "XMLNodeInfo (XMLChild d index 2)", ROOT, 'set n to XMLFind r name "note"', "XMLNodeInfo (XMLChild n index 1)", "XMLNodeInfo (XMLChild n index 4)", "XMLNodeInfo (XMLChild n index 5)"]),
    ("node-info-list", [ROOT, "XMLNodeInfo {d, r}"]),
    ("text", [ROOT, BOOK1, 'XMLGetText (XMLFind b name "title")', 'XMLGetText (XMLFind r name "note")', 'XMLGetText (XMLFind r name "empty")', 'XMLGetText (XMLFind r name "spaces")']),
    ("text-of-parent", [ROOT, "XMLGetText (XMLChild r index 1)", "XMLGetText r"]),
    ("text-of-text-node", [ROOT, 'XMLGetText (XMLChild (XMLFind r name "note") index 1)']),
    ("text-of-document", ["XMLGetText d"]),
    ("text-list", [ROOT, BOOK1, 'XMLGetText {XMLFind b name "title", XMLFind b name "year"}']),
    ("text-comment", ['XMLGetText (XMLChild d index 1)']),
]:
    case(f"read-{name}", OPEN(), *lines, CLOSE)
case("read-text-entities", OPEN("dtd.xml"), "XMLGetText (XMLChild (XMLRoot d) index 1)", CLOSE)
case("read-text-latin1", OPEN("latin1.xml"), "XMLGetText (XMLRoot d)", CLOSE)

# XMLNodeInfo of a file (only its start is read)
case("info-file", f"XMLNodeInfo {F('simple.xml')}")
case("info-file-alias-dtd", f"XMLNodeInfo ({F('dtd.xml')} as alias)")
case("info-file-string-html", 'XMLNodeInfo "$FILES/page.html"')
case("info-file-invalid", f"XMLNodeInfo {F('invalid.xml')}")
case("info-file-latin1", f"XMLNodeInfo {F('latin1.xml')}")
case("info-file-missing", f"XMLNodeInfo {F('nope.xml')}")

# XMLDisplayXML
for name, spec in [
    ("document", ""), ("no-formatting", " without formatting"), ("no-declaration", " without xml declaration"),
    ("encoding", ' encoding "ISO-8859-1"'), ("html4", " with html4"), ("no-nsclean", " without nsclean"),
]:
    case(f"display-{name}", OPEN(), f"XMLDisplayXML d{spec}", CLOSE)
case("display-element", OPEN(), ROOT, "XMLDisplayXML (XMLChild r index 1)", "XMLDisplayXML (XMLChild r index 1) without formatting", CLOSE)
case("display-namespaced", OPEN("namespaces.xml"), 'XMLDisplayXML (XMLChild (XMLRoot d) index 3)', 'XMLDisplayXML (XMLChild (XMLRoot d) index 3) without nsclean', CLOSE)
case("display-text", OPEN(), ROOT, 'XMLDisplayXML (XMLChild (XMLFind r name "note") index 1)', CLOSE)
case("display-list", OPEN(), ROOT, "XMLDisplayXML {XMLChild r index 1, XMLChild r index 4}", CLOSE)
case("display-keep-blanks", OPEN(options=" with keep blanks"), "XMLDisplayXML d", "XMLDisplayXML d without formatting", CLOSE)
case("display-html-document", OPEN("page.html", options=" with html4"), "XMLDisplayXML d", "XMLDisplayXML d with html4", CLOSE)
case("display-dtd", OPEN("dtd.xml"), "XMLDisplayXML d", CLOSE)
case("display-unicode", S("<a>é ☃ &#x1F600;</a>"), "XMLDisplayXML d", 'XMLDisplayXML d encoding "US-ASCII"', CLOSE)
case("display-indent-string", OPEN(), 'set old to XMLSetIndentString "  "', "XMLDisplayXML (XMLChild (XMLRoot d) index 1)", "XMLSetIndentString old", CLOSE)

# Changing
for name, lines in [
    ("set-attribute", [BOOK1, 'XMLSetAttribute b name "id" to "new"', 'XMLSetAttribute b name "extra" to "x"']),
    ("set-attribute-number", [BOOK1, 'XMLSetAttribute b name "n" to 42']),
    ("set-attribute-lists", [BOOK1, 'XMLSetAttribute b name {"a1", "a2"} to {"1", "2"}']),
    ("set-attribute-missing-value", [BOOK1, 'XMLSetAttribute b name {"id", "lang"} to {missing value, "de"}']),
    ("set-attribute-suppressing", [BOOK1, 'XMLSetAttribute b name {"id", "lang"} to {missing value, "de"} with suppressing']),
    ("set-attribute-namespace", [BOOK1, 'XMLSetAttribute b name "lang" to "en" namespace "http://www.w3.org/XML/1998/namespace"']),
    ("set-attribute-escaping", [BOOK1, 'XMLSetAttribute b name "q" to "a<b & \\"c\\""']),
    ("set-attribute-no-to", [BOOK1, 'XMLSetAttribute b name "q"']),
    ("remove-attribute", [BOOK1, 'XMLRemoveAttribute b name "lang"', 'XMLRemoveAttribute b name "nope"']),
    ("remove-attribute-list", [BOOK1, 'XMLRemoveAttribute b name {"id", "lang"}']),
    ("remove", [BOOK1, "XMLRemove b", "XMLCount r"]),
    ("remove-then-use", [BOOK1, "set t to XMLChild b index 1", "XMLRemove b", "XMLTagName t"]),
    ("remove-root", ["XMLRemove r", "XMLRoot d"]),
    ("remove-list", ["XMLRemove {XMLChild r index 1, XMLChild r index 2}", "XMLCount r"]),
    ("remove-children", [BOOK1, "XMLRemoveChildren b", "XMLCount b"]),
    ("new-child-string", [BOOK1, 'set c to XMLNewChild "<isbn>123</isbn>" at b', "XMLTagName c"]),
    ("new-child-text", [BOOK1, 'set c to XMLNewChild "plain text" at b', "XMLNodeInfo c"]),
    ("new-child-several", [BOOK1, 'XMLNewChild "<x/><y/>" at b']),
    ("new-child-clone", [BOOK1, 'set c to XMLNewChild (XMLChild r index 2) at b', "XMLNodeInfo c"]),
    ("new-child-clone-list", [BOOK1, 'XMLNewChild {XMLChild r index 2, XMLChild r index 3} at b']),
    ("new-child-invalid", [BOOK1, 'XMLNewChild "<a><b></a>" at b']),
    ("new-child-namespace", [BOOK1, 'set c to XMLNewChild "<dc:subject>whale</dc:subject>" at b', "XMLNodeInfo c"]),
    ("new-child-no-nsclean", [BOOK1, 'XMLNewChild "<dc:subject xmlns:dc=\\"http://purl.org/dc/elements/1.1/\\">whale</dc:subject>" at b without nsclean']),
    ("new-child-keep-blanks", [BOOK1, 'XMLNewChild "<a>  <b/>  </a>" at b with keep blanks']),
    ("new-child-no-at", ['XMLNewChild "<a/>"']),
    ("new-sibling-after", [BOOK1, 'set s to XMLNewSibling "<book id=\\"b0\\"/>" after b', "XMLGetAttribute (XMLChild r index 2) name \"id\""]),
    ("new-sibling-before", [BOOK1, 'XMLNewSibling "<book id=\\"b0\\"/>" before b', "XMLGetAttribute (XMLChild r index 1) name \"id\""]),
    ("new-sibling-clone", [BOOK1, 'XMLNewSibling (XMLChild r index 3) before b']),
    ("new-sibling-neither", [BOOK1, 'XMLNewSibling "<x/>"']),
    ("new-sibling-of-root", ['XMLNewSibling "<x/>" after r']),
    ("set-xml", [BOOK1, 'XMLSetXML b to "<t>new</t><u/>"', "XMLCount b"]),
    ("set-xml-text-node", ['set n to XMLChild (XMLFind r name "note") index 1', 'XMLSetXML n to "<i>replaced</i> text"', 'XMLCount (XMLFind r name "note")']),
    ("set-xml-invalid", [BOOK1, 'XMLSetXML b to "<t>"']),
    ("set-text", [BOOK1, 'XMLSetText (XMLChild b index 1) to "New & <title>"', "XMLGetText (XMLChild b index 1)"]),
    ("set-text-element", [BOOK1, 'XMLSetText b to "just text"', "XMLCount b"]),
    ("set-text-list", [BOOK1, 'XMLSetText {XMLChild b index 1, XMLChild b index 3} to {"T", "Y"}']),
    ("set-text-missing-value", [BOOK1, 'XMLSetText {XMLChild b index 1, XMLChild b index 3} to {missing value, "Y"}']),
    ("set-text-suppressing", [BOOK1, 'XMLSetText {XMLChild b index 1, XMLChild b index 3} to {missing value, "Y"} with suppressing']),
    ("set-text-number", [BOOK1, 'XMLSetText (XMLChild b index 3) to 1900']),
    ("append-text", [BOOK1, 'XMLAppendText " (novel)" at (XMLChild b index 1)', "XMLGetText (XMLChild b index 1)"]),
    ("append-text-empty-element", ['XMLAppendText "filled" at (XMLFind r name "empty")', 'XMLGetText (XMLFind r name "empty")']),
    ("append-text-mixed", ['XMLAppendText " end" at (XMLFind r name "note")']),
]:
    case(f"change-{name}", OPEN(), ROOT, *lines, "XMLDisplayXML d", CLOSE)

# Namespaces
N = [OPEN("namespaces.xml"), ROOT]
for name, lines in [
    ("get", ["XMLGetNameSpace r", "XMLGetNameSpace (XMLChild r index 1)", "XMLGetNameSpace (XMLChild r index 2)"]),
    ("get-none", ['XMLGetNameSpace (XMLRoot (XMLOpen from string "<a/>"))']),
    ("get-attribute", ["XMLGetNameSpace (XMLChild r index 1)"]),
    ("get-all", ["XMLGetNameSpaces r", "XMLGetNameSpaces (XMLChild (XMLChild r index 3) index 1)"]),
    ("from-prefix", ['XMLGetNameSpaceFromPrefix r prefix "a"', 'XMLGetNameSpaceFromPrefix r prefix ""', 'XMLGetNameSpaceFromPrefix (XMLChild (XMLChild r index 3) index 1) prefix "c"']),
    ("from-prefix-missing", ['XMLGetNameSpaceFromPrefix r prefix "zz"']),
    ("add", ['XMLAddNamespace {nsprefix:"n", nsurl:"urn:new"} at r', "XMLGetNameSpaces r", "XMLDisplayXML r without formatting"]),
    ("add-default", ['XMLAddNamespace {nsprefix:"", nsurl:"urn:other"} at (XMLChild r index 2)', "XMLDisplayXML r without formatting"]),
    ("add-existing-prefix", ['XMLAddNamespace {nsprefix:"a", nsurl:"urn:changed"} at r']),
    ("attribute-with-namespace", ['XMLGetAttribute (XMLChild r index 1) name "attr" namespace "urn:b"', 'XMLGetAttribute (XMLChild r index 1) name "attr"']),
]:
    case(f"ns-{name}", *N, *lines, CLOSE)

# Searching
for name, lines in [
    ("find-name", ['XMLTagName (XMLFind r name "book")']),
    ("find-all", ['XMLFind r name "book" with all occurrences']),
    ("find-deep", ['XMLGetText (XMLFind r name "title")', 'XMLFind r name "title" with all occurrences']),
    ("find-attribute", ['XMLGetAttribute (XMLFind r key "lang" value "fr") name "id"']),
    ("find-key-only", ['XMLFind r key "currency" with all occurrences']),
    ("find-name-and-key", ['XMLFind r name "book" key "id" value "b2"']),
    ("find-prefixed", [BOOK1, 'XMLTagName (XMLFind b name "creator")', 'XMLFind b name "dc:creator"']),
    ("find-missing", ['XMLFind r name "nope"']),
    ("find-missing-all", ['XMLFind r name "nope" with all occurrences']),
    ("find-self", ['XMLFind r name "library"']),
    ("find-in-document", ['XMLTagName (XMLFind d name "title")']),
    ("find-nothing", ["XMLFind r"]),
    ("find-text", ['set t to XMLFindText "Hugo" in r', "XMLNodeInfo t", "XMLTagName (XMLParent t)"]),
    ("find-text-all", ['XMLFindText "e" in r with all occurrences']),
    ("find-text-missing", ['XMLFindText "zzz" in r']),
    ("find-text-case", ['XMLFindText "hugo" in r']),
    ("find-text-cdata", ['XMLFindText "cdata" in r with all occurrences']),
    ("regexp", ['XMLGetText (XMLRegexp "^[0-9]{4}$" in r)']),
    ("regexp-all", ['XMLRegexp "[0-9]" in r with all occurrences']),
    ("regexp-not-conforming", ['XMLRegexp "[0-9]" in r with all occurrences without conforming']),
    ("regexp-invalid", ['XMLRegexp "([" in r']),
    ("regexp-missing", ['XMLRegexp "^zzz$" in r']),
]:
    case(f"search-{name}", OPEN(), ROOT, *lines, CLOSE)

# URLs
B = [OPEN("base.xml"), ROOT, "set leaf to XMLChild (XMLChild r index 1) index 1"]
for name, lines in [
    ("base", ["XMLBase d", "XMLBase r", "XMLBase leaf"]),
    ("base-as-alias", ["XMLBase d as alias"]),
    ("set-base", ['XMLSetBase leaf to "other/"', "XMLBase leaf", "XMLDisplayXML r without formatting"]),
    ("set-base-empty", ['XMLSetBase (XMLChild r index 1) to ""', "XMLBase leaf"]),
    ("absolute", ['XMLAbsoluteURL "file.html" from leaf', 'XMLAbsoluteURL "../x.html" from leaf', 'XMLAbsoluteURL "http://other.com/y" from leaf']),
    ("absolute-from-url", ['XMLAbsoluteURL "b.html" from "http://h.com/a/"']),
    ("absolute-as-alias", ['XMLAbsoluteURL "simple.xml" from d as alias']),
    ("relative", ['XMLRelativeURL "http://example.com/dir/sub/other.html" from leaf', 'XMLRelativeURL "http://example.com/x.html" from leaf']),
]:
    case(f"url-{name}", *B, *lines, CLOSE)

# Errors and settings
case("error-none", S("<a/>"), "XMLError", CLOSE)
case("error-level", "set old to XMLErrorLevel", "XMLErrorLevel 3", "XMLErrorLevel old")
case("error-level-3-opens-invalid", "set old to XMLErrorLevel 3", f"try\n{OPEN('invalid.xml')}\nXMLDisplayXML d\n{CLOSE}\nend try", "XMLErrorLevel old")
BAD_ENCODING = S('<?xml version="1.0" encoding="nonsense"?><a/>')
case("error-level-1-warning", "set old to XMLErrorLevel 1", "try", BAD_ENCODING, CLOSE, "end try", "XMLError", "XMLErrorLevel old")
case("extended-char", "set old to XMLExtendedChar true", S("<a>x&#1;y</a>"), "XMLGetText (XMLRoot d)", CLOSE, "XMLExtendedChar old")
case("extended-char-off", "set old to XMLExtendedChar false", S("<a>x&#1;y</a>"), "XMLExtendedChar old")
case("indent-string", 'set old to XMLSetIndentString "    "', "XMLSetIndentString old")

# Documents: URLs, saving, encodings, cloning
case("doc-url", OPEN(), "XMLURL d", "XMLURL d with parent", "XMLURL (XMLRoot d)", CLOSE)
case("doc-url-as-text", S("<a/>"), f"XMLSave d in {T('url-as-text.xml')}", "XMLURL d as text", CLOSE)
case("doc-url-as-alias", OPEN(), "XMLURL d as alias", CLOSE)
case("doc-url-string", S("<a/>"), "XMLURL d")
case("doc-set-url", S("<a/>"), f"XMLSetURL d to {T('set-url.xml')}", "XMLURL d", "XMLSave d", CLOSE, f"readtext {T('set-url.xml')}")
# Documents opened from latin1.xml only here, and in their own pool: XMLDocument returns every open document for
# the file, and cases that stop at an error leave theirs open.
case("doc-document", OPEN("latin1.xml", options=' in pool "mtc-x7"'), f'set e to XMLDocument {F("latin1.xml")} in pool "mtc-x7"', "XMLTagName (XMLRoot e)", CLOSE)
case("doc-document-twice", OPEN("latin1.xml", options=' in pool "mtc-x8"'), OPEN("latin1.xml", var="e", options=' in pool "mtc-x8"'), f'XMLDocument {F("latin1.xml")} in pool "mtc-x8"', 'DeletePool "mtc-x8"')
case("doc-document-not-open", f'XMLDocument {F("latin1.xml")} in pool "mtc-x9"')
case("doc-save", OPEN(), f"XMLSave d in {T('save.xml')}", CLOSE, f"readtext {T('save.xml')}")
case("doc-save-options", OPEN(), f'XMLSave d in {T("save-options.xml")} without formatting and xml declaration', CLOSE, f"readtext {T('save-options.xml')}")
case("doc-save-encoding", OPEN("latin1.xml"), f'XMLSave d in {T("save-latin1.xml")}', CLOSE, f"readtext {T('save-latin1.xml')}")
case("doc-save-encoding-parameter", S("<a>café</a>"), f'XMLSave d in {T("save-encoding.xml")} encoding "ISO-8859-1"', CLOSE, f"readtext {T('save-encoding.xml')}")
case("doc-save-html", OPEN("page.html", options=" with html4"), f'XMLSave d in {T("save.html")} with html4', CLOSE, f"readtext {T('save.html')}")
case("doc-save-without-in", S("<a/>"), f"XMLSave d in {T('again.xml')}", 'XMLSetAttribute (XMLRoot d) name "x" to "1"', "XMLSave d", CLOSE, f"readtext {T('again.xml')}")
case("doc-save-new-without-in", S("<a/>"), "XMLSave d")
case("doc-save-element", OPEN(), f"XMLSave (XMLChild (XMLRoot d) index 1) in {T('element.xml')}", CLOSE, f"readtext {T('element.xml')}")
case("doc-save-string-path", S("<a/>"), 'XMLSave d in "$TMP/string-path.xml"', CLOSE, f"readtext {T('string-path.xml')}")
case("doc-save-missing-folder", S("<a/>"), f"XMLSave d in {T('nope/x.xml')}")
case("doc-encoding", OPEN(), "XMLGetEncoding d", 'XMLSetEncoding d to "ISO-8859-1"', "XMLGetEncoding d", "XMLDisplayXML d", CLOSE)
case("doc-encoding-none", S("<a/>"), "XMLGetEncoding d", CLOSE)
case("doc-encoding-invalid", S("<a/>"), 'XMLSetEncoding d to "nonsense"', "XMLDisplayXML d", CLOSE)
case("doc-clone", OPEN(), "set e to XMLCloneDocument d", "XMLDisplayXML e", "XMLURL e", "XMLClose e", CLOSE)
case("doc-clone-in-pool", OPEN(), 'set e to XMLCloneDocument d in pool "mtc-x2"', "GetPool e", "XMLClose e", CLOSE)
case("doc-clone-independent", OPEN(), "set e to XMLCloneDocument d", "XMLRemove (XMLRoot e)", "XMLTagName (XMLRoot d)", "XMLClose e", CLOSE)
case("doc-xinclude", OPEN("include.xml"), "XMLXInclude d", "XMLDisplayXML d", CLOSE)
case("doc-xinclude-none", OPEN(), "XMLXInclude d", CLOSE)
case("doc-xinclude-missing", S('<doc xmlns:xi="http://www.w3.org/2001/XInclude"><xi:include href="nope.xml"/></doc>'), "XMLXInclude d", CLOSE)
case("doc-catalog", 'XMLCatalog "-//W3C//DTD XHTML 1.0 Strict//EN"')
case("doc-catalog-unknown", 'XMLCatalog "urn:nothing"')
case("doc-list", OPEN(options=' in pool "mtc-x3"'), S("<a/>", var="e", options=' in pool "mtc-x3"'), 'XMLListDocuments "mtc-x3"', 'XMLListDocuments "mtc-x3" as string', 'DeletePool "mtc-x3"', 'XMLListDocuments "mtc-x3"')
case("doc-list-plists-separate", 'set p to PlistNew {a:1} in pool "mtc-x4"', S("<a/>", options=' in pool "mtc-x4"'), 'XMLListDocuments "mtc-x4"', 'PlistListDocuments "mtc-x4"', 'DeletePool "mtc-x4"')
case("doc-id", OPEN(), 'XMLSetDocID d to "mine"', 'XMLTagName (XMLRoot (XMLGetDocByID "mine"))', 'XMLSetDocID d to "other"', CLOSE)
case("doc-id-missing", 'XMLGetDocByID "mtc-no-such-id"')
case("doc-id-plist-separate", 'set p to PlistNew {a:1}', 'PlistSetDocID p to "shared-id"', 'XMLGetDocByID "shared-id"')
case("doc-extras", OPEN(), 'XMLSetExtras d to {a:1, b:{"x"}}', "XMLGetExtras d", CLOSE)
case("doc-extras-none", OPEN(), "XMLGetExtras d", CLOSE)
case("doc-extras-node", OPEN(), 'XMLSetExtras (XMLRoot d) to "x"', "XMLGetExtras d", CLOSE)
# XMLGetID/XMLFromID numbers are a counter in the app, so unit tests cover them.

# Canonicalization
C = [S('<?xml version="1.0"?><!-- c --><a xmlns:u="urn:unused" b="2" a="1"><x   y="z"/><!-- inner --></a>')]
for name, spec in [("default", ""), ("no-comments", " without comments"), ("exclusive", " with exclusive"),
                   ("exclusive-prefixes", ' with exclusive inclusive prefixes {"u"}'), ("digest-sha1", ' digest "SHA1"'), ("digest-md5", ' digest "MD5"'),
                   ("digest-invalid", ' digest "SHA256"')]:
    case(f"c14n-{name}", *C, f"XMLc14n d{spec}", CLOSE)
case("c14n-in-file", *C, f"XMLc14n d in {T('c14n.xml')}", CLOSE, f"readtext {T('c14n.xml')}")
case("c14n-digest-in-file", *C, f'XMLc14n d in {T("digest.bin")} digest "SHA1"', CLOSE)
case("c14n-element", *C, "XMLc14n (XMLRoot d)", CLOSE)
case("c14n-nodelist", *C, "XMLc14n d nodelist {XMLChild (XMLRoot d) index 1}", CLOSE)

# Pools with XML
case("pool-get", S("<a/>", options=' in pool "mtc-x5"'), "GetPool d", "GetPool (XMLRoot d)", CLOSE)
case("pool-delete", S("<a/>", options=' in pool "mtc-x6"'), 'DeletePool "mtc-x6"', "XMLRoot d")

MTC_OSAX_FIXES = {
    "exists": "Satimage: XMLExists of a closed document's reference was error -1728, not false",
    "exists-removed": "Satimage: XMLExists of a removed node's reference was error -1728, not false",
    "change-append-text-mixed": "Satimage crashed appending text to an element with mixed content",
    "change-set-xml-text-node": "Satimage: XMLSetXML of a text node left a document XMLDisplayXML returned nothing for",
    "error-none": "Satimage: XMLError returned stale text from an earlier command",
    "doc-save-string-path": "Satimage: error 1535 for a POSIX path string",
    # Not Satimage bugs: macOS's libxml2 (2.9.13) writes some line breaks differently from SatimageOSAX's. The
    # content is the same; these are recorded from MTC_OSAX.
    "display-html-document": "libxml2 version: no line break after <br> in HTML",
    "display-html4": "libxml2 version: line breaks in HTML output",
    "doc-save-html": "libxml2 version: no line break after <br> in HTML",
    "open-html": "libxml2 version: no line break after <br> in HTML",
    "doc-xinclude": "libxml2 version: no blank lines for the XInclude markers",
}
assert MTC_OSAX_FIXES.keys() <= names
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
if MTC_OSAX_FIXES:
    os.makedirs("../XMLFixes", exist_ok=True)
    json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../XMLFixes/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
