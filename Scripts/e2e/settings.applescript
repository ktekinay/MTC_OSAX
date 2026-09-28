-- End-to-end checks of the settings commands (see Implemented/PLAN-Settings.md). MTC_OSAX only. The settings are saved first
-- and put back at the end. Run with Scripts/run-e2e.sh settings (through iTerm).

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

on errorNumber(settingName, newValue)
	try
		mtc_set settingName to newValue
	on error number n
		return n
	end try
	return 0
end errorNumber

set saved to mtc_get all_settings
try
	mtc_reset all_settings
	check("default idle timeout", mtc_get idle_timeout, 3600)
	check("default dollar references", mtc_get dollar_references, false)
	check("default regex syntax", mtc_get regex_syntax, "RUBY")

	-- Changes apply from the next command
	mtc_set regex_syntax to "pcre"
	check("normalized", mtc_get regex_syntax, "PCRE")
	check("PCRE by default", (find text "\\h+" in "x y" with regexp and string result), " ")
	mtc_set dollar_references to true
	check("dollar references by default", (change "(b)" into "[$1]" in "abc" with regexp), "a[b]c")
	mtc_set idle_timeout to 600

	-- Text names
	check("friendly name", mtc_get "regex syntax", "PCRE")
	check("defaults key", mtc_get "IdleTimeoutSeconds", 600)

	-- Every setting
	set infos to mtc_get "All Settings"
	check("count", count infos, 3)
	check("names", {name of item 1 of infos, name of item 2 of infos, name of item 3 of infos}, {idle_timeout, dollar_references, regex_syntax})
	check("a name goes back to mtc_get", mtc_get (name of item 3 of infos), "PCRE")
	check("is default", is default of item 1 of infos, false)
	check("key", key of item 2 of infos, "DollarReferences")

	-- Errors
	check("missing value", errorNumber(regex_syntax, missing value), -1700)
	check("negative", errorNumber(idle_timeout, -1), -50)
	check("unknown syntax", errorNumber(regex_syntax, "NOPE"), -50)
	check("unknown setting", errorNumber("nope", 1), -1728)

	-- Reset
	mtc_reset regex_syntax
	check("reset one", mtc_get regex_syntax, "RUBY")
	mtc_reset all_settings
	check("reset all", {mtc_get idle_timeout, mtc_get dollar_references}, {3600, false})
on error message number n
	set failure to {message, n}
end try

-- Put the settings back as they were.
repeat with info in saved
	if is default of info then
		mtc_reset (name of info)
	else
		mtc_set (name of info) to (value of info)
	end if
end repeat
try
	error (item 1 of failure) number (item 2 of failure)
end try
"OK: " & checks & " checks passed"
