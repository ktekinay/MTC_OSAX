-- End-to-end checks of the Files and folders and Symlink suites, in /private/tmp (no privacy prompts).
-- Only behavior shared with Satimage, so this also runs against SatimageOSAX (Scripts/parity.sh).
-- Where MTC_OSAX fixes Satimage's bugs, see files-fixes.applescript. Run with Scripts/run-e2e.sh files.

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0
property root : "/private/tmp/mtc-e2e-files"

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

try
	fileremove root
end try
-- A literal POSIX file: Satimage fails (error 1) for a path string directly in a system folder like /private/tmp,
-- which is what it would get from POSIX file of a variable. MTC_OSAX's fix is checked in files-fixes.applescript.
check("mkdir", (mkdir (POSIX file "/private/tmp/mtc-e2e-files")), root & "/")
check("mkdir nested", (mkdir root & "/a/b"), root & "/a/b/")
try
	mkdir root & "/a/b"
	error "mkdir existing: no error raised"
on error number n
	check("mkdir existing", n, 17)
end try

check("filenew", (filenew root & "/f.txt"), root & "/f.txt")
try
	filenew root & "/f.txt"
	error "filenew existing: no error raised"
on error number n
	check("filenew existing", n, -48)
end try
check("filegetname", (filegetname (POSIX file (root & "/f.txt"))), "f.txt")
check("filegetname list", (filegetname {root & "/a", "file://" & root & "/f.txt"}), {"a", "f.txt"})

writetext "hello" to root & "/f.txt"
check("filecopy", (filecopy root & "/f.txt" to root & "/a" name "g.txt"), root & "/a/g.txt")
check("copied content", (readtext root & "/a/g.txt"), "hello")
check("filemove", (filemove root & "/a/g.txt" filepath (POSIX file (root & "/h.txt"))), root & "/h.txt")
check("filerename", (filerename root & "/h.txt" to "i.txt"), root & "/i.txt")

check("chmod set", (chmod root & "/i.txt" to "600"), "644")
check("chmod get", (chmod root & "/i.txt"), "600")

create symlink "i.txt" in (POSIX file root) name "link"
check("readlink", (readlink root & "/link"), "i.txt")
check("testsymlink", (testsymlink root & "/link"), true)
check("testsymlink file", (testsymlink root & "/i.txt"), false)

set t to mkstemp (POSIX file root) name "tmp.txt" suffix 4
check("mkstemp", (t starts with root & "/tmp") and (t ends with ".txt") and (length of t is (length of root) + 14), true)

check("fileremove", (fileremove {root & "/i.txt", root & "/link"}), 2)
check("fileremove folder", (fileremove root), 1)

"OK: " & checks & " checks passed"
