-- End-to-end checks of the Text Additions commands, using the call shapes from real scripts.
-- Only behavior MTC_OSAX shares with Satimage, so this also runs unchanged against SatimageOSAX (Scripts/parity.sh).
-- Where MTC_OSAX fixes Satimage's bugs, see text-fixes.applescript.
-- Run with Scripts/run-e2e.sh text (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & my show(expected) & ", got " & my show(actual)
end check

on show(value)
	try
		if class of value is list then
			set parts to {}
			repeat with v in value
				set end of parts to my show(contents of v)
			end repeat
			set AppleScript's text item delimiters to ", "
			return "{" & (parts as text) & "}"
		end if
		return value as text
	on error
		return "(" & (class of value as text) & ")"
	end try
end show

set html to "<html><head>" & linefeed & "<TITLE>  Welcome &amp; Hello  </TITLE>" & linefeed & "<script type=\"application/ld+json\">{\"a\": 1}</script>" & linefeed & "</html>"
set ps to "  PID TTY  TIME CMD" & linefeed & "  123 ??   0:01.00 minirosetta_3.14" & linefeed & "  456 ??   0:02.00 Finder" & linefeed & " 7890 ??   0:03.00 minirosetta_3.15"

-- find text
check("ld+json", (find text "<script type=\"application/ld\\+json\">([\\s\\S]*)</script>" in html using "\\1" with regexp and string result), "{\"a\": 1}")
check("ps all", (find text "^ *(\\d+) [^\\r\\n]+minirosetta_\\d+\\.\\d+" in ps using "\\1" with regexp, all occurrences and string result), {"123", "7890"})
check("title", (find text "<title>(?:\\s|[^[:alnum:]'\"])*(.*?)[\\s]*</title>" in html using "\\1" with regexp and string result without case sensitive regexpflag {"MULTILINE"}), "Welcome &amp; Hello")
check("template with return", (find text "on (\\d{4}-\\d{2}-\\d{2}) at (\\d{2}\\.\\d{2})" in "Chat on 2008-03-04 at 12.30.ichat" using ("\\1" & return & "\\2") with regexp and string result), "2008-03-04" & return & "12.30")
set rec to find text "[0-9]+" in "a 2007-12-24 b" with regexp
check("matchPos", matchPos of rec, 2)
check("matchLen", matchLen of rec, 4)
check("matchResult", matchResult of rec, "2007")
check("emoji position", matchPos of (find text "b" in "😀b"), 2)
check("canonical é", matchLen of (find text "é" in ("cafe" & (character id 769))), 2)
check("case insensitive", (find text "FEEDBACK://SHOWREPORT\\?report_id=(\\d+)" in "feedback://showreport?report_id=4567" using "\\1" with regexp and string result without case sensitive), "4567")
check("all occurrences none", (find text "z" in "abc" with all occurrences), {})

try
	find text "z" in "abc"
	error "not found: no error raised"
on error number n
	check("not found error", n, -2763)
end try

-- The Paste URL Into Forum loop: repeat until find text fails.
set r to "see [url=http://x.com/a]here[/url]"
try
	repeat
		set r to find text "\\[url=([^\\]]+)" in r using "\\1" with regexp and string result
	end repeat
end try
check("repeat until not found", r, "http://x.com/a")

-- change
check("return to linefeed", (change return into linefeed in ("a" & return & "b")), "a" & linefeed & "b")
check("crlf", (change "\\r\\n|\\n" into "\\r" in ("a" & return & linefeed & "b" & linefeed & "c") with regexp), "a" & return & "b" & return & "c")
check("trim", (change "\\A\\s+" into "" in (change "\\s+\\z" into "" in ("  abc  " & linefeed) with regexp) with regexp), "abc")
check("href", (change "(<a\\s+[^>]*href=['\"])(?!http)([^'\"]+[\"'])" into ("\\1" & "http://root.com/" & "\\2") in "<a href='page.html'>x</a>" with regexp without case sensitive), "<a href='http://root.com/page.html'>x</a>")
check("list patterns", (change {"e", "o"} into {"E", "O"} in "hello world"), "hEllO wOrld")
check("list input", (change "([0-9]{1,2})/([0-9]{1,2})" into "\\2/\\1" in {"31/12/2007", "29/2/2008"} with regexp), {"12/31/2007", "2/29/2008"})
check("dollar literal", (change "(b)" into "[$1]" in "abc" with regexp), "a[$1]c")

-- simple commands used by real scripts
check("join", (join {"2008", "03", "04"} using "-"), "2008-03-04")
check("join empty", (join {"The site ", "<", "http://x.com", ">"} using ""), "The site <http://x.com>")
check("resolve entities", (resolve entities "&apos;foo&apos; &gt; &#65;"), "'foo' > A")
check("uppercase", (uppercase "straße"), "STRASSE")
check("titlecase", (titlecase "hello-world"), "Hello-World")
check("atoi hex", (atoi "0xa0"), 160)
check("atof comma", (atof "1,5"), 1.5)
check("escapeURL", (escapeURL "a b#"), "a%20b%23")
check("hash", (hash "abc"), 12885873)

-- files (in /private/tmp, which needs no privacy permission)
set f to POSIX file "/private/tmp/mtc-e2e-text.txt"
writetext ("alpha beta" & linefeed & "é alpha" & linefeed) to f
check("readtext", (readtext f), "alpha beta" & linefeed & "é alpha" & linefeed)
check("readtext for", (readtext f for 5), "alpha")
check("find text in file", matchPos of (find text "alpha" in f starting at 12), 13)
check("change in file count", (change "alpha" into "ALPHA" in f), 2)
check("file changed", (readtext f), "ALPHA beta" & linefeed & "é ALPHA" & linefeed)
writetext "!" to f with append
check("append", (readtext f starting at 0 for 3), "ALP")
writetext "é" to f encoding "UTF-16"
check("utf-16 round trip", (readtext f), "é")

-- format
check("format", (format pi into "##.##"), "3.14")
check("format grouping", (format 1234567.891 into "#,##0.00"), "1,234,567.89")
check("format sections", (format -5 into "#;(#)"), "(5)")
check("format scientific", (format 12345 into "0.0E+0"), "1.2E+4")

-- printf, strftime, strptime (independent of the Mac's time zone)
check("printf", (printf "The %2$s %1$s: " parameters {"car", "red"}) & (printf "%05.1f%%" parameters {12.345}), "The red car: 012.3%")
try
	printf "%2$s %05.1f" parameters {"car", "red", 12.345}
	error "printf mixed: no error raised"
on error number n
	check("printf mixed positional error", n, 10)
end try
check("printf lists", (printf "%d;" parameters {{1, 2, 3}}), "1;2;3;")
set d to strptime "2007-01-15T16:10:56" encoding "%FT%T"
check("strptime/strftime", (strftime d into "%F %T"), "2007-01-15 16:10:56")
check("strftime GMT round trip", (strftime (strptime "2007-01-15T16:10:56Z" encoding "%FT%T" with GMT) into "%FT%TZ" with GMT), "2007-01-15T16:10:56Z")
check("strptime as real", (strptime "2001-01-01T00:00:00" encoding "%FT%T" as real with GMT), 0.0)

-- splittext
check("split literal", (splittext "a-b-c" using "-"), {"a", "b", "c"})
check("split regexp ci", (splittext "x<P class=\"Body\">y" using "<p\\s+class=\"Body\">" with regexp without case sensitive), {"x", "y"})
check("split not found", (splittext "abc" using "-"), {"abc"})

-- re_compile
check("re_compile", (re_compile "a(b)c"), "a(b)c")
try
	re_compile "a(b"
	error "re_compile: no error raised"
on error number n
	check("re_compile error", n, -117)
end try

"OK: " & checks & " checks passed"
