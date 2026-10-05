-- End-to-end checks of what MTC_OSAX does where SatimageOSAX was broken in the File Additions suite
-- (see Implemented/PLAN-FileAdditions.md). MTC_OSAX only. Run with Scripts/run-e2e.sh file-additions-fixes (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"
use scripting additions

property checks : 0
property root : "/private/tmp/mtc-e2e-file-additions-fixes"

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & (expected as text) & ", got " & (actual as text)
end check

try
	fileremove root
end try
mkdir root
writetext "x" to root & "/a.txt"
writetext "x" to root & "/.hidden"
mkdir root & "/sub"

-- Satimage: glob "…/.*" matched . and .. (the folder and its parent).
check("glob dot pattern", (glob root & "/.*" with names only), {})
check("glob dot pattern invisibles", (glob root & "/.*" with invisibles and names only), {".hidden"})

-- Satimage: not conforming to "public.folder" kept folders.
check("glob not a folder", (glob root & "/*" not conforming to "public.folder" with names only), {"a.txt"})

-- Satimage: error -1700 for HFS paths.
set hfs to (POSIX file root) as text
check("list files HFS path", (list files hfs with names only), {"a.txt"})
check("URL info for HFS path", name of (URL info for (hfs & "a.txt")), "a.txt")

-- Satimage ran in a sandbox container, so ~ was the container, not the home folder.
set home to (system attribute "HOME") & "/"
check("absoluteURL ~", (absoluteURL "~/" as unix path), home)
check("glob ~", (glob "~" as unix path), {home})

check("cleanup", (fileremove root), 1)

"OK: " & checks & " checks passed"
