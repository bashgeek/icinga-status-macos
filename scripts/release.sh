#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh --check|--sign|--notarize

Set in the environment or ignored Config/Release.local.sh:
  ICINGA_RELEASE_TEAM_ID       Apple Developer team ID
  ICINGA_RELEASE_IDENTITY      Full Developer ID Application certificate name
  ICINGA_NOTARY_PROFILE        Notarytool Keychain profile (required for --notarize)

--check verifies local signing prerequisites without building or uploading.
--sign builds and packages a locally signed ZIP without notarization or uploading.
--notarize builds, submits to Apple, and packages a notarized ZIP for GitHub Releases.
EOF
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --check|--sign|--notarize) mode="$1" ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# == 1 ]] || { usage >&2; exit 2; }

if [[ -f Config/Release.local.sh ]]; then
  source Config/Release.local.sh
fi
: "${ICINGA_RELEASE_TEAM_ID:?Set your Apple Developer team ID.}"
: "${ICINGA_RELEASE_IDENTITY:?Set your Developer ID Application identity.}"
if [[ "$mode" == --notarize ]]; then
  : "${ICINGA_NOTARY_PROFILE:?Set your notarytool Keychain profile.}"
fi

if [[ ! "$ICINGA_RELEASE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo 'Expected a 10-character Apple Developer team ID.' >&2
  exit 1
fi
case "$ICINGA_RELEASE_IDENTITY" in
  "Developer ID Application: "*" ($ICINGA_RELEASE_TEAM_ID)") ;;
  *) echo 'Use a Developer ID Application identity belonging to the release team.' >&2; exit 1 ;;
esac

identities="$(security find-identity -v -p codesigning)"
if [[ "$identities" != *"\"$ICINGA_RELEASE_IDENTITY\""* ]]; then
  echo 'The requested valid certificate and private key are not installed in the signing keychain.' >&2
  exit 1
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
if [[ "$mode" == --check ]]; then
  echo 'Signing identity and tools are available. Notarization credentials will be validated when submitting.'
  exit 0
fi

swift test
mkdir -p build/distribution
release_dir="$(mktemp -d "$PWD/build/distribution/release.XXXXXX")"
echo "Release output: $release_dir"
xcodebuild -project IcingaStatus.xcodeproj -scheme IcingaStatus \
  -configuration Release -derivedDataPath build/DistributionDerivedData \
  "DEVELOPMENT_TEAM=$ICINGA_RELEASE_TEAM_ID" "CODE_SIGN_IDENTITY=$ICINGA_RELEASE_IDENTITY" \
  CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  "CODE_SIGN_ENTITLEMENTS=$PWD/Config/Distribution.entitlements" \
  OTHER_CODE_SIGN_FLAGS=--timestamp 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

app="$release_dir/Icinga Status.app"
ditto 'build/DistributionDerivedData/Build/Products/Release/Icinga Status.app' "$app"
codesign --verify --deep --strict --verbose=2 "$app"
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
if [[ "$signature" != *"TeamIdentifier=$ICINGA_RELEASE_TEAM_ID"* || "$signature" != *"Authority=$ICINGA_RELEASE_IDENTITY"* ]]; then
  echo 'Built app does not match the requested release signing identity.' >&2
  exit 1
fi
codesign -d --entitlements - --xml "$app" > "$release_dir/entitlements.plist" 2>/dev/null
plutil -lint "$release_dir/entitlements.plist" >/dev/null
for entitlement in com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.files.user-selected.read-only; do
  if [[ "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$release_dir/entitlements.plist" 2>/dev/null || true)" != true ]]; then
    echo "Distribution app is missing its required entitlement: $entitlement" >&2
    exit 1
  fi
done
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$release_dir/entitlements.plist" 2>/dev/null || true)" == true ]]; then
  echo 'Distribution app unexpectedly allows debugger attachment.' >&2
  exit 1
fi
lipo "$app/Contents/MacOS/Icinga Status" -verify_arch arm64 x86_64

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
if [[ "$mode" == --sign ]]; then
  artifact="Icinga-Status-$version-macos-universal-signed.zip"
  ditto -c -k --keepParent "$app" "$release_dir/$artifact"
  (cd "$release_dir" && shasum -a 256 "$artifact" > "$artifact.sha256")
  echo "Signed locally, not notarized: $release_dir/$artifact"
  exit 0
fi

ditto -c -k --keepParent "$app" "$release_dir/submission.zip"
xcrun notarytool submit "$release_dir/submission.zip" \
  --keychain-profile "$ICINGA_NOTARY_PROFILE" --wait --output-format json > "$release_dir/notarization.json"
status="$(plutil -extract status raw -o - "$release_dir/notarization.json")"
if [[ "$status" != Accepted ]]; then
  echo "Notarization was not accepted. Inspect $release_dir/notarization.json and retrieve the submission log with notarytool log." >&2
  exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

artifact="Icinga-Status-$version-macos-universal.zip"
ditto -c -k --keepParent "$app" "$release_dir/$artifact"
(cd "$release_dir" && shasum -a 256 "$artifact" > "$artifact.sha256")
echo "Ready for GitHub Releases: $release_dir/$artifact"
