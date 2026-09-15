import SwiftUI
import IcingaCore

/// Two aligned rows sized to the menu bar's 22-point content height.
struct MenuBarReadout: View {
    let status: AggregateStatus
    private var states: [Severity] {
        [.healthy, .warning, .critical, .unknown] + (status.pendingCount > 0 ? [.pending] : [])
    }
    private var paused: Bool { status.isPaused || status.enabledCount == 0 }

    var body: some View {
        HStack(spacing: 7) {
            VStack(spacing: 1) {
                Text("H").frame(height: 10)
                Text("S").frame(height: 10)
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            HStack(spacing: 6) {
                ForEach(states, id: \.self) { severity in
                    VStack(alignment: .leading, spacing: 1) {
                        count(status.hosts[severity], severity: severity, applicable: severity != .warning)
                        count(status.services[severity], severity: severity)
                    }
                    .frame(width: columnWidth(severity), alignment: .leading)
                }
            }
            .opacity(paused ? 0.45 : 1)
            if paused {
                Image(systemName: "pause.fill").font(.system(size: 9)).foregroundStyle(.primary)
            } else if status.unavailableCount > 0 {
                Image(systemName: "exclamationmark.icloud.fill").font(.system(size: 12)).foregroundStyle(.orange)
            } else if status.waitingCount > 0 {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if status.emptyCount > 0 {
                Image(systemName: "questionmark.circle").font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .frame(height: 22)
        .fixedSize()
    }

    private func columnWidth(_ severity: Severity) -> CGFloat {
        let digits = String(max(status.hosts[severity], status.services[severity])).count
        return CGFloat(max(2, digits)) * 6 + 12
    }

    private func count(_ number: Int, severity: Severity, applicable: Bool = true) -> some View {
        HStack(spacing: 3) {
            Image(systemName: severity.readoutSymbol)
                .font(.system(size: 7, weight: .bold))
                .frame(width: 8)
                .foregroundStyle(applicable && number > 0 ? severity.color : Color.secondary)
            Text(applicable ? String(number) : "·")
                .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(applicable && number > 0 ? .primary : .secondary)
        }
        .frame(height: 10)
    }
}

struct StatusOverview: View {
    let status: AggregateStatus
    private let states: [Severity] = [.healthy, .warning, .critical, .unknown]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Status totals").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(status.objectCount) checks").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(states, id: \.self) { severity in
                        Text(severity == .critical ? "Down / Crit." : severity.title)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .fixedSize().frame(maxWidth: .infinity)
                    }
                }
                totalsRow("Hosts", symbol: "server.rack", counts: status.hosts, isHost: true)
                totalsRow("Services", symbol: "square.stack.3d.up", counts: status.services, isHost: false)
            }
            if status.pendingCount > 0 {
                Divider()
                Label("Awaiting results: \(status.hosts[.pending]) hosts, \(status.services[.pending]) services", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(PanelStyle.surface, in: RoundedRectangle(cornerRadius: PanelStyle.radius))
        .help("Totals include all checks, including acknowledged, downtime, and soft states. Unavailable instances retain their last results.")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusOverview")
    }

    private func totalsRow(_ title: String, symbol: String, counts: CheckCounts, isHost: Bool) -> some View {
        GridRow {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium)).labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize()
                .gridColumnAlignment(.leading)
            ForEach(states, id: \.self) { severity in
                let applicable = !isHost || severity != .warning
                Text(applicable ? String(counts[severity]) : "·")
                    .font(.system(size: 17, weight: counts[severity] > 0 ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(applicable && counts[severity] > 0 ? severity.color : Color.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(applicable
                                        ? "\(title), \(severity == .critical && isHost ? "Down" : severity.title), \(counts[severity])"
                                        : "Hosts do not have a warning state")
            }
        }
    }
}

extension Severity {
    var readoutSymbol: String {
        switch self {
        case .healthy: "checkmark"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark"
        case .unknown: "questionmark"
        case .pending: "clock"
        }
    }
}

extension AggregateStatus {
    var fullStatusDescription: String {
        "Icinga Status: \(title). "
        + "Hosts: \(hosts[.healthy]) up, \(hosts[.critical]) down, \(hosts[.unknown]) unknown, \(hosts[.pending]) pending. "
        + "Services: \(services[.healthy]) OK, \(services[.warning]) warning, \(services[.critical]) critical, \(services[.unknown]) unknown, \(services[.pending]) pending. "
        + (hasIncompleteCoverage ? "Incomplete monitoring coverage. " : "")
        + "Full totals include filtered problems."
    }
}
