#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration=Debug
launch_mode=
for argument in "$@"; do
  case "$argument" in
    --release) configuration=Release ;;
    --run) launch_mode=run ;;
    --demo) launch_mode=demo ;;
    *) echo "Usage: $0 [--release] [--run|--demo]" >&2; exit 2 ;;
  esac
done
if [[ "$launch_mode" == "demo" && "$configuration" != "Debug" ]]; then
  echo "Scenario controls require a Debug build. Use ./scripts/build.sh --demo." >&2
  exit 2
fi
build_arguments=(-project IcingaStatus.xcodeproj -scheme IcingaStatus -configuration "$configuration" -derivedDataPath build)
if [[ "${ICINGA_ADHOC_SIGNING:-0}" == "1" ]]; then
  build_arguments+=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual)
elif [[ -n "${ICINGA_DEVELOPMENT_TEAM:-}" ]]; then
  build_arguments+=("DEVELOPMENT_TEAM=$ICINGA_DEVELOPMENT_TEAM")
fi
if [[ -n "${ICINGA_SIGNING_IDENTITY:-}" ]]; then
  build_arguments+=("CODE_SIGN_IDENTITY=$ICINGA_SIGNING_IDENTITY")
fi
xcodebuild "${build_arguments[@]}" build
if [[ -n "$launch_mode" ]]; then
  # Launch arguments are ignored by an already-running copy. Quit gracefully first.
  swift -e '
    import AppKit
    let copies = NSRunningApplication.runningApplications(withBundleIdentifier: "net.blendbyte.icingastatus")
    for app in copies where !app.terminate() {
      print("The running app could not quit. Launch stopped to avoid duplicate copies.")
      exit(1)
    }
    let deadline = Date().addingTimeInterval(5)
    while copies.contains(where: { !$0.isTerminated }) && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    if copies.contains(where: { !$0.isTerminated }) {
      print("The previous app is still running. Launch stopped.")
      exit(1)
    }
  '
fi
if [[ "$launch_mode" == "run" ]]; then
  open "build/Build/Products/$configuration/Icinga Status.app"
elif [[ "$launch_mode" == "demo" ]]; then
  open "build/Build/Products/$configuration/Icinga Status.app" --args --demo
fi
