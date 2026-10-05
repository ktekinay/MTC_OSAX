-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the PropertyList suite, and of
-- filter text … into a property list (see Implemented/PLAN-PropertyLists.md). MTC_OSAX only. Run with Scripts/run-e2e.sh plists-fixes.

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & (expected as text) & ", got " & (actual as text)
end check

set p to PlistOpen from string "<plist version=\"1.0\"><dict><key>big</key><integer>1099511627776</integer><key>d</key><dict><key>x</key><integer>1</integer></dict><key>w</key><date>2020-05-17T12:30:00Z</date></dict></plist>"
-- Satimage returned 0 for integers beyond 32 bits.
check("big integer", (PlistGet p key "big"), 1.099511627776E+12)
-- Satimage broke after a path with a trailing slash.
check("trailing slash", (PlistGet p using "d/x/"), 1)
-- Satimage returned nothing for a date in JSON.
check("JSON date", (PlistToJSON (PlistChild p key "w")), "\"2020-05-17T12:30:00Z\"")
-- Satimage returned nothing for a removed element's reference.
set d to PlistChild p key "d"
PlistRemoveChild p key "d"
try
	PlistGet d
	error "removed: no error raised"
on error number n
	check("removed element", n, -1728)
end try
-- Satimage ignored missing values without suppressing.
PlistSet p key {"a", "b"} to {1, missing value} without suppressing
check("kept missing value", (PlistGet p key "b"), missing value)
-- Satimage refused POSIX path strings.
PlistSave p in "/private/tmp/mtc-e2e-fixes.plist"
PlistClose p

-- filter text never worked in Satimage.
set p to PlistNew {z:0}
filter text "^(\\w+)=(.*)$" in ("a=1" & linefeed & "b=2" & linefeed & "a=3") key "\\1" using "\\2" into p
check("filter text into", (PlistGet p key "a"), "1" & linefeed & "3")
PlistClose p

set j to PlistFromJSON "{\"n\": null}"
check("JSON null", (PlistGet j key "n"), missing value)
PlistClose j

"OK: " & checks & " checks passed"
