-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the XML Validation suite (see
-- Implemented/PLAN-XML.md). MTC_OSAX only. Run with Scripts/run-e2e.sh xml-validation-fixes (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & (expected as text) & ", got " & (actual as text)
end check

set d to XMLOpen from string "<!DOCTYPE people [<!ELEMENT people (person*)><!ELEMENT person (#PCDATA)><!ATTLIST person id ID #REQUIRED>]><people><person id=\"p1\">Ann</person><person id=\"p2\">Bob</person></people>"
set r to XMLRoot d

-- An element with IDs validates
XMLValidate r
XMLValidate (XMLChild r index 1)
check("element", XMLError, "")

-- XMLError after a validation that failed, then one that succeeded
set b to XMLOpen from string "<people><extra/></people>"
try
	XMLValidate b
end try
check("failed", XMLError, "no DTD found!

")
XMLValidate d
check("succeeded", XMLError, "")
XMLClose b

-- Names: false, not an error
check("name", XMLValidName "1abc", false)
check("NCName", XMLValidNCName "a:b", false)
check("names", XMLValidName {"a", "1"}, false)
check("valid names", XMLValidName {"a", "b"}, true)

XMLClose d
"OK: " & checks & " checks passed"
