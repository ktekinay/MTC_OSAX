-- End-to-end checks of `syntax "PCRE"`, MTC_OSAX's PCRE2 regex engine (see Implemented/PLAN-PCRE.md). MTC_OSAX only.
-- Run with Scripts/run-e2e.sh text-pcre (through iTerm).

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

set someLines to "one" & linefeed & "two" & return & linefeed & "three"

-- ^ and $ at every line, unless the pattern or the call says otherwise
check("lines", find text "^\\w+$" in someLines with regexp, all occurrences and string result syntax "PCRE", {"one", "two", "three"})
check("(?-m)", find text "(?-m)^\\w+" in someLines with regexp, all occurrences and string result syntax "PCRE", {"one"})
check("SINGLELINE", find text "^\\w+" in someLines with regexp, all occurrences and string result syntax "PCRE" regexpflag {"SINGLELINE"}, {"one"})

-- PCRE's own features
check("\\h", find text "\\h+" in "x " & tab & " y" with regexp and string result syntax "PCRE", " " & tab & " ")
check("unicode \\w", find text "\\w+" in "café naïve" with regexp, all occurrences and string result syntax "PCRE", {"café", "naïve"})
check("lookbehind", find text "(?<=\\$)\\d+" in "cost $42" with regexp and string result syntax "PCRE", "42")
check("recursion", find text "\\((?:[^()]|(?R))*\\)" in "x(a(b)c)y" with regexp and string result syntax "PCRE", "(a(b)c)")
check("DOTALL", find text "a.b" in "a" & linefeed & "b" with regexp and string result syntax "PCRE" regexpflag {"DOTALL"}, "a" & linefeed & "b")
check("position", matchPos of (find text "b+" in "😀bb" with regexp syntax "PCRE"), 2)

-- The other commands
check("change", change "(?<user>\\w+)@(\\w+)" into "\\2 at \\k<user>" in "me@home" with regexp syntax "PCRE", "home at me")
check("change dollars", change "(\\w+)@(\\w+)" into "$2:$1" in "me@home" with regexp and dollar references syntax "PCRE", "home:me")
check("splittext", splittext "a1b22c" using "\\d+" with regexp syntax "PCRE", {"a", "b", "c"})
check("filter text", (filter text "^(\\w+) is (.*)$" in "John is ten" key "\\1" using "\\2" syntax "PCRE") contains "<key>John</key>", true)
check("re_compile", re_compile "a++b" syntax "PCRE", "a++b")
try
	re_compile "(unclosed" syntax "PCRE"
	error "re_compile: no error raised"
on error message number n
	check("error number", n, -3114)
	check("error message", message contains "missing closing parenthesis", true)
end try

-- Without syntax "PCRE", Satimage's Onigmo as before
check("RUBY \\h is a hex digit", find text "\\h" in "x a" with regexp and string result, "a")

"OK: " & checks & " checks passed"
