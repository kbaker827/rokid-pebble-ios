import Foundation
import Combine

@MainActor
class HubViewModel: ObservableObject {

    // Sources
    @Published var tempest  = TempestSource()
    @Published var snapmaker: SnapmakerSource

    // Connectivity
    let pebble  = PebbleBLEManager()
    let glasses = GlassesServer()

    @Published var glassesClientCount = 0
    var glassesConnected: Bool { glassesClientCount > 0 }

    // Current active source shown on Pebble (user can cycle with buttons)
    @Published var pebbleSourceIndex = 0

    let settings: SettingsStore
    private var broadcastTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore) {
        self.settings = settings
        self.snapmaker = SnapmakerSource(settingsStore: settings)

        glasses.$clientCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$glassesClientCount)

        // Wire up Pebble button events to cycle through sources
        pebble.session.onButtonEvent = { [weak self] button in
            Task { @MainActor [weak self] in self?.handlePebbleButton(button) }
        }
    }

    // MARK: - Lifecycle

    func start() {
        glasses.start()
        pebble.nameFilter = settings.pebbleNameFilter
        pebble.start()

        if settings.tempestEnabled { tempest.start() }
        if settings.snapmakerEnabled { snapmaker.start() }

        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.broadcast() }
        }
    }

    func stop() {
        broadcastTimer?.invalidate()
        tempest.stop()
        snapmaker.stop()
        pebble.stop()
        glasses.stop()
    }

    // MARK: - Data aggregation

    var activeSources: [SourceData] {
        var out: [SourceData] = []
        if settings.tempestEnabled  { out.append(tempest.data) }
        if settings.snapmakerEnabled { out.append(snapmaker.data) }
        return out
    }

    var summaryData: SourceData {
        let active = activeSources.filter { $0.status == .active }
        if active.isEmpty {
            return SourceData(line1: "No active sources", sourceName: "Hub", sourceIcon: "antenna.radiowaves.left.and.right")
        }
        return SourceData(
            line1: active.map { $0.line1 }.joined(separator: "  "),
            line2: active.count > 1 ? active.map { $0.sourceName }.joined(separator: " + ") : "",
            sourceName: "Summary",
            sourceIcon: "square.grid.2x2.fill",
            updatedAt: active.compactMap { $0.updatedAt }.max() ?? Date()
        )
    }

    // MARK: - Broadcast

    private func broadcast() {
        // Glasses get a rolling summary
        glasses.broadcastSummary(activeSources)

        // Pebble gets the currently-selected source
        let sources = activeSources
        guard !sources.isEmpty else { return }
        let idx = pebbleSourceIndex % sources.count
        pebble.session.sendAppMessage(source: sources[idx])
    }

    // MARK: - Pebble button handling

    private func handlePebbleButton(_ button: Int) {
        let count = activeSources.count
        guard count > 0 else { return }
        switch button {
        case 0:  // up → previous source
            pebbleSourceIndex = (pebbleSourceIndex - 1 + count) % count
        case 2:  // down → next source
            pebbleSourceIndex = (pebbleSourceIndex + 1) % count
        default: break  // select — reserved for future use
        }
        // Push updated source immediately
        let sources = activeSources
        pebble.session.sendAppMessage(source: sources[pebbleSourceIndex % sources.count])
    }

    // MARK: - Alert passthrough

    func sendAlert(_ text: String) {
        glasses.broadcastAlert(text)
    }

    // MARK: - Settings changes

    func applySourceSettings() {
        tempest.stop()
        snapmaker.stop()
        if settings.tempestEnabled  { tempest.start() }
        if settings.snapmakerEnabled { snapmaker.start() }
    }
}
