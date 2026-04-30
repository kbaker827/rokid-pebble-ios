import Foundation

/// Polls Snapmaker U1 HTTP API and publishes SourceData.
@MainActor
class SnapmakerSource: ObservableObject {
    @Published var data = SourceData(sourceName: "Snapmaker", sourceIcon: "printer.fill")

    private let settingsStore: SettingsStore
    private var pollTimer: Timer?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func start() {
        guard settingsStore.snapmakerEnabled, !settingsStore.snapmakerHost.isEmpty else { return }
        data.status = .idle
        Task { await poll() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        data.status = .disconnected
    }

    private func poll() async {
        let host = settingsStore.snapmakerHost
        let token = settingsStore.snapmakerToken
        guard !host.isEmpty, !token.isEmpty else { return }
        guard var comps = URLComponents(string: "http://\(host):8080/api/v1/status") else { return }
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        guard let (responseData, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            data.status = .error
            return
        }
        let status  = (json["status"] as? String ?? "UNKNOWN").uppercased()
        let fileName = json["fileName"] as? String ?? ""
        let shortName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let completion = (json["progress"] as? [String: Any])?["completion"] as? Double ?? 0
        let timeLeft   = (json["progress"] as? [String: Any])?["printTimeLeft"] as? Int ?? 0
        let nozzle = ((json["temperature"] as? [String: Any])?["extruder"] as? [String: Any])?["current"] as? Double
        let bed    = ((json["temperature"] as? [String: Any])?["heatedBed"] as? [String: Any])?["current"] as? Double

        let h = timeLeft / 3600, m = (timeLeft % 3600) / 60
        let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        let tempStr = [nozzle.map { "N:\(Int($0))°" }, bed.map { "B:\(Int($0))°" }]
            .compactMap { $0 }.joined(separator: "  ")

        data = SourceData(
            line1: status == "PRINTING" ? "\(shortName)  \(Int(completion))%" : status.capitalized,
            line2: status == "PRINTING" ? "\(timeStr) left  \(tempStr)" : "",
            line3: "",
            status: status == "PRINTING" ? .active : .idle,
            sourceName: "Snapmaker",
            sourceIcon: "printer.fill",
            updatedAt: Date()
        )
    }
}
