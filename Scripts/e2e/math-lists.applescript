-- End-to-end checks of the Mathematical Functions and Array and List Utilities suites, and createarray and
-- randomarray. Only behavior shared with Satimage, so this also runs against SatimageOSAX (Scripts/parity.sh).
-- Where MTC_OSAX fixes Satimage's bugs, see math-lists-fixes.applescript. Run with Scripts/run-e2e.sh math-lists.

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

-- Math
check("abs", (abs -3), 3.0)
check("sqrt", (sqrt 16), 4.0)
check("floor", (floor -2.5), -3.0)
check("exp ln", (ln (exp 2)), 2.0)
check("log10", (log10 1000), 3.0)
check("cos", (cos 0), 1.0)
check("gamma", (gamma 5), 24.0)
check("atan2", (atan2 {0, -1}), pi)
check("hypot", (hypot {3, 4}), 5.0)
check("list", (abs {-1, 2, -3.5}), {1.0, 2.0, 3.5})
check("nested list", (sqr {{2}, {3, 4}}), {{4.0}, {9.0, 16.0}})
check("list with invalid item", (sqrt {4, -1}), {2.0, missing value})
check("text number", (abs "-2.5"), 2.5)
try
	sqrt -1
	error "sqrt -1: no error raised"
on error number n
	check("sqrt -1", n, -50)
end try
try
	hypot {1, 2, 3}
	error "hypot of 3: no error raised"
on error number n
	check("hypot of 3", n, -50)
end try

-- Arrays
set a to createarray 5 range {1, 3}
check("createarray class", class of a, array of real)
check("cos of an array", class of (cos a), array of real)
check("randomarray seed", (randomarray 3 seed 7) = (randomarray 3 seed 7), true)

-- sortlist
check("sort numbers", (sortlist {2, 5, 1, 3}), {1, 2, 3, 5})
check("sort descending", (sortlist {2, 5, 1, 3} without ascending), {5, 3, 2, 1})
check("sort text", (sortlist {"abc", "ABC", "xyz", "123"}), {"123", "ABC", "abc", "xyz"})
check("sort case-insensitive", (sortlist {"b", "B", "a", "A"} comparison 1), {"a", "A", "b", "B"})
check("sort numeric", (sortlist {"a1", "a10", "a2"} comparison 2), {"a1", "a2", "a10"})
check("sort unique", (sortlist {3, 1, 3, 2} with remove duplicates), {1, 2, 3})
check("sort with respect to", (sortlist {{2, 1, 3}, {"b", "a", "c"}} with respect to 1), {{1, 2, 3}, {"a", "b", "c"}})
check("sort lists separately", (sortlist {{3, 1, 2}, {"b", "a"}}), {{1, 2, 3}, {"a", "b"}})

-- masklist, suppress item, exclude/keep items
check("masklist", (masklist {"abc", {a:1}, "b", 3, {1, 2, 3}} with {1, 0, 1, 1, 0}), {"abc", "b", 3})
check("masklist substitute", (masklist {1, 2, 3} with {0, 1, 0} substitute "x"), {"x", 2, "x"})
check("suppress items", (suppress item {2, 3} from {"abc", {a:1}, "b", 3}), {"abc", 3})
check("suppress property", (suppress item "b" from {a:1, b:2}), {a:1})
check("exclude items", (exclude items {"r", "t", "z"} from {"a", "z", "e", "r", "t", "y"}), {"a", "e", "y"})
check("keep items", (keep items {"r", "t", "z"} from {"a", "z", "e", "r", "t", "y"}), {"z", "r", "t"})
check("exclude from lists", (exclude items {"r"} from {{"a", "r"}, {1, 2}}), {{"a"}, {1}})

-- special concat
check("special concat", (special concat {a:1, b:{1}, c:"A", d:0} with {a:2, b:{2}, c:"B"}), {a:3.0, b:{1, 2}, c:"A", d:0})
check("special concat text", (special concat ("1" & tab & "2" & return & "A" & tab & "B") with ("3" & return & "C")), "1" & tab & "2" & tab & "3" & return & "A" & tab & "B" & tab & "C")

"OK: " & checks & " checks passed"
