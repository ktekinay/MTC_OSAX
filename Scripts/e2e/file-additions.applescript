-- End-to-end checks of the Satimage File Additions suite (all but the dialogs), in /private/tmp (no privacy prompts).
-- Only behavior shared with Satimage, so this also runs against SatimageOSAX (Scripts/parity.sh).
-- Where MTC_OSAX fixes Satimage's bugs, see file-additions-fixes.applescript. Run with Scripts/run-e2e.sh file-additions.

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0
property root : "/private/tmp/mtc-e2e-file-additions"

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & my show(expected) & ", got " & my show(actual)
end check

-- Lists in the order the file system gives them, so compare their items, not their order.
on checkItems(label, actual, expected)
	set checks to checks + 1
	if (count of actual) is not (count of expected) then error label & ": expected " & my show(expected) & ", got " & my show(actual)
	repeat with anItem in expected
		if actual does not contain {contents of anItem} then error label & ": missing " & anItem & " in " & my show(actual)
	end repeat
end checkItems

on show(value)
	try
		set AppleScript's text item delimiters to ", "
		return value as text
	on error
		return "(" & (class of value as text) & ")"
	end try
end show

try
	fileremove root
end try
-- A literal POSIX file: Satimage fails (error 1) for a path string directly in a system folder like /private/tmp.
mkdir (POSIX file "/private/tmp/mtc-e2e-file-additions")
mkdir root & "/src/sub"
mkdir root & "/src/pkg.app/Contents"
writetext "x" to root & "/src/a.txt"
writetext "x" to root & "/src/B.TXT"
writetext "x" to root & "/src/.hidden"
writetext "x" to root & "/src/img.png"
writetext "x" to root & "/src/sub/c.txt"
writetext "x" to root & "/src/pkg.app/Contents/Info.plist"
set src to root & "/src"

-- list files
checkItems("list files", (list files src with names only), {"a.txt", "B.TXT", "img.png", "c.txt", "pkg.app"})
checkItems("list files not recursively", (list files src without recursively as unix path), {src & "/a.txt", src & "/B.TXT", src & "/img.png", src & "/sub/", src & "/pkg.app/"})
checkItems("list files invisibles", (list files src with invisibles and names only), {".hidden", "a.txt", "B.TXT", "img.png", "c.txt", "pkg.app"})
checkItems("list files extension", (list files src of extension "txt" with names only), {"a.txt", "c.txt"})
checkItems("list files UTI", (list files src conforming to "public.image" with names only), {"img.png"})
checkItems("list files not UTI", (list files src not conforming to "public.text" with names only), {"img.png", "pkg.app"})
checkItems("list files starting with", (list files src starting with "B" with names only), {"B.TXT"})
checkItems("list files packages", (list files (src & "/pkg.app") with ignoring packages and names only), {"Info.plist"})
checkItems("list files as text", (list files (src & "/sub") as Unicode text), {"file://" & src & "/sub/c.txt"})
check("list files as alias", class of item 1 of (list files (src & "/sub") as alias), alias)
check("list files file reference", (POSIX path of item 1 of (list files (src & "/sub"))), src & "/sub/c.txt")
check("list files missing", (list files (root & "/nope")), {})

-- glob
checkItems("glob", (glob src & "/*" with names only), {"a.txt", "B.TXT", "img.png", "sub", "pkg.app"})
checkItems("glob from", (glob "*.txt" from (POSIX file src) as unix path), {src & "/a.txt"})
checkItems("glob brace", (glob src & "/{a,B}.*" with names only), {"a.txt", "B.TXT"})
checkItems("glob extension", (glob src & "/*" of extension "TXT" with names only), {"B.TXT"})
check("glob no match", (glob src & "/*.zzz"), {})

-- URLs
check("absoluteURL path", (absoluteURL src & "/a b.txt"), "file://" & src & "/a%20b.txt")
check("absoluteURL relative", (absoluteURL "sub/c.txt" from (POSIX file (src & "/"))), "file://" & src & "/sub/c.txt")
check("absoluteURL unix path", (absoluteURL "a%20b.html" from "http://h.com/x/" as unix path), "/x/a b.html")
check("absoluteURL http", (absoluteURL "../y.html?q=1" from "http://h.com/a/b/c.html"), "http://h.com/a/y.html?q=1")
check("relativeURL", (relativeURL "http://h.com/a/b/c.html" from "http://h.com/a/d/e.html"), "../b/c.html")
check("relativeURL files", (relativeURL (POSIX file (src & "/sub/c.txt")) from (POSIX file (src & "/"))), "sub/c.txt")

set info to URL info for "http://user:pw@www.example.com:8080/dir/file.html;p=1?q=2#top"
check("URL info scheme", scheme of info, "http")
check("URL info host", host of info, "www.example.com")
check("URL info user", user name of info, "user")
check("URL info password", password of info, "pw")
check("URL info path", path of info, "/dir/file.html")
check("URL info parameters", url parameters of info, "p=1")
check("URL info query", url query of info, "q=2")
check("URL info fragment", url fragment of info, "top")
check("URL info name", name of info, "file.html")
check("URL info extension", name extension of info, "html")
check("URL info type", type identifier of info, "public.html")
set info to URL info for (src & "/a.txt")
check("URL info file", {name of info, unix path of info, type identifier of info}, {"a.txt", src & "/a.txt", "public.plain-text"})
try
	URL info for (root & "/nope")
	error "URL info missing: no error raised"
on error number n
	check("URL info missing", n, -43)
end try

check("alias description for", (alias description for (src & "/sub")), src & "/sub")
check("alias description for alias", (alias description for (POSIX file (src & "/sub") as alias)), src & "/sub/")

-- backup
mkdir root & "/dst"
set dst to root & "/dst"
check("backup report", (backup (POSIX file src) onto (POSIX file dst) without recursively only extensions {"png"}), "Items to create : " & return & tab & dst & "/img.png" & linefeed)
check("backup level 1", (backup (POSIX file src) onto (POSIX file dst) level 1), "OK")
checkItems("backup copied", (list files dst with names only), {"a.txt", "B.TXT", "img.png", "c.txt", "pkg.app"})
check("backup up to date", (backup (POSIX file src) onto (POSIX file dst) level 2), "OK")

check("cleanup", (fileremove root), 1)

"OK: " & checks & " checks passed"
