-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the XML XPath, XSLT suite (see
-- PLAN-XML.md). MTC_OSAX only. Run with Scripts/run-e2e.sh xml-xpath-fixes (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & (expected as text) & ", got " & (actual as text)
end check

set d to XMLOpen from string "<library xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><book id=\"b1\"><title>Moby-Dick</title><dc:creator>Melville</dc:creator></book><book id=\"b2\"><title>Les Misérables</title><year>1862</year></book></library>"
set r to XMLRoot d

-- XPointers in a document without a URL, and relative to an element
set {b} to XMLXPointer "#xpointer(/library/book[2])" from d
check("no URL", XMLGetAttribute b name "id", "b2")
set {t} to XMLXPointer "#xpointer(title)" from b
check("relative", XMLGetText t, "Les Misérables")

-- Node paths from any ancestor, without a leading space
set {y} to XMLXPath r with "book[2]/year"
check("from parent", XMLGetNodePath y from b, "year[1]")
check("from root", XMLGetNodePath y from r, "book[2]/year[1]")
check("from elsewhere", XMLGetNodePath y from (XMLChild r index 1), "xpointer(/library[1]/book[2]/year[1])")

-- The suffix is a further step
check("suffix", XMLGetXPointer b suffix "title", "#xpointer(/library[1]/book[2]/title)")

-- An empty nsurl removes a namespace from the context
XMLSetContext d namespace {{nsprefix:"dc", nsurl:"http://purl.org/dc/elements/1.1/"}}
check("declared", XMLGetText (XMLXPath r with "book/dc:creator"), {"Melville"})
XMLSetContext d namespace {{nsprefix:"dc", nsurl:""}}
check("removed", namespace of (XMLGetContext d), {})
try
	XMLXPath r with "book/dc:creator"
	error "removed prefix: no error raised"
on error number n
	check("removed prefix", n, 3)
end try

-- str:replace in XPath
XMLSetContext d namespace {{nsprefix:"str", nsurl:"http://exslt.org/strings"}}
check("replace", XMLXPath r with "str:replace(string(book[1]/title), 'Dick', 'Duck')", "Moby-Duck")

-- Variables for nodes in two documents
set e to XMLOpen from string "<a/>"
check("two documents", XMLXPath {r, XMLRoot e} with "$v" xpath variables {"v", 1}, {1, 1})
XMLClose e

XMLClose d
"OK: " & checks & " checks passed"
