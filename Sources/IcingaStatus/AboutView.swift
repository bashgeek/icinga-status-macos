import AppKit
import SwiftUI

@MainActor enum AppInformation {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Icinga Status"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    static let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Blendbyte GmbH"
    static let repositoryURL = URL(string: "https://github.com/bashgeek/icinga-status-macos")!
    static let communityNotice = "Icinga Status is an independent community project and is not affiliated with or endorsed by Icinga. It is provided as is, without warranties or guarantees of accuracy, availability, or support."
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApp.applicationIconImage
    }()
    static let menuBarIcon: NSImage = {
        let image = icon.copy() as! NSImage
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

struct AppLogo: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: AppInformation.icon)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            AppLogo(size: 96)

            VStack(spacing: 8) {
                Text(AppInformation.name)
                    .font(.title2.weight(.semibold))
                Text("Version \(AppInformation.version) (\(AppInformation.build))")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("aboutVersion")
            }

            VStack(spacing: 12) {
                Link("github.com/bashgeek/icinga-status-macos", destination: AppInformation.repositoryURL)
                    .font(.callout)
                    .accessibilityIdentifier("aboutGitHub")
                Text(AppInformation.copyright)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Divider()
            Text(AppInformation.communityNotice)
                .font(.caption).foregroundStyle(.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("aboutCommunityNotice")
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width: 380)
        .background(.background)
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Icinga Status…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
        }
    }
}
