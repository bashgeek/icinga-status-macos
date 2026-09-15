#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh --check|--sign|--notarize|--publish

Set in the environment or ignored Config/Release.local.sh:
  ICINGA_RELEASE_TEAM_ID       Apple Developer team ID
  ICINGA_RELEASE_IDENTITY      Full Developer ID Application certificate name
  ICINGA_NOTARY_PROFILE        Notarytool Keychain profile (required for --notarize)
  ICINGA_SPARKLE_ACCOUNT       Sparkle Keychain account (default: net.blendbyte.icingastatus)
  ICINGA_RELEASE_REPO          GitHub repository (default: bashgeek/icinga-status-macos)
  ICINGA_RELEASE_NOTES         Optional Markdown file; otherwise use GitHub's generated notes

--check verifies local signing prerequisites without building or uploading.
--sign builds and packages a locally signed ZIP without notarization or uploading.
--notarize builds, submits to Apple, and packages a notarized ZIP for GitHub Releases.
--publish also uploads the ZIP, checksum, and signed update feed to a GitHub release.
          Requires a clean tree, the version tag pushed to GitHub, and a public repository.
EOF
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --check|--sign|--notarize|--publish) mode="$1" ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# == 1 ]] || { usage >&2; exit 2; }

if [[ -f Config/Release.local.sh ]]; then
  source Config/Release.local.sh
fi
: "${ICINGA_RELEASE_TEAM_ID:?Set your Apple Developer team ID.}"
: "${ICINGA_RELEASE_IDENTITY:?Set your Developer ID Application identity.}"
if [[ "$mode" == --notarize || "$mode" == --publish ]]; then
  : "${ICINGA_NOTARY_PROFILE:?Set your notarytool Keychain profile.}"
fi
export ICINGA_SPARKLE_ACCOUNT="${ICINGA_SPARKLE_ACCOUNT:-net.blendbyte.icingastatus}"
export ICINGA_RELEASE_REPO="${ICINGA_RELEASE_REPO:-bashgeek/icinga-status-macos}"

if [[ "$mode" == --publish ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo 'Commit the release changes first.' >&2; exit 1; }
  tag="$(git describe --tags --exact-match HEAD)"
  remote_tag="$(gh api "repos/$ICINGA_RELEASE_REPO/git/ref/tags/$tag" --jq .object.sha)"
  [[ "$remote_tag" == "$(git rev-parse "$tag")" ]] || { echo 'Push the release tag to GitHub first.' >&2; exit 1; }
  [[ "$(gh repo view "$ICINGA_RELEASE_REPO" --json visibility --jq .visibility)" == PUBLIC ]] || {
    echo 'GitHub-hosted updates require public release downloads. Make the repository public before publishing.' >&2; exit 1;
  }
  if gh release view "$tag" --repo "$ICINGA_RELEASE_REPO" >/dev/null 2>&1; then
    echo 'This release already exists. Use a new version and tag.' >&2; exit 1
  fi
  if [[ -n "${ICINGA_RELEASE_NOTES:-}" && ! -f "$ICINGA_RELEASE_NOTES" ]]; then
    echo 'The release notes file does not exist.' >&2; exit 1
  fi
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
  echo 'Signing identity and tools are available. Sparkle keys and notarization credentials are checked before use.'
  exit 0
fi

swift test
xcodebuild -resolvePackageDependencies -project IcingaStatus.xcodeproj -scheme IcingaStatus \
  -derivedDataPath build/DistributionDerivedData
sparkle_bin="$PWD/build/DistributionDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
public_key="$("$sparkle_bin/generate_keys" --account "$ICINGA_SPARKLE_ACCOUNT" -p)"
configured_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Config/Info.plist)"
[[ "$public_key" == "$configured_key" ]] || { echo 'The Sparkle Keychain key does not match Config/Info.plist.' >&2; exit 1; }
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
architectures="$(lipo -archs "$app/Contents/MacOS/Icinga Status")"
case "$architectures" in
  'arm64 x86_64'|'x86_64 arm64') ;;
  *) echo "Release must support Apple silicon and Intel; found: $architectures" >&2; exit 1 ;;
esac

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
if [[ "$mode" == --publish && "$tag" != "v$version" ]]; then
  echo 'The release tag must match the app version.' >&2; exit 1
fi
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
./scripts/generate-appcast.sh "$release_dir/$artifact" "$sparkle_bin"
echo "Ready for GitHub Releases: $release_dir/$artifact"

if [[ "$mode" == --publish ]]; then
  notes=(--generate-notes)
  if [[ -n "${ICINGA_RELEASE_NOTES:-}" ]]; then notes=(--notes-file "$ICINGA_RELEASE_NOTES"); fi
  gh release create "$tag" "$release_dir/$artifact" "$release_dir/$artifact.sha256" "$release_dir/appcast.xml" \
    --repo "$ICINGA_RELEASE_REPO" --verify-tag --draft --title "Icinga Status $tag" "${notes[@]}"
  gh release edit "$tag" --repo "$ICINGA_RELEASE_REPO" --draft=false --latest
fi
