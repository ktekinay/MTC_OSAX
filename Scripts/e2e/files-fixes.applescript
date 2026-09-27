-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the Files and folders suite
-- (see Implemented/PLAN-FilesAndFolders.md). MTC_OSAX only. Run with Scripts/run-e2e.sh files-fixes (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0
property root : "/private/tmp/mtc-e2e-files-fixes"

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & (expected as text) & ", got " & (actual as text)
end check

try
	fileremove root
end try
mkdir root
writetext "x" to root & "/a.txt"

-- Satimage: error 1 for a path string directly in a system folder.
try
	fileremove "/private/tmp/mtc-e2e-files-fixes-2"
end try
check("mkdir in /private/tmp", (mkdir "/private/tmp/mtc-e2e-files-fixes-2"), "/private/tmp/mtc-e2e-files-fixes-2/")
check("filenew in /private/tmp", (filenew "/private/tmp/mtc-e2e-files-fixes-2.txt"), "/private/tmp/mtc-e2e-files-fixes-2.txt")
fileremove {"/private/tmp/mtc-e2e-files-fixes-2", "/private/tmp/mtc-e2e-files-fixes-2.txt"}

check("filegetname HFS path", (filegetname ((POSIX file (root & "/a.txt")) as text)), "a.txt")

set d to mkdtemp (POSIX file root) name "d" wildcards 8
check("mkdtemp wildcards", length of (filegetname d), 9)

mkdir root & "/f"
writetext "x" to root & "/f/one.txt"
writetext "x" to root & "/f/two.txt"
check("fileremove filesonly count", (fileremove root & "/f" with filesonly), 2)

fileremove root
"OK: " & checks & " checks passed"
