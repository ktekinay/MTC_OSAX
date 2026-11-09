-- End-to-end checks of the Arrays suite (Implemented/PLAN-Arrays.md). Only behavior shared with Satimage, so this also runs
-- against SatimageOSAX (Scripts/parity.sh). Where MTC_OSAX fixes Satimage's bugs, see arrays-fixes.applescript.
-- Run with Scripts/run-e2e.sh arrays.

use AppleScript version "2.4"
use application "MTC_OSAX"
-- No scripting additions: SatimageOSAX's dictionary also defines "small integer", which would be ambiguous.

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & my show(expected) & ", got " & my show(actual)
end check

-- Reals within a billionth (the math libraries differ in the last digits).
on near(label, actual, expected)
	set checks to checks + 1
	if class of expected is list then
		if (count actual) is not (count expected) then error label & ": expected " & my show(expected) & ", got " & my show(actual)
		repeat with i from 1 to count expected
			my near(label & " item " & i, item i of actual, item i of expected)
		end repeat
	else if (actual - expected) ^ 2 > 1.0E-18 * (1 + expected ^ 2) then
		error label & ": expected " & expected & ", got " & actual
	end if
end near

on show(value)
	try
		set AppleScript's text item delimiters to ", "
		return value as text
	on error
		return "(" & (class of value as text) & ")"
	end try
end show

-- An array's (or polynomial's) numbers.
on nums(a)
	return extractarray a for -1 as list of real
end nums

set m23 to {class:matrix, ncols:2, nrows:3, array of real:{1, 2, 3, 4, 5, 6}}
set m33 to {class:matrix, ncols:3, nrows:3, array of real:{1, 2, 3, 4, 5, 6, 7, 8, 9}}
set m44 to {class:matrix, ncols:4, nrows:4, array of real:{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}}

-- Making and reading arrays
check("creatematrix x", nums(creatematrix "x" ncols 3 nrows 2), {0.0, 1.0, 2.0, 0.0, 1.0, 2.0})
set d to creatematrix "d" diagonal {1, 2} as matrix
check("creatematrix d", {ncols of d, nrows of d, nums(array of real of d)}, {2, 2, {1.0, 0.0, 0.0, 2.0}})
check("extractarray blocks", nums(extractarray (createarray 50) for 3 at 1 step 10 blocksize 2), {0.0, 1.0, 10.0, 11.0, 20.0, 21.0})
check("extractarray integers", extractarray (createarray 7 range {-1.5, 1.5}) for -1 as list of integer, {-2, -1, 0, 0, 0, 1, 2})
check("extractarray real", extractarray (createarray 5) at 2 as real, 1.0)
check("extractarray list", nums(extractarray {1, 2.5, 3} for -1), {1.0, 2.5, 3.0})
check("changearray", nums(changearray (createarray 5) at 2 into {7, 8, 9}), {0.0, 7.0, 8.0, 9.0, 4.0})
check("insertarray", nums(insertarray {7, 8} into (createarray 5) at 2), {0.0, 1.0, 7.0, 8.0, 2.0, 3.0, 4.0})
check("reversearray", nums(reversearray {1, 2, 3}), {3.0, 2.0, 1.0})
check("reversearray matrix", nums(array of real of (reversearray m23)), {5.0, 6.0, 3.0, 4.0, 1.0, 2.0})
check("maskarray", nums(maskarray (createarray 5) with {1, 0, 1, 0, 1}), {0.0, 2.0, 4.0})
check("replacemissingvalue", replacemissingvalue {1, missing value, 3} with 0, {1, 0.0, 3})

-- Arithmetic
check("addlist", addlist {1, 2, 3} with {10, 20, 30}, {11.0, 22.0, 33.0})
check("divlist", divlist 1 with {-2, -1, 0, 1, 2}, {-0.5, -1.0, missing value, 1.0, 0.5})
check("multlist matrix", nums(array of real of (multlist {class:matrix, ncols:2, nrows:1, array of real:{1, 2}} with 2)), {2.0, 4.0})
check("multlist polynomials", nums(multlist (composepolynomial {1, 1} with {0, 2}) with {1, 2, 3}), {1.0, 4.0, 7.0, 6.0})

