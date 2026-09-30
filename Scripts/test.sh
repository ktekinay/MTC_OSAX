#!/bin/zsh
# Runs the package's tests (swift test, with any arguments given) in a sandbox that lets them write only where a build
# and the tests need to: the package's .build folder, the temporary and cache folders, and SwiftPM's caches.
# Everything else can be read but not written, deleted, renamed or unlocked, so a test that goes wrong (a test once
# ran fileremove "/" against code that accepted it) can't harm your files.
#
#   Scripts/test.sh
#   Scripts/test.sh --filter XMLTests --sanitize=address
#
# Each test process also has a time limit (MTC_TEST_TIME_LIMIT; see the README).

package="${0:A:h:h}/Packages/MTCOSAXKit"
temporary="$(getconf DARWIN_USER_TEMP_DIR)"
caches="$(getconf DARWIN_USER_CACHE_DIR)"

# Later rules win: writing is denied everywhere, then allowed in these folders.
profile="(version 1)
(allow default)
(deny file-write*)
(allow file-write*
	(subpath \"${package:A}/.build\")
	(subpath \"${temporary:A}\")
	(subpath \"${caches:A}\")
	(subpath \"/private/tmp\")
	(subpath \"/private/var/tmp\")
	(subpath \"/dev\")
	(subpath \"${HOME:A}/Library/Caches/org.swift.swiftpm\")
	(subpath \"${HOME:A}/Library/org.swift.swiftpm\"))"

# SwiftPM sandboxes the manifest's compilation itself, which can't be done inside this sandbox; this one is stricter.
exec sandbox-exec -p "$profile" swift test --package-path "$package" --disable-sandbox "$@"
