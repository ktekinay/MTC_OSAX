-- End-to-end checks of the XML XPath, XSLT suite, in /private/tmp (no privacy prompts), including the dictionary's
-- examples. Only behavior shared with Satimage, so this also runs against SatimageOSAX (Scripts/parity.sh). Run
-- with Scripts/run-e2e.sh xml-xpath.

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

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

set table to "<PERIODIC_TABLE xmlns:x=\"urn:x\">
<ATOM STATE=\"GAS\"><NAME>Hydrogen</NAME><SYMBOL>H</SYMBOL><ATOMIC_NUMBER>1</ATOMIC_NUMBER><ATOMIC_WEIGHT>1.00794</ATOMIC_WEIGHT></ATOM>
<ATOM STATE=\"SOLID\"><NAME>Carbon</NAME><SYMBOL>C</SYMBOL><ATOMIC_NUMBER>6</ATOMIC_NUMBER><ATOMIC_WEIGHT>12.011</ATOMIC_WEIGHT></ATOM>
<ATOM STATE=\"GAS\"><NAME>Oxygen</NAME><SYMBOL>O</SYMBOL><ATOMIC_NUMBER>8</ATOMIC_NUMBER><ATOMIC_WEIGHT>15.9994</ATOMIC_WEIGHT></ATOM>
<ATOM STATE=\"GAS\"><NAME>Neon</NAME><SYMBOL>Ne</SYMBOL><ATOMIC_NUMBER>10</ATOMIC_NUMBER><ATOMIC_WEIGHT>20.1797</ATOMIC_WEIGHT></ATOM>
</PERIODIC_TABLE>"
set the_doc to XMLOpen from string table
set the_root to XMLRoot the_doc

-- XMLXPath, as in the dictionary
set {the_weight} to XMLXPath the_root with "ATOM[NAME='Oxygen']/ATOMIC_WEIGHT"
check("weight", XMLGetText the_weight, "15.9994")
check("string", XMLXPath the_root with "string(ATOM[NAME='Oxygen']/ATOMIC_WEIGHT)", "15.9994")
check("variable", XMLXPath the_root with "string(ATOM[NAME=$s]/ATOMIC_WEIGHT)" xpath variables {s:"Oxygen"}, "15.9994")
check("attribute test", XMLGetText (XMLXPath the_root with "*[@STATE='GAS']/NAME"), {"Hydrogen", "Oxygen", "Neon"})
check("count", XMLXPath the_root with "count(ATOM)", 4)
check("number", XMLXPath the_root with "sum(ATOM/ATOMIC_NUMBER) div 2", 12.5)
check("boolean", XMLXPath the_root with "count(ATOM) > 3", true)
check("none", XMLXPath the_root with "ATOM[SYMBOL='Sl']", {})
try
	XMLXPath the_root with "ATOM["
	error "syntax error: no error raised"
on error number n
	check("syntax error", n, 1207)
end try
XMLSetContext the_doc namespace {nsprefix:"math", nsurl:"http://exslt.org/math"}
check("exslt math", XMLGetText (XMLXPath the_doc with "//ATOM[math:abs(number(ATOMIC_NUMBER[1])-8)<3]/NAME"), {"Carbon", "Oxygen", "Neon"})
XMLSetContext the_doc namespace {nsprefix:"fn", nsurl:"http://www.w3.org/2005/xpath-functions"} xpath variables {"v", "Carbon"}
set x to item -1 of (XMLXPath the_root with "ATOM[fn:compare(NAME,'Nitrogen')<0]")
check("compare", XMLGetText (XMLFind x name "NAME"), "Neon")
check("context variable", XMLXPath the_root with "string(ATOM[NAME=$v]/SYMBOL)", "C")
check("context", xpath variables of (XMLGetContext the_doc), {{"s", "Oxygen"}, {"v", "Carbon"}})
set a to item 1 of (XMLXPath the_root with "ATOM/@STATE")
check("attribute node", {XMLGetText a, XMLTagName a, kind of (XMLNodeInfo a)}, {"GAS", "STATE", "ATTRIBUTE_NODE"})

-- Paths and XPointers
check("node path", XMLGetNodePath the_weight, "xpointer(/PERIODIC_TABLE[1]/ATOM[3]/ATOMIC_WEIGHT[1])")
-- (SatimageOSAX only resolved XPointers in documents opened from a file or URL.)
XMLSave the_doc in (POSIX file "/private/tmp/mtc-e2e-table.xml")
set saved to XMLOpen (POSIX file "/private/tmp/mtc-e2e-table.xml")
set {the_atom} to XMLXPointer "#xpointer(/PERIODIC_TABLE/ATOM[NAME='Oxygen'])" from saved
check("xpointer", XMLGetText (XMLFind the_atom name "SYMBOL"), "O")
check("escape", XMLEscapeXPointer "f(x) ^ 2", "f^(x^) ^^ 2")
check("xpointer text", XMLGetXPointer the_atom, "file:///private/tmp/mtc-e2e-table.xml#xpointer(/PERIODIC_TABLE[1]/ATOM[3])")
XMLClose saved

-- Indexes, as in the dictionary
set doc to XMLOpen from string "<a><b name='x'/><b name='y'/></a>"
XMLNewIndex "test key" match "//b" use "@name" at doc
set {x} to XMLLookup "x" using "test key" at doc
check("lookup", XMLDisplayXML x, "<b name=\"x\"/>")
check("entries", XMLEntries "test key" at doc, {"y", "x"})
XMLClose doc
set doc to XMLOpen from string "<plist><dict><key>CFBundleIdentifier</key><string>com.example.app</string><key>CFBundleName</key><string>Example</string></dict></plist>"
XMLNewIndex "dict" match "/plist/dict/*[name()!='key']" use "preceding-sibling::key[1]" at doc
set {x} to XMLLookup "CFBundleIdentifier" using "dict" at doc
check("plist index", XMLGetText x, "com.example.app")
XMLClose doc

-- XSLT
set xsl to "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\"><xsl:param name=\"state\" select=\"'GAS'\"/><xsl:output method=\"text\"/><xsl:template match=\"/\"><xsl:for-each select=\"//ATOM[@STATE=$state]\"><xsl:value-of select=\"SYMBOL\"/>;</xsl:for-each></xsl:template></xsl:stylesheet>"
check("transform", XMLTransform the_doc with xsl as string, "H;O;Ne;")
check("xsl params", XMLTransform the_doc with xsl xsl params {"state", "'SOLID'"} as string, "C;")
check("xsl string params", XMLTransform the_doc with xsl xsl string params {"state", "SOLID"} as string, "C;")
set t to XMLTransform the_doc with "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\"><xsl:template match=\"/\"><n><xsl:value-of select=\"count(//ATOM)\"/></n></xsl:template></xsl:stylesheet>"
check("result document", XMLDisplayXML (XMLRoot t), "<n>4</n>")
XMLClose t
XMLTransform the_doc with xsl in (POSIX file "/private/tmp/mtc-e2e-symbols.txt")
check("in file", readtext (POSIX file "/private/tmp/mtc-e2e-symbols.txt"), "H;O;Ne;")

XMLClose the_doc
"OK: " & checks & " checks passed"