-- Statistics and filters
check("runningsum", nums(runningsum {1, 2, 3, 4}), {1.0, 3.0, 6.0, 10.0})
set stats to statlist {1, 2, 3, 4, 10} with kurtosis
check("statlist", {mean of stats, variance of stats, median of stats, maximum index of stats}, {4.0, 10.0, 3.0, 5})
near("statlist kurtosis", kurtosis of stats, 2.788)
set {centers, counts} to histogram (createarray 10) samples 3
check("histogram", {nums(centers), nums(counts)}, {{1.5, 4.5, 7.5}, {3.0, 3.0, 4.0}})
check("resamplematrix", nums(array of real of (resamplematrix m44 blocksize {2, 2})), {3.5, 5.5, 11.5, 13.5})
check("filter", nums(array of real of (filter m33 using {1, 2, 3, 4, 5, 6, 7, 8, 9})), {285.0})

-- evalformula
near("evalformula atan2", evalformula "atan2(y,x)" with {y:sqrt 3, x:1}, pi / 3)
check("evalformula array", nums(evalformula "2*x+1" with {"x", createarray 3}), {1.0, 3.0, 5.0})
check("evalformula statements", evalformula "r=hypot(x,y);r*2" with {x:3, y:4}, 10.0)
check("evalformula formulas", evalformula {"x+1", "x*2"} with {x:1}, {2.0, 2.0})
check("evalformula precedence", evalformula "-2^2+2*3^2" with {}, 14.0)
set doubled to evalformula "x*2" with {x:m23} as matrix
check("evalformula as matrix", {ncols of doubled, nums(array of real of doubled)}, {2, {2.0, 4.0, 6.0, 8.0, 10.0, 12.0}})
near("evalformula elliptic", evalformula "EllipticK(k)" with {k:0.5}, 1.685750354812596)

-- Polynomials and fitting
check("evalpolynomial", evalpolynomial {1, 2, 3} at 2, 17.0)
near("roots of", roots of {-6, 11, -6, 1}, {3.0, 2.0, 1.0})
near("roots of complex", item 1 of (roots of {1, 0, 1} with complex), {0.0, 1.0})
check("composepolynomial", nums(composepolynomial {0, 0, 1} with {1, 1}), {1.0, 2.0, 1.0})
set {numerator, denominator} to pade approximant {1, 1, 0.5, 0.16666666666666666} numerator 1 denominator 1
near("pade approximant", {nums(numerator), nums(denominator)}, {{1.0, 0.5}, {1.0, -0.5}})
set fit to fitpolynomial {{0, 1, 2, 3}, {1, 3, 7, 13}} degree 2 number formatting "%.3g"
check("fitpolynomial", fit string of fit, "1+x+x^2")
set noisy to fitrational {(randomarray 30 range {0, 5} seed 5), (randomarray 30 range {-1, 1} seed 6)} numerator 1 denominator 1 number formatting "%.4g"
check("fitrational", fit string of noisy, "(0.1021-0.02918*x)/(1-0.3062*x)")
near("fitrational error", fit error of noisy, 0.9951166697398599)

-- Binary files. A literal POSIX file: Satimage fails (error 1) for POSIX file of a variable in /private/tmp; and
-- integer and byte, since "small integer" comes from scripting additions, which this script can't use.
set binaryFile to POSIX file "/private/tmp/mtc-e2e-arrays.bin"
try
	fileremove binaryFile
end try
write binary binaryFile with data {1, -2.5, 300, 70000} as integer
write binary binaryFile with data {9} as integer starting at 0
check("binary", nums(read binary binaryFile as integer), {9.0, -3.0, 300.0, 70000.0})
check("binary step", nums(read binary binaryFile as integer step 2), {9.0, 300.0})
write binary binaryFile with data {1, 300} as byte
check("binary byte", nums(read binary binaryFile as byte skip 16), {1.0, 44.0})
fileremove binaryFile

"OK: " & checks & " checks passed"
