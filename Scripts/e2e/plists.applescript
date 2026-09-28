-- End-to-end checks of the PropertyList and Pool suites, in /private/tmp (no privacy prompts), including the
-- patterns of the scripts in ~/Documents/AppleScript Projects. Only behavior shared with Satimage, so this also runs
-- against SatimageOSAX (Scripts/parity.sh). Run with Scripts/run-e2e.sh plists.

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0
property prefFilePath : "/private/tmp/mtc-e2e-prefs.plist"

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

-- Like "Email Web Page": create a preferences file, then read and update it.
set prefFileRef to PlistNew
PlistSet prefFileRef key "String_Utils_Script_Path" to "/Users/me/Scripts/String Utils.scpt"
PlistSave prefFileRef in (POSIX file prefFilePath)
PlistClose prefFileRef
set prefFileRef to PlistOpen (POSIX file prefFilePath as alias)
check("read preference", (PlistGet prefFileRef key "String_Utils_Script_Path"), "/Users/me/Scripts/String Utils.scpt")
PlistSet prefFileRef key "String_Utils_Script_Path" to "/new/path.scpt"
PlistSave prefFileRef
PlistClose prefFileRef
set prefFileRef to PlistOpen (POSIX file prefFilePath)
check("updated preference", (PlistGet prefFileRef key "String_Utils_Script_Path"), "/new/path.scpt")
PlistClose prefFileRef

-- Like "Report to SpamCop": a list of records.
set p to PlistNew {MessageList:{{|id|:1, subject:"Hi"}, {|id|:2, subject:"Spam"}}}
set msgRecs to PlistGet p key "MessageList"
check("records", count msgRecs, 2)
check("record value", subject of item 2 of msgRecs, "Spam")
PlistClose p

-- Children, paths, types
set p to PlistNew {a:1, l:{"x", "y"}, d:{e:2.5, f:{g:"deep"}}}
check("type", (PlistType p), "dictionary")
check("count", (PlistCount p), 3)
check("keys", (PlistGetKeys p), {"a", "d", "l"})
check("path", (PlistGet p using "d/f/g"), "deep")
check("path index", (PlistGet p using "l[2]"), "y")
set l to PlistChild p key "l"
check("child type", (PlistType l), "array")
check("child index", (PlistGet l index 1), "x")
try
	PlistGet p key "nope"
	error "missing key: no error raised"
on error number n
	check("missing key", n, -1728)
end try

-- Changes
PlistSet p key "b" to {true, false}
PlistSet l index 3 to "z"
set c to PlistNewChild "w" at l index 1
check("new child", (PlistGet c), "w")
check("array", (PlistGet l), {"w", "x", "y", "z"})
PlistRemoveChild l index 1
check("removed", (PlistCount l), 3)
check("exist", (PlistExist "y" in l), {2})
PlistAdd {"q"} after l
check("added", (PlistGet l index 4), "q")
check("xml", (PlistGetXML (PlistChild p key "b")) contains "<array>", true)
check("json", (PlistToJSON (PlistChild p key "d")), "{\"e\":2.5,\"f\":{\"g\":\"deep\"}}")
PlistClose p

set j to PlistFromJSON "{\"n\": 3, \"t\": \"x\"}"
check("from JSON", (PlistGet j key "n"), 3.0)
PlistClose j

-- Pools and IDs
set old to SetPool "mtc-e2e"
set p to PlistNew {a:1}
check("pool", (GetPool p), "mtc-e2e")
PlistSetDocID p to "e2e"
check("doc by ID", (PlistCount (PlistGetDocByID "e2e")), 1)
SetPool old
DeletePool "mtc-e2e"
try
	PlistGet p
	error "deleted pool: no error raised"
on error number n
	check("deleted pool", n, -1728)
end try

"OK: " & checks & " checks passed"
