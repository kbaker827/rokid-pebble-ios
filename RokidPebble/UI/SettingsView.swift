import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vm: HubViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                tempestSection
                snapmakerSection
                pebbleSection
                glassesSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        vm.applySourceSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Tempest

    private var tempestSection: some View {
        Section {
            Toggle("Enable Tempest", isOn: $settings.tempestEnabled)
            if settings.tempestEnabled {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(sourceStatusColor(vm.tempest.data.status))
                        .imageScale(.small)
                    Text(statusDescription(vm.tempest.data))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("WeatherFlow Tempest")
        } footer: {
            Text("Listens for UDP broadcasts from your Tempest Hub on port 50222. No API key needed.")
        }
    }

    // MARK: - Snapmaker

    private var snapmakerSection: some View {
        Section {
            Toggle("Enable Snapmaker", isOn: $settings.snapmakerEnabled)
            if settings.snapmakerEnabled {
                HStack {
                    Text("IP Address")
                    Spacer()
                    TextField("192.168.1.x", text: $settings.snapmakerHost)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if !settings.snapmakerToken.isEmpty {
                    HStack {
                        Text("Token")
                        Spacer()
                        Text(settings.snapmakerToken.prefix(10) + "…")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                Button("Connect Snapmaker") {
                    Task {
                        guard !settings.snapmakerHost.isEmpty else { return }
                        if let url = URL(string: "http://\(settings.snapmakerHost):8080/api/v1/connect"),
                           let (data, _) = try? await URLSession.shared.data(from: url),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                           let token = json["token"] {
                            settings.snapmakerToken = token
                        }
                    }
                }
                .disabled(settings.snapmakerHost.isEmpty)
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(sourceStatusColor(vm.snapmaker.data.status))
                        .imageScale(.small)
                    Text(statusDescription(vm.snapmaker.data))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Snapmaker U1")
        } footer: {
            Text("Polls Snapmaker via HTTP. Tap Connect to authorize (machine will show a confirmation dialog).")
        }
    }

    // MARK: - Pebble

    private var pebbleSection: some View {
        Section {
            HStack {
                Text("Device name filter")
                Spacer()
                TextField("Pebble", text: $settings.pebbleNameFilter)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(pebbleStatusColor)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pebbleStatusText).font(.subheadline)
                    if let name = vm.pebble.watchName {
                        Text(name).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Pebble Watch (BLE)")
        } footer: {
            Text("The app scans for Pebble devices whose name contains the filter string. Make sure the watch is nearby and Bluetooth is on.")
        }
    }

    // MARK: - Glasses

    private var glassesSection: some View {
        Section("Rokid Glasses (TCP :8090)") {
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(vm.glassesConnected ? .green : .gray)
                    .imageScale(.small)
                Text(vm.glassesConnected
                     ? "\(vm.glassesClientCount) glasses connected"
                     : "No glasses connected")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Tempest UDP",  value: ":50222")
            LabeledContent("Snapmaker HTTP", value: ":8080")
            LabeledContent("Pebble BLE",   value: "PPOGATT")
            LabeledContent("Glasses TCP",  value: ":8090")
            LabeledContent("Watchapp UUID", value: watchappUUID.uuidString.prefix(8) + "…")
        }
    }

    // MARK: - Helpers

    private func sourceStatusColor(_ s: SourceStatus) -> Color {
        switch s {
        case .active: return .green
        case .idle:   return .orange
        case .error:  return .red
        case .disconnected: return .gray
        }
    }

    private func statusDescription(_ d: SourceData) -> String {
        switch d.status {
        case .active:       return "Live — \(d.line1)"
        case .idle:         return "Idle"
        case .error:        return "Error"
        case .disconnected: return "Disconnected"
        }
    }

    private var pebbleStatusText: String {
        switch vm.pebble.connectionState {
        case .off:          return "Bluetooth off"
        case .scanning:     return "Scanning for watch…"
        case .connecting:   return "Connecting…"
        case .handshake:    return "Completing handshake…"
        case .connected:    return "Connected"
        case .disconnected: return "Disconnected"
        }
    }

    private var pebbleStatusColor: Color {
        switch vm.pebble.connectionState {
        case .connected:  return .green
        case .scanning, .connecting, .handshake: return .orange
        default:          return .gray
        }
    }
}
