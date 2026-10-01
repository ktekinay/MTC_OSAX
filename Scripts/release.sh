#!/bin/zsh
# Builds MTC_OSAX for release, has Apple notarize it, and leaves a zip to distribute.
#
#   Scripts/release.sh                  build, notarize, staple, zip
#   Scripts/release.sh --no-notarize    build and check the signature only
#
# The Release configuration is optimized and signed with the Developer ID certificate, the hardened runtime and a
# secure timestamp, without the entitlement that lets a debugger attach (which the Debug build has, and which
# notarization refuses).
#
# Notarizing needs your credentials in the keychain, once:
#
#   xcrun notarytool store-credentials mtc-osax-notary --apple-id <you@example.com> --team-id 8A6WVHL579
#
# (it asks for an app-specific password from appleid.apple.com). MTC_NOTARY_PROFILE names another profile.

set -e
root="${0:A:h:h}"
profile="${MTC_NOTARY_PROFILE:-mtc-osax-notary}"
derived="$root/build/DerivedData"
app="$derived/Build/Products/Release/MTC_OSAX.app"

xcodebuild -project "$root/MTC_OSAX.xcodeproj" -scheme MTC_OSAX -configuration Release -derivedDataPath "$derived" build | tail -1

# What notarization checks, before waiting for it: a valid Developer ID signature with the hardened runtime and a
# secure timestamp, and no debugging entitlement.
codesign --verify --strict --deep "$app"
details="$(codesign -d --verbose=4 --entitlements - "$app" 2>&1)"
[[ "$details" == *"flags=0x10000(runtime)"* ]] || { echo "The hardened runtime isn't on." >&2; exit 1 }
[[ "$details" == *"Authority=Developer ID Application"* ]] || { echo "Not signed with a Developer ID certificate." >&2; exit 1 }
[[ "$details" == *"Timestamp="* ]] || { echo "The signature has no secure timestamp." >&2; exit 1 }
[[ "$details" != *"get-task-allow"* ]] || { echo "The build has the get-task-allow entitlement." >&2; exit 1 }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip="$root/build/MTC_OSAX-$version.zip"
echo "Built and signed: $app (version $version)"

if [[ "$1" == "--no-notarize" ]]; then
	exit 0
fi

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
# Again, with the ticket stapled to the app inside.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose=2 "$app"
echo "Notarized: $zip"
