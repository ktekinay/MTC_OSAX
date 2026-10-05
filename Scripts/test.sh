#!/bin/zsh
# Runs the package's tests (swift test, with any arguments given) in a sandbox that lets them write only where a build
# and the tests need to: the package's .build folder, the temporary and cache folders, two kinds of item two tests
# make directly in /private/tmp, a few devices, and SwiftPM's caches. Everything else can be read but not written,
# deleted, renamed or unlocked, so a test that goes wrong (a test once ran fileremove "/" against code that accepted
# it) can't harm your files. The tests also can't send Apple events, launch apps, signal other processes, reach the
# network beyond this Mac, or read the cloud folders (listing them alone makes their files download).
#
#   Scripts/test.sh
#   Scripts/test.sh --filter XMLTests --sanitize=address
#
# The tests refuse to run outside a sandbox (TestSandbox.m), and each test process has a time limit
# (MTC_TEST_TIME_LIMIT; see the README).

package="${0:A:h:h}/Packages/MTCOSAXKit"
temporary="$(getconf DARWIN_USER_TEMP_DIR)"
caches="$(getconf DARWIN_USER_CACHE_DIR)"

# Later rules win: writing is denied everywhere, then allowed in these places. Setting setuid and setgid bits is an
# operation of its own, which the sandbox refuses unless it's allowed (the tests of modes set them in temporary items).
profile="(version 1)
(allow default)
(deny file-write*)
(allow file-write*
	(subpath \"${package:A}/.build\")
	(subpath \"${temporary:A}\")
	(subpath \"${caches:A}\")
	(regex #\"^/private/tmp/(mtc-unit|xml-doc)-\")
	(literal \"/dev/null\")
	(literal \"/dev/tty\")
	(literal \"/dev/dtracehelper\")
	(regex #\"^/dev/ttys[0-9]+\$\")
	(regex #\"^/dev/fd/[0-9]+\$\")
	(subpath \"${HOME:A}/Library/Caches/org.swift.swiftpm\")
	(subpath \"${HOME:A}/Library/Caches/swiftpm-testing-helper\")
	(subpath \"${HOME:A}/Library/org.swift.swiftpm\"))
(allow file-write-setugid
	(subpath \"${temporary:A}\"))
(deny appleevent-send)
(deny lsopen)
(deny signal)
(allow signal (target same-sandbox))
(deny network*)
(allow network-bind (local ip \"localhost:*\"))
(allow network-inbound (local ip \"localhost:*\"))
(allow network-outbound (remote ip \"localhost:*\") (remote unix-socket))
(deny file-read*
	(subpath \"${HOME:A}/Library/CloudStorage\")
	(subpath \"${HOME:A}/Library/Mobile Documents\"))"

# SwiftPM sandboxes the manifest's compilation itself, which can't be done inside this sandbox; this one is stricter.
exec sandbox-exec -p "$profile" swift test --package-path "$package" --disable-sandbox "$@"
