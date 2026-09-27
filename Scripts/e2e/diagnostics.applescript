-- End-to-end checks of the hidden diagnostics commands, sent to the running app.
-- Run with Scripts/run-e2e.sh (through iTerm, which has Automation permission).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & my show(expected) & ", got " & my show(actual)
end check

on show(value)
	try
		return value as text
	on error
		return "(" & (class of value as text) & ")"
	end try
end show

check("ping", mtc_ping, "pong")
check("version", (mtc_version) starts with "MTC_OSAX ", true)

check("echo text", mtc_echo "abc déf", "abc déf")
check("echo integer", mtc_echo 42, 42)
check("echo real", mtc_echo 1.5, 1.5)
check("echo boolean", mtc_echo true, true)
check("echo list", mtc_echo {1, "a", {2, 3}}, {1, "a", {2, 3}})
check("echo record", mtc_echo {name:"x", size:3}, {name:"x", size:3})
check("echo user record", mtc_echo {foo:"bar"}, {foo:"bar"})
check("echo missing value", mtc_echo missing value, missing value)

check("describe text", mtc_describe "a", "utxt \"a\"")
check("describe list", mtc_describe {1, 2.5}, "list [long 1, doub 2.5]")
check("describe nothing", mtc_describe, "(no direct parameter)")

try
	mtc_raise_error "boom" number 42
	error "raise_error with message: no error raised"
on error message number n
	check("raise_error number", n, 42)
	check("raise_error message", message, "boom")
end try

try
	mtc_raise_error number -1728
	error "raise_error without message: no error raised"
on error number n
	check("raise_error standard number", n, -1728)
end try

"OK: " & checks & " checks passed"
