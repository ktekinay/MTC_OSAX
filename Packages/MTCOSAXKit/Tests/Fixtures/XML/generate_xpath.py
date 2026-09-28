# Generates cases-xpath.json for the XML XPath, XSLT suite (stage 2 of Implemented/PLAN-XML.md), recorded from SatimageOSAX
# into this folder like generate.py's. Warm SatimageOSAX up with an XMLOpen first. Run: python3 generate_xpath.py
import json, os

existing = {c["name"].lower() for c in json.load(open("cases.json"))}
cases, names = [], set()
def case(name, *lines):
    name = "xpath-" + name if not name.startswith(("xslt-", "index-", "xptr-")) else name
    assert name.lower() not in names and name.lower() not in existing, name
    names.add(name.lower())
    cases.append({"name": name, "script": "\n".join(lines)})

def q(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

F = lambda name: f'(POSIX file "$FILES/{name}")'
T = lambda name: f'(POSIX file "$TMP/{name}")'
OPEN = lambda name="simple.xml", var="d", options="": f"set {var} to XMLOpen {F(name)}{options}"
ROOT = "set r to XMLRoot d"
CLOSE = "XMLClose d"
DC = '{nsprefix:"dc", nsurl:"http://purl.org/dc/elements/1.1/"}'

# XMLXPath
for name, expression, extra in [
    ("children", "book", ""), ("descendants", "//title", ""), ("predicate", "book[@lang='fr']/title", ""),
    ("position", "book[2]", ""), ("attribute", "book/@id", ""), ("text-nodes", "book/title/text()", ""),
    ("count", "count(//book)", ""), ("string", "string(book[1]/title)", ""), ("boolean", "count(book) > 1", ""),
    ("number-sum", "sum(//year)", ""), ("no-match", "nothing", ""), ("absolute", "/library/note", ""),
    ("parent", "book[1]/title/..", ""), ("union", "note | empty", ""), ("comment", "book[2]/comment()", ""),
    ("invalid", "book[", ""), ("unknown-function", "nope(1)", ""), ("prefix-undeclared", "book/dc:creator", ""),
    ("prefix-declared", "book/dc:creator", f" namespace {DC}"), ("prefix-declared-list", "book/dc:creator", f" namespace {{{DC}}}"),
    ("variable-list", "book[@id=$v]/title", ' xpath variables {"v", "b2"}'), ("variable-record", "book[@id=$v]/title", ' xpath variables {v:"b2"}'),
    ("variable-number", "book[$n]/title", ' xpath variables {"n", 2}'), ("variable-boolean", "$b", ' xpath variables {"b", true}'),
    ("variable-undefined", "book[@id=$v]", ""), ("variable-list-odd", "$v", ' xpath variables {"v"}'),
]:
    case(name, OPEN(), ROOT, f"set x to XMLXPath r with {q(expression)}{extra}", "x", CLOSE)
case("result-use", OPEN(), ROOT, 'set {t} to XMLXPath r with "book[1]/title"', "XMLGetText t", CLOSE)
case("attribute-use", OPEN(), ROOT, 'set a to item 1 of (XMLXPath r with "book/@id")', "XMLNodeInfo a", "XMLGetText a", "XMLTagName a", CLOSE)
case("from-document", OPEN(), 'XMLXPath d with "library/book[1]/title"', 'XMLXPath d with "//year"', CLOSE)
case("from-text-node", OPEN(), ROOT, 'set t to XMLChild (XMLChild (XMLChild r index 1) index 1) index 1', 'XMLXPath t with ".."', CLOSE)
case("default-namespace", OPEN("namespaces.xml"), ROOT, 'XMLXPath r with "item"', 'XMLXPath r with "d:item" namespace {nsprefix:"d", nsurl:"urn:default"}', CLOSE)
case("no-with", OPEN(), ROOT, "XMLXPath r", CLOSE)
case("list", OPEN(), ROOT, 'XMLXPath {r, XMLChild r index 1} with "title"', CLOSE)

# Extension functions
NS = {"fn": "http://www.w3.org/2005/xpath-functions", "math": "http://exslt.org/math", "str": "http://exslt.org/strings",
      "set": "http://exslt.org/sets", "date": "http://exslt.org/dates-and-times", "crypto": "http://exslt.org/crypto",
      "sat": "http://satimage.fr/software/xpath-functions"}
for name, prefix, expressions in [
    ("fn", "fn", ["fn:upper-case(string(book[1]/title))", "fn:lower-case('ABC')", "fn:compare('a', 'b')", "fn:compare('b', 'b')",
                  "fn:ends-with('abc', 'bc')", "fn:base-uri(book[1])", "fn:upper-case()"]),
    ("exslt-math", "math", ["math:abs(-3)", "math:max(//year)", "math:sqrt(16)"]),
    ("exslt-str", "str", ["str:padding(3, 'x')", "str:concat(//title)", "str:encode-uri('a b', true())", "str:align('ab', '----', 'right')", "str:decode-uri('a%20b')"]),
    ("exslt-str-replace", "str", ["str:replace('a-b-c', '-', '+')", "str:replace(string(book[1]/title), 'Dick', 'Duck')"]),
    ("exslt-set", "set", ["count(set:distinct(//book/@lang | //book/@lang))", "count(set:leading(book, book[2]))"]),
    ("exslt-date", "date", ["date:year('2020-03-04')", "date:day-name('2020-03-04')"]),
    ("exslt-crypto", "crypto", ["crypto:md5('abc')", "crypto:sha1('abc')", "crypto:sha256('abc')", "crypto:sha224('abc')"]),
    ("satimage-uri", "sat", ["sat:parent-uri('http://a.com/b/c.xml')", "sat:relative-uri('http://a.com/b/c.xml', 'http://a.com/d/e.xml')",
                             "sat:parent-uri('http://a.com/b/')"]),
]:
    case("functions-" + name, OPEN(), ROOT, f'XMLSetContext d namespace {{{{nsprefix:"{prefix}", nsurl:"{NS[prefix]}"}}}}',
         *[f"try\nXMLXPath r with {q(e)}\nend try" for e in expressions], CLOSE)
case("functions-undeclared", OPEN(), ROOT, 'XMLXPath r with "upper-case(\'a\')"', 'XMLXPath r with "math:abs(-3)"', CLOSE)

# XMLSetContext, XMLGetContext
case("context", OPEN(), ROOT, f"XMLSetContext d namespace {{{DC}}} xpath variables {{\"v\", \"b1\"}}", "XMLGetContext d",
     'XMLXPath r with "book[@id=$v]/dc:creator"', CLOSE)
case("context-remove", OPEN(), ROOT, f"XMLSetContext d namespace {{{DC}}} xpath variables {{\"v\", \"b1\"}}",
     'XMLSetContext d namespace {{nsprefix:"dc", nsurl:""}} xpath variables {"v", missing value}', "XMLGetContext d", 'XMLXPath r with "book/dc:creator"', CLOSE)
case("context-empty", OPEN(), "XMLGetContext d", CLOSE)
case("context-override", OPEN(), ROOT, 'XMLSetContext d xpath variables {"v", "b1"}', 'XMLXPath r with "book[@id=$v]/title" xpath variables {"v", "b2"}', CLOSE)
case("context-record", OPEN(), 'XMLSetContext d xpath variables {v:"b1", n:2}', "XMLGetContext d", CLOSE)
case("context-from-parameters", OPEN(), ROOT, f'XMLXPath r with "book[@id=$v]/dc:creator" namespace {DC} xpath variables {{"v", "b1"}}', "XMLGetContext d",
     'XMLXPath r with "book[@id=$v]/dc:creator"', 'XMLXPath r with "count(book[@id=$v])" xpath variables {"v", "b2"}', "XMLGetContext d", CLOSE)
case("context-from-index", OPEN(), f'XMLNewIndex "k" match "//book[@lang=$l]" use "dc:creator" at d namespace {DC} xpath variables {{"l", "fr"}}', "XMLGetContext d", CLOSE)
case("context-from-xpointer", OPEN(), f'XMLXPointer "#xpointer(//dc:creator)" from d namespace {DC}', "XMLGetContext d", CLOSE)
case("context-from-list", OPEN(), OPEN(var="e"), 'XMLXPath {XMLRoot d, XMLRoot e} with "$v" xpath variables {"v", 1}', "XMLGetContext d", "XMLGetContext e", CLOSE, "XMLClose e")
case("context-other-document", OPEN(), OPEN(var="e"), 'XMLSetContext d xpath variables {"v", "b1"}', 'XMLXPath (XMLRoot e) with "book[@id=$v]"', CLOSE, "XMLClose e")

# XMLGetNodePath
case("node-path", OPEN(), ROOT, 'set y to item 1 of (XMLXPath r with "book[2]/year")', "XMLGetNodePath y", "XMLGetNodePath r", CLOSE)
case("node-path-document", OPEN(), "XMLGetNodePath d", CLOSE)
case("node-path-text", OPEN(), ROOT, 'set t to item 1 of (XMLXPath r with "book[1]/title/text()")', "XMLGetNodePath t", CLOSE)
case("node-path-attribute", OPEN(), ROOT, 'set a to item 1 of (XMLXPath r with "book[1]/@lang")', "XMLGetNodePath a", CLOSE)
case("node-path-comment", OPEN(), ROOT, 'set c to item 1 of (XMLXPath r with "book[2]/comment()")', "XMLGetNodePath c", CLOSE)
case("node-path-unique", OPEN(), ROOT, 'XMLGetNodePath (XMLFind r name "note")', CLOSE)
case("node-path-from-root", OPEN(), ROOT, 'set y to item 1 of (XMLXPath r with "book[2]/year")', "XMLGetNodePath y from r", CLOSE)
case("node-path-from", OPEN(), ROOT, 'XMLGetNodePath (item 1 of (XMLXPath r with "book[2]/year")) from (XMLChild r index 2)', CLOSE)
case("node-path-namespace", OPEN(), ROOT, 'XMLGetNodePath (XMLChild (XMLChild r index 1) index 2)', CLOSE)

# XPointer
case("xptr-xpath", OPEN(), 'XMLXPointer "#xpointer(//book[2]/title)" from d', CLOSE)
case("xptr-xpath-use", OPEN(), 'set {t} to XMLXPointer "#xpointer(//book[2]/title)" from d', "XMLGetText t", CLOSE)
case("xptr-relative", OPEN(), ROOT, 'XMLXPointer "#xpointer(title)" from (XMLChild r index 1)', CLOSE)
case("xptr-id", OPEN("dtd.xml", options=" with validate"), 'set {p} to XMLXPointer "#p2" from d', "XMLGetText p", CLOSE)
case("xptr-id-not-validated", OPEN("dtd.xml"), 'XMLXPointer "#p2" from d', CLOSE)
case("xptr-id-missing", OPEN("dtd.xml", options=" with validate"), 'XMLXPointer "#zz" from d', CLOSE)
case("xptr-other-file", OPEN(), 'set {p} to XMLXPointer "dtd.xml#xpointer(/people/person[1])" from d', "XMLGetText p", CLOSE)
case("xptr-base-url", 'set {p} to XMLXPointer "dtd.xml#xpointer(/people/person[2])" baseURL "file://$FILES/"', "XMLGetText p")
case("xptr-no-read-permission", OPEN(), 'XMLXPointer "latin1.xml#xpointer(/root)" from d without read permission', CLOSE)
case("xptr-namespace", OPEN(), f'XMLXPointer "#xpointer(//dc:creator)" from d namespace {DC}', CLOSE)
case("xptr-invalid", OPEN(), 'XMLXPointer "#xpointer(((" from d', CLOSE)
case("xptr-no-url", 'set d to XMLOpen from string "<a><b>B</b></a>"', 'set {b} to XMLXPointer "#xpointer(/a/b)" from d', "XMLGetText b", CLOSE)
case("xptr-escape", 'XMLEscapeXPointer "it\'s (a) test ^ here"', 'XMLEscapeXPointer "plain"')
case("xptr-get", OPEN(), ROOT, 'XMLGetXPointer (XMLChild r index 2)', 'XMLGetXPointer (XMLChild r index 2) suffix "title"', 'XMLGetXPointer d', CLOSE)

# XSLT
case("xslt-file", OPEN(), f"set t to XMLTransform d with {F('titles.xsl')}", "XMLDisplayXML t", "XMLClose t", CLOSE)
case("xslt-path-string", OPEN(), 'set t to XMLTransform d with "$FILES/titles.xsl"', "XMLDisplayXML t", "XMLClose t", CLOSE)
case("xslt-reference", OPEN(), OPEN("titles.xsl", var="s"), "set t to XMLTransform d with s", "XMLDisplayXML t", "XMLClose t", "XMLClose s", CLOSE)
case("xslt-string", OPEN(), 'set t to XMLTransform d with "<xsl:stylesheet version=\\"1.0\\" xmlns:xsl=\\"http://www.w3.org/1999/XSL/Transform\\"><xsl:template match=\\"/\\"><n><xsl:value-of select=\\"count(//book)\\"/></n></xsl:template></xsl:stylesheet>"', "XMLDisplayXML t", "XMLClose t", CLOSE)
case("xslt-params", OPEN(), f"set t to XMLTransform d with {F('titles.xsl')} xsl params {{\"label\", \"'Books'\"}}", 'XMLGetAttribute (XMLRoot t) name "label"', "XMLClose t", CLOSE)
case("xslt-params-xpath", OPEN(), f"set t to XMLTransform d with {F('titles.xsl')} xsl params {{\"label\", \"count(//book)\"}}", 'XMLGetAttribute (XMLRoot t) name "label"', "XMLClose t", CLOSE)
case("xslt-params-record", OPEN(), f"set t to XMLTransform d with {F('titles.xsl')} xsl params {{label:\"'R'\"}}", 'XMLGetAttribute (XMLRoot t) name "label"', "XMLClose t", CLOSE)
case("xslt-string-params", OPEN(), f"set t to XMLTransform d with {F('titles.xsl')} xsl string params {{\"label\", \"It's\"}}", 'XMLGetAttribute (XMLRoot t) name "label"', "XMLClose t", CLOSE)
case("xslt-as-string", OPEN(), f"XMLTransform d with {F('titles.xsl')} as string", CLOSE)
case("xslt-text-as-string", OPEN(), f"XMLTransform d with {F('text.xsl')} as string", CLOSE)
case("xslt-text-as-reference", OPEN(), f"set t to XMLTransform d with {F('text.xsl')}", "XMLDisplayXML t", CLOSE)
case("xslt-as-plist", OPEN(), f"set p to XMLTransform d with {F('plist.xsl')} as CFRef", "PlistGet p", "PlistClose p", CLOSE)
case("xslt-in-file", OPEN(), f"XMLTransform d with {F('titles.xsl')} in {T('titles-out.xml')}", CLOSE, f"readtext {T('titles-out.xml')}")
case("xslt-in-pool", OPEN(), f'set t to XMLTransform d with {F("titles.xsl")} in pool "mtc-xs"', "GetPool t", "XMLClose t", CLOSE)
case("xslt-node", OPEN(), ROOT, f"set t to XMLTransform (XMLChild r index 2) with {F('titles.xsl')}", "XMLDisplayXML t", "XMLClose t", CLOSE)
case("xslt-processing-instruction", OPEN("with-pi.xml"), "XMLTransform d as string", CLOSE)
case("xslt-no-stylesheet", OPEN(), "XMLTransform d", CLOSE)
case("xslt-invalid", OPEN(), f"XMLTransform d with {F('invalid.xsl')}", CLOSE)
case("xslt-missing-file", OPEN(), f"XMLTransform d with {F('nope.xsl')}", CLOSE)
case("xslt-exslt", OPEN(), f"XMLTransform d with {F('exslt.xsl')} as string", CLOSE)
case("xslt-compile", OPEN(), OPEN("titles.xsl", var="s"), "XMLCompile s", "set t to XMLTransform d with s", 'XMLGetAttribute (XMLRoot t) name "label"', "XMLClose t", "XMLClose s", CLOSE)
case("xslt-result-url", OPEN(), f"set t to XMLTransform d with {F('titles.xsl')}", "XMLURL t", "XMLClose t", CLOSE)

# Indexes
case("index-lookup", 'set d to XMLOpen from string "<a><b name=\'x\'/><b name=\'y\'/><b name=\'x\'/></a>"', 'XMLNewIndex "k" match "//b" use "@name" at d',
     'XMLLookup "x" using "k" at d', 'XMLLookup "y" using "k" at d', 'XMLLookup "z" using "k" at d', "XMLEntries \"k\" at d",
     'XMLEntries "k" at d with duplicate match', 'XMLEntries "k" at d without duplicate match', CLOSE)
case("index-documentation", 'set doc to XMLOpen from string "<a><b name=\'x\'/><b name=\'y\'/></a>"', 'XMLNewIndex "test key" match "//b" use "@name" at doc',
     'set {x} to XMLLookup "x" using "test key" at doc', "XMLDisplayXML x", "XMLClose doc")
case("index-empty", OPEN(), 'XMLNewIndex "k" match "//nothing" use "@id" at d', CLOSE)
case("index-missing", OPEN(), 'XMLLookup "x" using "nope" at d', CLOSE)
case("index-missing-entries", OPEN(), 'XMLEntries "nope" at d', CLOSE)
case("index-at-node", OPEN(), ROOT, 'XMLNewIndex "k" match "book" use "title" at r', 'XMLLookup "Emma" using "k" at r', 'XMLLookup "Moby-Dick" using "k" at d', CLOSE)
case("index-namespace", OPEN(), f'XMLNewIndex "k" match "//book" use "dc:creator" at d namespace {DC}', 'XMLLookup "Victor Hugo" using "k" at d', CLOSE)
case("index-variables", OPEN(), 'XMLNewIndex "k" match "//book[@lang=$l]" use "@id" at d xpath variables {"l", "fr"}', 'XMLEntries "k" at d', CLOSE)
case("index-replace", OPEN(), 'XMLNewIndex "k" match "//book" use "@id" at d', 'XMLNewIndex "k" match "//book" use "@lang" at d', 'XMLEntries "k" at d', CLOSE)
case("index-document", OPEN(), "XMLIndexDocument d", CLOSE)

case("index-order", 'set d to XMLOpen from string "<a><b n=\'m\'/><b n=\'c\'/><b n=\'z\'/><b n=\'a\'/><b n=\'c\'/><b n=\'q\'/></a>"',
     'XMLNewIndex "k" match "//b" use "@n" at d', 'XMLEntries "k" at d', 'XMLLookup "c" using "k" at d', CLOSE)
case("index-remove", OPEN(), 'XMLNewIndex "k" match "//book" use "@id" at d', 'XMLNewIndex "k" match "" use "@id" at d', 'XMLEntries "k" at d', CLOSE)
case("node-path-several", 'set d to XMLOpen from string "<a><!--1--><!--2--><?p x?><b/>t<b/><?p y?></a>"', ROOT,
     "XMLGetNodePath (XMLChild r index 2 with all nodes)", "XMLGetNodePath (XMLChild r index 3 with all nodes)",
     "XMLGetNodePath (XMLChild r index 5 with all nodes)", "XMLGetNodePath (XMLChild r index 7 with all nodes)", CLOSE)
case("node-path-from-other", OPEN(), ROOT, 'XMLGetNodePath (item 1 of (XMLXPath r with "book[2]/year")) from (XMLChild r index 1)', CLOSE)
case("xptr-get-suffix-slash", OPEN(), ROOT, 'XMLGetXPointer (XMLChild r index 2) suffix "/title"', CLOSE)
case("xptr-get-no-url", 'set d to XMLOpen from string "<a><b/></a>"', ROOT, "XMLGetXPointer (XMLChild r index 1)", CLOSE)

# Hidden: XMLStrings, XMLLocalize
case("strings", OPEN(), ROOT, 'XMLStrings (XMLXPath r with "//title/text()")', "XMLStrings (XMLChild r index 1)", CLOSE)

case("localize-text", OPEN(), ROOT, 'set l to XMLXPath r with "//title/text()"',
     f'writetext "\\"Moby-Dick\\" = \\"Moby Dick (fr)\\";" to {T("l.strings")}', f"XMLLocalize l using {T('l.strings')}", "XMLGetText l", CLOSE)
case("localize-element", OPEN(), ROOT, "set b to XMLChild r index 1",
     f'writetext "\\"%1$sMoby-Dick%2$s%3$sHerman Melville%4$s%5$s1851%6$s%7$s9.99%8$s\\" = \\"%3$sHM%4$s%1$sMD%2$s%7$s1%8$s%5$s2%6$s\\";" to {T("e.strings")}',
     f"XMLLocalize b using {T('e.strings')}", "XMLDisplayXML b", CLOSE)
case("strings-nested", 'set d to XMLOpen from string "<a>x<b>y<c>z</c></b><d/>w</a>"', ROOT, "XMLStrings r", CLOSE)

MTC_OSAX_FIXES = {
    "xpath-context-remove": "Satimage: XMLSetContext kept a namespace whose nsurl was \"\" instead of removing it",
    "xpath-functions-exslt-str-replace": "Satimage: str:replace, which the dictionary lists, was an unknown function in XPath",
    "xpath-node-path-from": "Satimage: XMLGetNodePath from a parent put a space before the path",
    "xpath-node-path-from-root": "Satimage: XMLGetNodePath from an ancestor other than the parent ignored from",
    "xptr-get": "Satimage: XMLGetXPointer added the suffix without a /",
    "xpath-context-from-list": "Satimage: XMLXPath of nodes in two documents with xpath variables was error -1",
    "xptr-no-url": "Satimage: XMLXPointer in a document without a URL (from string) was error -1700",
    "xptr-relative": "Satimage: XMLXPointer of a relative xpointer() from an element was error -1",
}
names = {c["name"] for c in cases}
assert MTC_OSAX_FIXES.keys() <= names
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases-xpath.json", "w"), indent=1, ensure_ascii=False)
json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../XMLFixes/cases-xpath.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
