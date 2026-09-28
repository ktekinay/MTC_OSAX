-- End-to-end checks of the XML DOM and XML Documents suites, in /private/tmp (no privacy prompts), including the
-- "KML To Excel" script's calls. Only behavior shared with Satimage, so this also runs against SatimageOSAX
-- (Scripts/parity.sh). Run with Scripts/run-e2e.sh xml.

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0
property kmlPath : "/private/tmp/mtc-e2e-places.kml"

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & my show(expected) & ", got " & my show(actual)
end check

on show(value)
	try
		set AppleScript's text item delimiters to ", "
		return value as text
	on error
		return "(" & (class of value as text) & ")"
	end try
end show

-- A KML file, read as the "KML To Excel" script does.
set kml to "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>Places</name>
<Placemark><name>Home</name><description>Where I live</description><styleUrl>#icon</styleUrl><Point><coordinates>-73.9857,40.7484,0</coordinates></Point></Placemark>
<Placemark><name>Work</name><description>The office</description><styleUrl>#icon</styleUrl><Point><coordinates>-74.0060,40.7128,0</coordinates></Point></Placemark>
</Document></kml>"
set xmlTop to XMLOpen from string kml
XMLSave xmlTop in (POSIX file kmlPath)
XMLClose xmlTop

set theFile to POSIX file kmlPath
set nameList to {}
set descList to {}
set coordList to {}
set xmlTop to XMLOpen theFile
set xml to XMLChild xmlTop index 1
set xml to XMLChild xml index 1
set cnt to XMLCount xml
set xml to XMLFind xml name "Placemark"
repeat
	set node to XMLChild xml index 1
	set end of nameList to XMLGetText node
	set node to XMLChild xml index 2
	set end of descList to XMLGetText node
	set pointNode to XMLChild xml index 4
	set node to XMLChild pointNode index 1
	set end of coordList to XMLGetText node
	try
		set xml to XMLNextSibling xml
	on error
		exit repeat
	end try
end repeat
XMLClose xmlTop
check("KML count", cnt, 3)
check("KML names", nameList, {"Home", "Work"})
check("KML descriptions", descList, {"Where I live", "The office"})
check("KML coordinates", item 2 of coordList, "-74.0060,40.7128,0")

-- Reading
set d to XMLOpen from string "<library version=\"2\"><book id=\"b1\"><title>Moby-Dick</title><year>1851</year></book><book id=\"b2\"><title>Emma</title></book><!-- end --></library>"
set r to XMLRoot d
check("tag name", XMLTagName r, "library")
check("count", XMLCount r, 3)
check("count elements", XMLCountElement r, 2)
set b to XMLChild r index 1
check("attribute", XMLGetAttribute b name "id", "b1")
check("text", XMLGetText (XMLFind b name "title"), "Moby-Dick")
check("find attribute", XMLGetAttribute (XMLFind r key "id" value "b2") name "id", "b2")
check("find all", count (XMLFind r name "book" with all occurrences), 2)
check("find text", XMLTagName (XMLParent (XMLFindText "Emma" in r)), "title")
check("node info", kind of (XMLNodeInfo b), "ELEMENT_NODE")
check("display", (XMLDisplayXML b without formatting), "<book id=\"b1\"><title>Moby-Dick</title><year>1851</year></book>")
try
	XMLChild r index 9
	error "child 9: no error raised"
on error number n
	check("child out of range", n, -1719)
end try

-- Changing
XMLSetAttribute b name "lang" to "en"
check("set attribute", XMLGetAttribute b name "lang", "en")
set c to XMLNewChild "<isbn>123</isbn>" at b
check("new child", XMLGetText c, "123")
XMLSetText (XMLFind b name "year") to "1852"
check("set text", XMLGetText (XMLFind b name "year"), "1852")
XMLRemove (XMLChild r index 2)
check("removed", XMLCountElement r, 1)
check("changed", (XMLDisplayXML r without formatting), "<library version=\"2\"><book id=\"b1\" lang=\"en\"><title>Moby-Dick</title><year>1852</year><isbn>123</isbn></book><!-- end --></library>")

-- Namespaces
set n to XMLOpen from string "<r xmlns=\"urn:d\" xmlns:a=\"urn:a\"><a:x/></r>"
check("namespace", nsurl of (XMLGetNameSpace (XMLChild (XMLRoot n) index 1)), "urn:a")
check("namespace from prefix", XMLGetNameSpaceFromPrefix (XMLRoot n) prefix "a", "urn:a")
XMLClose n

-- Documents
check("encoding", XMLGetEncoding d, "UTF-8")
XMLSave d in (POSIX file "/private/tmp/mtc-e2e-library.xml")
check("url", XMLURL d, "/private/tmp/mtc-e2e-library.xml")
set e to XMLCloneDocument d
check("clone", XMLTagName (XMLRoot e), "library")
XMLClose e
check("c14n", (XMLc14n d without comments), "<library version=\"2\"><book id=\"b1\" lang=\"en\"><title>Moby-Dick</title><year>1852</year><isbn>123</isbn></book></library>")
XMLSetDocID d to "e2e"
check("doc by ID", XMLTagName (XMLRoot (XMLGetDocByID "e2e")), "library")
XMLClose d
try
	XMLTagName r
	error "closed: no error raised"
on error number n
	check("closed", n, -1728)
end try

"OK: " & checks & " checks passed"
