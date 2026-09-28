-- End-to-end checks of the XML Validation suite, in /private/tmp (no privacy prompts). Only behavior shared with
-- Satimage, so this also runs against SatimageOSAX (Scripts/parity.sh). Run with Scripts/run-e2e.sh xml-validation.

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

set folder to "/private/tmp/mtc-e2e-valid-"
writetext "<!ELEMENT people (person*)>
<!ELEMENT person (#PCDATA)>
<!ATTLIST person id ID #REQUIRED>
" to (POSIX file (folder & "people.dtd"))
writetext "<?xml version=\"1.0\"?>
<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\"><xs:element name=\"people\"><xs:complexType><xs:sequence><xs:element name=\"person\" maxOccurs=\"unbounded\"><xs:complexType><xs:simpleContent><xs:extension base=\"xs:string\"><xs:attribute name=\"id\" type=\"xs:ID\" use=\"required\"/></xs:extension></xs:simpleContent></xs:complexType></xs:element></xs:sequence></xs:complexType></xs:element></xs:schema>
" to (POSIX file (folder & "people.xsd"))
writetext "<?xml version=\"1.0\"?>
<element name=\"people\" xmlns=\"http://relaxng.org/ns/structure/1.0\"><zeroOrMore><element name=\"person\"><attribute name=\"id\"><text/></attribute><text/></element></zeroOrMore></element>
" to (POSIX file (folder & "people.rng"))
writetext "<?xml version=\"1.0\"?>
<!DOCTYPE people SYSTEM \"mtc-e2e-valid-people.dtd\">
<people><person id=\"p1\">Ann</person><person id=\"p2\">Bob</person></people>
" to (POSIX file (folder & "people.xml"))
writetext "<?xml version=\"1.0\"?>
<people><person>Ann</person><extra/></people>
" to (POSIX file (folder & "bad.xml"))

-- DTDs
set d to XMLOpen (POSIX file (folder & "people.xml"))
XMLValidate d
set b to XMLOpen (POSIX file (folder & "bad.xml"))
try
	XMLValidate b against (POSIX file (folder & "people.dtd"))
	error "invalid: no error raised"
on error number n
	check("invalid", n, 504)
end try
check("messages", (XMLError) contains "No declaration for element extra", true)
try
	XMLValidate b
	error "no DTD: no error raised"
on error number n
	check("no DTD", n, 522)
end try
XMLCheckDTD (POSIX file (folder & "people.dtd"))
XMLCheckDTD "<!ELEMENT a (b)><!ELEMENT b EMPTY>"
try
	XMLCheckDTD "<!ELEMENT a (b>"
	error "bad DTD: no error raised"
on error number n
	check("bad DTD", n, 55)
end try

-- Schemas
XMLSchema d with respect to (POSIX file (folder & "people.xsd"))
try
	XMLSchema b with respect to (POSIX file (folder & "people.xsd"))
	error "schema: no error raised"
on error number n
	check("schema", n, 1868)
end try
XMLSchema with respect to (POSIX file (folder & "people.xsd"))
XMLRelaxNG d with respect to (POSIX file (folder & "people.rng"))
try
	XMLRelaxNG b with respect to (POSIX file (folder & "people.rng"))
	error "relaxng: no error raised"
on error number n
	check("relaxng", n, 24)
end try

-- IDs and names
set x to XMLOpen from string "<doc><sec xml:id=\"s1\">One</sec><sec xml:id=\"s2\">Two</sec></doc>"
check("by ID", XMLGetText (XMLGetByID x xmlid "s2"), "Two")
check("xml:id", XMLGetxmlID (XMLChild (XMLRoot x) index 1), "s1")
check("DTD ID", XMLGetText (XMLGetByID d xmlid "p2"), "Bob")
check("name", XMLValidName {"a:b", "é"}, true)
check("NCName", XMLValidNCName "a-b", true)
check("du", XMLDu x, "/
doc
	sec
	sec
")
XMLClose x
XMLClose b
XMLClose d
"OK: " & checks & " checks passed"
