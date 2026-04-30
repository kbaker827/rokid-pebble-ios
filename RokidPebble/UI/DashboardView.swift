import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: HubViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectivityRow
                ForEach(Array(vm.activeSources.enumerated()), id: \.offset) { idx, source in
                    sourceCard(source, isPebbleFocus: idx == vm.pebbleSourceIndex % max(vm.activeSources.count, 1))
                }
                if vm.activeSources.isEmpty {
                    emptyCard
                }
                summaryCard
            }
            .padding()
        }
    }

    // MARK: - Connectivity row

    private var connectivityRow: some View {
        HStack(spacing: 12) {
            connectBadge(
                icon: "eyeglasses",
                label: vm.glassesConnected ? "\(vm.glassesClientCount) glasses" : "No glasses",
                color: vm.glassesConnected ? .green : .gray,
                detail: "TCP :8090"
            )
            Spacer()
            connectBadge(
                icon: "applewatch",
                label: pebbleLabel,
                color: pebbleColor,
                detail: vm.pebble.watchName ?? "scanning…"
            )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var pebbleLabel: String {
        switch vm.pebble.connectionState {
        case .off:           return "BT off"
        case .scanning:      return "Scanning"
        case .connecting:    return "Connecting"
        case .handshake:     return "Handshake"
        case .connected:     return "Connected"
        case .disconnected:  return "Disconnected"
        }
    }

    private var pebbleColor: Color {
        switch vm.pebble.connectionState {
        case .connected:  return .green
        case .scanning, .connecting, .handshake: return .orange
        default:          return .gray
        }
    }

    private func connectBadge(icon: String, label: String, color: Color, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.bold())
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Source card

    private func sourceCard(_ source: SourceData, isPebbleFocus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: source.sourceIcon)
                    .foregroundColor(statusColor(source.status))
                Text(source.sourceName)
                    .font(.headline)
                Spacer()
                if isPebbleFocus {
                    Image(systemName: "applewatch")
                        .foregroundColor(.blue)
                        .imageScale(.small)
                }
                statusBadge(source.status)
            }
            if !source.line1.isEmpty {
                Text(source.line1)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            if !source.line2.isEmpty {
                Text(source.line2)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if source.isStale && source.status != .disconnected {
                Label("Data may be stale", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPebbleFocus ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Glasses Summary (TCP :8090)", systemImage: "eyeglasses")
                .font(.caption)
                .foregroundColor(.secondary)
            let active = vm.activeSources.filter { $0.status == .active }
            if active.isEmpty {
                Text("No active data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(active.enumerated()), id: \.offset) { _, s in
                    Text("• \(s.sourceName): \(s.line1)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No sources enabled")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Enable Tempest or Snapmaker in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func statusColor(_ s: SourceStatus) -> Color {
        switch s {
        case .active:       return .green
        case .idle:         return .secondary
        case .error:        return .red
        case .disconnected: return .gray
        }
    }

    @ViewBuilder
    private func statusBadge(_ s: SourceStatus) -> some View {
        let (label, color): (String, Color) = {
            switch s {
            case .active:       return ("Live", .green)
            case .idle:         return ("Idle", .secondary)
            case .error:        return ("Error", .red)
            case .disconnected: return ("Off", .gray)
            }
        }()
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
