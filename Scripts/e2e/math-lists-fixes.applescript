-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the Math and Lists suites
-- (see Implemented/PLAN-MathAndLists.md). MTC_OSAX only. Run with Scripts/run-e2e.sh math-lists-fixes (through iTerm).

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

-- topological sort never worked (-1708).
check("topological sort", (topological sort edges {{13, 2}, {1, 13}, {24, 1}}), {24, 1, 13, 2})
check("topological sort dependencies", (topological sort {1, 2, 3} dependencies {{2}, {3}, {}}), {3, 2, 1})
try
	topological sort edges {{1, 2}, {2, 1}}
	error "cycle: no error raised"
on error number n
	check("topological sort cycle", n, -2700)
end try

-- sortlist: missing values stayed NaN and landed in the middle when descending; single values gave {}.
check("sortlist missing values", (sortlist {3, missing value, 1, 2} without ascending), {3, 2, 1, missing value})
check("sortlist single value", (sortlist 5), {5})

-- suppress item: a single index was error -1719.
check("suppress item", (suppress item 2 from {"abc", {a:1}, "b", 3}), {"abc", "b", 3})
check("suppress last item", (suppress item -1 from {1, 2, 3}), {1, 2})

-- exclude/keep items ignored case sensitive false; keep items {} gave {{}, {}}.
check("exclude ignoring case", (exclude items {"A"} from {"a", "b"} without case sensitive), {"b"})
check("keep ignoring case", (keep items {"A"} from {"a", "b"} without case sensitive), {"a"})
check("keep nothing", (keep items {} from {"a", "b"}), {})

-- special concat returned garbage for text with a record, and nothing for empty text.
check("special concat empty text", (special concat "" with "b"), tab & "b")
try
	special concat "a" with {a:1}
	error "text with record: no error raised"
on error number n
	check("special concat text with record", n, -1700)
end try

-- randomarray ignored a seed beyond 32 bits.
check("large seed repeats", (randomarray 3 seed 4.0E+9) = (randomarray 3 seed 4.0E+9), true)

"OK: " & checks & " checks passed"
