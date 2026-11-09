-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the Arrays suite (see Implemented/PLAN-Arrays.md).
-- MTC_OSAX only. Run with Scripts/run-e2e.sh arrays-fixes (through iTerm).

use AppleScript version "2.4"
use scripting additions
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

on nums(a)
	return extractarray a for -1 as list of real
end nums

on errorNumber(code)
	try
		run script code
	on error number n
		return n
	end try
	return 0
end errorNumber

-- removemissingvalue gave -1708.
check("removemissingvalue", removemissingvalue {1, missing value, 2}, {1, 2})
check("removemissingvalue array", nums(removemissingvalue (divlist (createarray 3) with (createarray 3))), {1.0, 1.0})

-- as list of integer wrapped numbers beyond 32 bits.
try
	extractarray (createarray 2 range {1.0E+10, 0}) for -1 as list of integer
	error "no error for 1.0E+10 as integer"
on error number n
	check("list of integer beyond 32 bits", n, -1700)
end try

-- histogram counted numbers up to an interval below the minimum.
check("histogram minimum", nums(item 2 of (histogram (createarray 10) samples 2 minimum 4)), {3.0, 3.0})

-- filter without reduced moved border values; the identity filter now keeps the matrix.
set m33 to {class:matrix, ncols:3, nrows:3, array of real:{1, 2, 3, 4, 5, 6, 7, 8, 9}}
check("filter not reduced", nums(array of real of (filter m33 using {0, 0, 0, 0, 1, 0, 0, 0, 0} reduced false)), {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0})

-- evalformula: sqr was unknown, a comment with a space failed, and int(f,x) integrated x by f.
check("sqr", evalformula "sqr(x)" with {x:3}, 9.0)
check("comment", evalformula "x+1 // one more" with {x:2}, 3.0)
check("int", evalformula "int(f,x)" with {f:{1, 1, 1}, x:{0, 1, 2}}, 2.0)

-- Dividing a polynomial by a number was -50.
check("divlist polynomial", nums(divlist (composepolynomial {1, 1} with {0, 2}) with 2), {0.5, 1.0})

-- An exact fit's error was 3.8e-8.
check("exact fit error", (fit error of (fitpolynomial {createarray 5, createarray 5 range {1, 9}} degree 1)) < 1.0E-14, true)

-- read binary and write binary: a path as text was error 1; integers came back as 4-byte reals; as text was taken.
set filePath to "/private/tmp/mtc-e2e-arrays-fixes-" & (random number from 100000 to 999999) & ".bin"
write binary filePath with data {16777217, -1} as integer
check("binary path as text", nums(read binary filePath as integer), {16777217.0, -1.0})
write binary filePath with data {1, 300} as byte
check("binary byte", nums(read binary filePath as byte skip 8), {1.0, 44.0})
try
	write binary filePath with data {1} as text
	error "no error for as text"
on error number n
	check("binary as text", n, -50)
end try
do shell script "rm -f " & quoted form of filePath

"OK: " & checks & " checks passed"
