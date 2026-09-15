# Icinga Status for macOS

A native menu bar app for monitoring multiple Icinga 2 instances, built with Swift 6 and SwiftUI. Requires macOS 15 or later and has no third-party runtime dependencies.

- Four menu bar styles with host and service totals, problem counts, and connection status.
- Overview, Hosts, and Services views with search, instance filters, and Icinga Web links.
- Support for Icinga Web 2 Monitoring and Icinga DB Web.
- Optional notifications, acknowledgements, and rechecks.
- Keychain credentials and per-instance certificate trust for private CAs.

Icinga Status is an independent community project, unaffiliated with or endorsed by Icinga. It is provided as is, without warranties or guarantees of accuracy, availability, or support.

## Download

Check [GitHub Releases](https://github.com/bashgeek/icinga-status-macos/releases) for a signed macOS version. Download the app from an available release, unpack it, and move **Icinga Status.app** to **Applications** before launching. The app lives in the menu bar and has no Dock icon.

## Screenshots

The examples below use development sample data, including simulated incidents and API failures.

| Healthy monitoring | Problems and API failures |
| --- | --- |
| ![Green menu bar totals and the healthy Overview](docs/screenshots/healthy.png) | ![Problem counts, an API failure indicator, and incidents in Overview](docs/screenshots/problems.png) |

| Service inventory | Menu bar settings |
| --- | --- |
| ![Services with their status and Icinga Web links](docs/screenshots/services.png) | ![General settings with menu bar appearance examples](docs/screenshots/settings.png) |

## Connect

Add an instance in Settings using its Icinga 2 HTTPS API URL, usually `https://icinga.example.com:5665`, and an API account with `objects/query/Host` and `objects/query/Service` permissions. A trailing `/v1` is accepted. This app supports the Icinga 2 API only.

Set the separate Icinga Web URL to enable host and service links. Choose Icinga DB Web explicitly if your URL does not identify the module. For acknowledgements and rechecks, enable actions per instance and grant `actions/acknowledge-problem` and `actions/reschedule-check` permissions.

## Build

Open `IcingaStatus.xcodeproj` in Xcode 26 or later. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and set your Apple Development team. Keep the same signing identity across builds to preserve Keychain authorization.

```sh
./scripts/build.sh --run       # Build and launch
./scripts/build.sh --demo      # Debug only, isolated sample data and scenario switcher
swift test                    # Core tests
./scripts/test-tls.sh          # Local HTTPS integration tests
```

Build output is ignored under `build/`. Regenerate the Xcode project with `xcodegen generate` after changing `project.yml` or adding source files.

For distribution outside the App Store, copy `Config/Release.local.sh.example` to `Config/Release.local.sh` and fill in your Developer ID signing details. Run `./scripts/release.sh --help` for signing and notarization commands. Local signing files are ignored by Git.

After building Debug, run `python3 scripts/capture-screenshots.py` to export the complete sample-data gallery to ignored `build/screenshots/`. The four images above are kept in `docs/screenshots/` for GitHub. To regenerate the menu bar examples bundled in Settings, run `python3 scripts/capture-menubar-examples.py` and rebuild.

## Credits

Inspired by [Icinga Multi Status](https://github.com/bashgeek/icinga-multi-status). The app icon comes from that project's `img/icon_black_*.png` assets at commit `4fe0bdca6df49db80cb571d65f1cdfa0f592b674`; the 1024-pixel variant is scaled from its 512-pixel original. Its [MIT license](Sources/IcingaStatus/Resources/IcingaMultiStatus-LICENSE.txt) is included in the app.
