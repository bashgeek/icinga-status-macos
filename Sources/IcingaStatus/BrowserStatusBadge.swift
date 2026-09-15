import SwiftUI
import IcingaCore

struct BrowserStatusBadge: View {
    let status: BrowserBadgeStatus
    var highlighted = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                if status.state == .unconfigured {
                    Text("SET UP").font(.system(size: 9, weight: .bold))
                } else {
                    counter("H", value: status.hostCount)
                    Text("/").font(.system(size: 10, weight: .regular)).opacity(0.55)
                    counter("S", value: status.serviceCount)
                }
            }
            .padding(.horizontal, 7)

            if status.unavailableCount > 0 {
                segment("API \(status.unavailableCount)", symbol: "exclamationmark.icloud.fill", background: apiColor)
            } else if status.waitingCount > 0 || status.pendingCount > 0 {
                segment("WAIT", symbol: "clock", background: Color.black.opacity(0.15))
            } else if status.emptyCount > 0 {
                segment("EMPTY", symbol: "questionmark.circle", background: Color.black.opacity(0.15))
            }
        }
        .foregroundStyle(.white)
        .frame(height: 20)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.white.opacity(highlighted ? 0.75 : 0.15), lineWidth: highlighted ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(height: 22)
        .fixedSize()
    }

    private var background: Color {
        let base: Color
        switch status.state {
        case .healthy: base = Color(red: 0.07, green: 0.40, blue: 0.22)
        case .problems: base = Color(red: 0.70, green: 0.10, blue: 0.16)
        case .connectionFailure: base = apiColor
        case .waiting, .paused, .unconfigured: base = Color(red: 0.30, green: 0.33, blue: 0.37)
        }
        return highlighted ? base.mix(with: .white, by: 0.14) : base
    }

    private var apiColor: Color { Color(red: 0.53, green: 0.27, blue: 0.025) }
    private var symbol: String {
        switch status.state {
        case .healthy: "checkmark"
        case .problems: "exclamationmark.triangle.fill"
        case .connectionFailure: "exclamationmark"
        case .waiting: "clock"
        case .paused: "pause.fill"
        case .unconfigured: "plus"
        }
    }

    private func counter(_ label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .medium)).opacity(0.85)
            Text(String(value)).font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
        }
    }

    private func segment(_ title: String, symbol: String, background: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(title).font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 6).frame(height: 20)
        .background(background)
    }
}
