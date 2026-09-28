-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the XML DOM and Documents suites
-- (see Implemented/PLAN-XML.md). MTC_OSAX only. Run with Scripts/run-e2e.sh xml-fixes (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & (expected as text) & ", got " & (actual as text)
end check

set d to XMLOpen from string "<a><b>one<i/>two</b></a>"
set r to XMLRoot d
set b to XMLChild r index 1

-- Satimage: XMLExists of an invalid reference was error -1728.
set t to XMLChild b index 1
XMLRemove t
check("exists removed", XMLExists t, false)

-- Satimage crashed appending text to an element with mixed content.
XMLAppendText "!" at b
check("append to mixed", XMLGetText b, "two!")

-- Satimage left the document unreadable after XMLSetXML of a text node.
set t to XMLChild b index 2
XMLSetXML t to "<j/> three"
check("set XML of text", (XMLDisplayXML r without formatting), "<a><b><i/><j/> three</b></a>")

-- Satimage: XMLError returned stale text after a successful command.
XMLClose (XMLOpen from string "<ok/>")
check("no error", XMLError, "")

-- Satimage: error 1535 for a POSIX path string.
XMLSave d in "/private/tmp/mtc-e2e-xml-fixes.xml"
check("saved", XMLURL d, "/private/tmp/mtc-e2e-xml-fixes.xml")
XMLClose d
check("closed", XMLExists d, false)

"OK: " & checks & " checks passed"
