#!/bin/bash
set -euo pipefail

framework="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"
[[ -d "$framework" ]] || { echo 'Sparkle.framework was not embedded.' >&2; exit 1; }
[[ "${CODE_SIGNING_ALLOWED:-YES}" == YES ]] || exit 0
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
arguments=(--force --sign "$identity" --options runtime)
if [[ "$identity" == - ]]; then
  arguments+=(--timestamp=none)
else
  arguments+=(--timestamp)
fi

# Xcode's framework copy does not re-sign nested helpers during ordinary builds.
for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign "${arguments[@]}" --preserve-metadata=entitlements "$framework/Versions/B/$helper"
done
codesign "${arguments[@]}" "$framework"
