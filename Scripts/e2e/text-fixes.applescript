-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken (see Implemented/PLAN-TextAdditions.md,
-- "Fixing Satimage's bugs"). MTC_OSAX only: these fail against SatimageOSAX by design.
-- Run with Scripts/run-e2e.sh text-fixes (through iTerm).

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

-- files
set f to POSIX file "/private/tmp/mtc-e2e-fixes.txt"
writetext "0123456789abcdefé123" to "/private/tmp/mtc-e2e-fixes.txt" -- POSIX path string
check("file offset", (file offset "abc" in f), 10)
check("file offset inclusive", (file offset "abc" in f with inclusive), 13)
check("readtext starting at, no for", (readtext f starting at 16), "é123")
try
	file offset "zzz" in f
	error "file offset: no error raised"
on error number n
	check("file offset not found", n, -2763)
end try

-- filter text
set people to "John is ten" & linefeed & "Anna is twelve" & linefeed & "John is at school"
set plist to filter text "^([A-z]+) is (.*)" in people key "\\1" using "\\2" separator ", "
check("filter text", (plist contains "<key>John</key>" & linefeed & tab & "<string>ten, at school</string>"), true)

-- format
check("format three sections", (format 0 into "+#;-#;'zero'"), "zero")
check("format caret", (format pi into "^##.##"), " 3.14")
check("format underflow", (format 1.0E-4 into "#.##" with underflow test), "1E-04")
try
	format 2.5 into "##^##"
	error "format invalid: no error raised"
on error number n
	check("format invalid", n, -50)
end try

-- dates before 1900, printf %c, templates, entities, atoi
check("strptime 1850", (strftime (strptime "1850-06-01" encoding "%Y-%m-%d") into "%F"), "1850-06-01")
check("printf %c", (printf "%c%c" parameters {72, "i"}), "Hi")
check("k<name>", (change "a(?<n>b)" into "[\\k<n>]" in "abc" with regexp), "[b]c")
check("only backreference unmatched", (change "a(x)?c" into "X" in "ac axc" with regexp only backreference 1), "ac aXc")
check("resolve entities", (resolve entities "&#X42;&#;"), "B&#;")
check("atoi signed hex", (atoi "-0x10"), -16)

"OK: " & checks & " checks passed"
