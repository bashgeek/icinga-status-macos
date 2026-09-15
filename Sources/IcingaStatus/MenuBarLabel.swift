import AppKit
import SwiftUI
import IcingaCore

struct MenuBarLabel: View {
    let store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let status = store.aggregate
        Group {
            if store.preferences.effectiveMenuBarDisplay == .browserBadge {
                if let image = badgeImage(status) {
                    Image(nsImage: image).renderingMode(.original)
                } else {
                    statusIcon(status)
                }
            } else if store.preferences.effectiveMenuBarDisplay == .fullStatus, status.configuredCount > 0 {
                if let image = readoutImage(status) {
                    Image(nsImage: image).renderingMode(.original)
                } else {
                    statusIcon(status)
                }
            } else {
                HStack(spacing: 3) {
                    statusIcon(status)
                    if store.preferences.effectiveMenuBarDisplay == .problemCount, !status.isPaused, !status.problems.isEmpty {
                        Text(status.problems.count > 999 ? "999+" : "\(status.problems.count)")
                            .monospacedDigit()
                    }
                    if status.hasIncompleteCoverage, !status.problems.isEmpty, !status.isPaused {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                }
            }
        }
        .accessibilityLabel(description(status))
        .help(description(status))
    }

    private func description(_ status: AggregateStatus) -> String {
        store.preferences.effectiveMenuBarDisplay == .browserBadge
            ? BrowserBadgeStatus(status).accessibilityDescription : status.fullStatusDescription
    }

    private func statusIcon(_ status: AggregateStatus) -> Image {
        if status.configuredCount == 0 || (!status.isPaused && status.enabledCount > 0 && status.problems.isEmpty && !status.hasIncompleteCoverage) {
            return Image(nsImage: AppInformation.menuBarIcon).renderingMode(.template)
        }
        return Image(systemName: status.symbol)
    }

    private func badgeImage(_ status: AggregateStatus) -> NSImage? {
        render(BrowserStatusBadge(status: BrowserBadgeStatus(status), highlighted: store.isRefreshHighlighted))
    }

    private func readoutImage(_ status: AggregateStatus) -> NSImage? {
        render(MenuBarReadout(status: status).environment(\.colorScheme, colorScheme))
    }

    private func render<Content: View>(_ content: Content) -> NSImage? {
        // MenuBarExtra labels need raster images to preserve custom layout and colors.
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(2, displayScale)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .healthy: .green
        case .pending: .secondary
        case .warning: .orange
        case .unknown: .purple
        case .critical: .red
        }
    }
    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .pending: "clock"
        case .warning: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.diamond.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}

extension AggregateStatus {
    var symbol: String {
        if configuredCount == 0 { return "network" }
        if isPaused || enabledCount == 0 { return "pause.circle" }
        if !problems.isEmpty { return severity.symbol }
        if unavailableCount > 0 { return "exclamationmark.icloud" }
        if waitingCount > 0 || pendingCount > 0 { return "clock" }
        if emptyCount > 0 { return "questionmark.circle" }
        return "checkmark.circle"
    }
    var color: Color {
        if isPaused || enabledCount == 0 { return .secondary }
        if !problems.isEmpty { return severity.color }
        if hasIncompleteCoverage { return .orange }
        return .green
    }
}
