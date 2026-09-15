#!/bin/bash
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 <notarized-release.zip> <sparkle-bin-directory>" >&2; exit 2; }
archive="$1"
sparkle_bin="$2"
output="$(dirname "$archive")"
account="${ICINGA_SPARKLE_ACCOUNT:-net.blendbyte.icingastatus}"
repo="${ICINGA_RELEASE_REPO:-bashgeek/icinga-status-macos}"
staging="$(mktemp -d "$output/appcast.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto -x -k "$archive" "$staging/unpacked"
app="$staging/unpacked/Icinga Status.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
public_key="$("$sparkle_bin/generate_keys" --account "$account" -p)"
[[ "$public_key" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")" ]] || {
  echo 'The archive and Sparkle signing key do not match.' >&2; exit 1;
}
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
mkdir "$staging/updates"
cp "$archive" "$staging/updates/$(basename "$archive")"
"$sparkle_bin/generate_appcast" --account "$account" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/$repo/releases/download/v$version/" \
  --full-release-notes-url "https://github.com/$repo/releases/tag/v$version" \
  --link "https://github.com/$repo" -o "$output/appcast.xml" "$staging/updates"
"$sparkle_bin/sign_update" --account "$account" --verify "$output/appcast.xml"
