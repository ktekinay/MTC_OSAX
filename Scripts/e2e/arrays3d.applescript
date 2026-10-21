-- End-to-end checks of the 3D array handling suite (Implemented/PLAN-3DArrays.md). Only behavior shared with Satimage,
-- so this also runs against SatimageOSAX (Scripts/parity.sh). Where MTC_OSAX fixes Satimage's bugs (isosurface,
-- streamline), see arrays3d-fixes.applescript. Run with Scripts/run-e2e.sh arrays3d.

use AppleScript version "2.4"
use application "MTC_OSAX"
-- No scripting additions: SatimageOSAX's dictionary also defines "small integer", which would be ambiguous.

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

check("nothing open", list3D, {})

-- A 3×3×3 field: 1 at the center, 0 elsewhere (offset ix + nx*iy + nx*ny*iz).
set values to {}
repeat with i from 1 to 27
	set end of values to 0
end repeat
set item 14 of values to 1
set cube to open3D "cube" dimensions {3, 3, 3} field (extractarray values for -1)
check("class", class of cube, Array3DRef)
set info to info3D cube
check("name", name of info, "cube")
check("dimensions", dimensions of info, {3, 3, 3})
check("number of field", number of field of info, 1)
check("minimum", item 1 of minimum of info, 0.0)
check("maximum", item 1 of maximum of info, 1.0)
check("info by name", name of (info3D "cube"), "cube")
check("contents", nums(contents3D cube), values)
check("extract", nums(extract3D cube start {2, 2, 2} length {1, 1, 1}), {1.0})
check("extract row", nums(extract3D cube start {1, 2, 2} length {3, 1, 1}), {0.0, 1.0, 0.0})
check("extract from the end", nums(extract3D cube start {-2, -2, -2} length {1, 1, 1}), {1.0})

-- Scales: an array, a count, a list.
set scaled to open3D "scaled" dimensions {createarray 3 range {10, 20}, 3, {0, 1, 4}} field (createarray 27)
check("scale x", nums(item 1 of scale of (info3D scaled)), {10.0, 15.0, 20.0})
check("scale z", nums(item 3 of scale of (info3D scaled)), {0.0, 1.0, 4.0})
check("newest first", list3D as string, {"scaled", "cube"})
close3D scaled

-- A vector field.
set flow to open3D "flow" dimensions {2, 2, 2} field {createarray 8, createarray 8 range {10, 17}, createarray 8 range {20, 27}}
check("vector fields", number of field of (info3D flow), 3)
check("vector contents", count (contents3D flow), 3)
check("field index", nums(extract3D flow start {1, 1, 1} length {2, 1, 1} field index 3), {20.0, 21.0})
close3D flow

-- Names: the newest with a name; renamed.
set other to open3D "cube" dimensions {1, 1, 1} field (createarray 1)
check("repeated name", dimensions of (info3D "cube"), {1, 1, 1})
rename3D other into "small"
check("renamed", dimensions of (info3D "cube"), {3, 3, 3})
close3D "small"

-- Errors, as SatimageOSAX gives them.
set n to 0
try
	open3D "bad" dimensions {2, 2, 2} field (createarray 27)
on error number n
end try
check("wrong size", n, 2)
set n to 0
try
	open3D "bad" dimensions {3, 9} field (createarray 27)
on error number n
end try
check("two dimensions", n, 3)
set n to 0
try
	extract3D "cube" start {3, 3, 3} length {2, 1, 1}
on error number n
end try
check("past the end", n, -1719)
set n to 0
try
	isosurface "cube" at 2
on error number n
end try
check("isosurface outside the values", n, 7)
set n to 0
try
	streamline "cube" starting at {1, 1, 1}
on error number n
end try
check("streamline of a scalar field", n, -1)
close3D cube
set n to 0
try
	info3D "cube"
on error number n
end try
check("closed", n, -1728)
check("all closed", list3D, {})

"OK: " & checks & " checks passed"
