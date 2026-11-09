-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the 3D array handling suite (see
-- Implemented/PLAN-3DArrays.md). MTC_OSAX only. Run with Scripts/run-e2e.sh arrays3d-fixes (through iTerm).

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

-- How many numbers an array has (extractarray of an empty one is error 2000, as in SatimageOSAX).
on numberCount(a)
	try
		return count nums(a)
	on error number 2000
		return 0
	end try
end numberCount

-- isosurface: the whole surface. One 1 at the center of 0s: an octahedron of 8 triangles (SatimageOSAX's looked the
-- same only because it's symmetric); in a random field, every vertex on the value.
set values to {}
repeat with i from 1 to 27
	set end of values to 0
end repeat
set item 14 of values to 1
set cube to open3D "cube" dimensions {3, 3, 3} field values
check("octahedron", numberCount(isosurface cube at 0.5), 72)
check("at the minimum", numberCount(isosurface cube at 0), 0)
close3D cube
set random to open3D "random" dimensions {4, 4, 4} field (randomarray 64 seed 1)
set surface to nums(isosurface random at 0.5)
check("random field", (count surface) > 100 and (count surface) mod 9 = 0, true)
close3D random

-- streamline: a uniform flow along x, from the edge to the edge, and back.
set flow to open3D "flow" dimensions {3, 3, 3} field {createarray 27 range {1, 1}, createarray 27 range {0, 0}, createarray 27 range {0, 0}}
check("streamline", nums(streamline flow starting at {0, 1, 1}), {0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0})
check("streamline backward", nums(streamline flow starting at {2, 1, 1} direction -1), {2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0})
check("streamline resolution", numberCount(streamline flow starting at {0, 1, 1} resolution 0.5), 15)
set n to 0
try
	streamline flow starting at {5, 1, 1}
on error number n
end try
check("streamline outside", n, 2000)
close3D flow

-- Fields as lists, 8-byte reals, and minimum and maximum without the missing values.
set precise to open3D "precise" dimensions {3, 1, 1} field {missing value, 0.1, 1.0E+300}
check("precision", nums(contents3D precise), {missing value, 0.1, 1.0E+300})
check("minimum", item 1 of minimum of (info3D precise), 0.1)
check("maximum", item 1 of maximum of (info3D precise), 1.0E+300)

-- Pools don't hold 3D arrays: DeletePool leaves them open.
DeletePool ""
check("outside pools", list3D as string, {"precise"})
close3D precise
check("all closed", list3D, {})

"OK: " & checks & " checks passed"
