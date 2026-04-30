import Foundation
import Network

/// Listens on UDP :50222 for Tempest Hub broadcasts and publishes SourceData.
@MainActor
class TempestSource: ObservableObject {
    @Published var data = SourceData(sourceName: "Weather", sourceIcon: "cloud.sun.fill")

    private var listener: NWListener?

    func start() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: 50222),
              let listener = try? NWListener(using: params, on: port) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .utility))
            self?.receive(on: conn)
        }
        listener.start(queue: .global(qos: .utility))
        data.status = .idle
    }

    func stop() {
        listener?.cancel()
        listener = nil
        data.status = .disconnected
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] content, _, isComplete, error in
            if let content, let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any] {
                Task { @MainActor [weak self] in self?.handle(json) }
            }
            if error == nil { self?.receive(on: conn) }
        }
    }

    private func handle(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "obs_st":
            guard let obs = (json["obs"] as? [[Any]])?.first else { return }
            let tempC   = obs[7] as? Double ?? 0
            let tempF   = tempC * 9/5 + 32
            let humidity = obs[8] as? Double ?? 0
            let windAvg = (obs[2] as? Double ?? 0) * 2.237
            let windDir = obs[4] as? Double ?? 0
            let uv      = obs[10] as? Double ?? 0
            let precip  = obs[13] as? Int ?? 0
            let bearing = compassBearing(degrees: windDir)
            let precipLabel = ["Dry","Rain","Hail","Mix"][min(precip, 3)]
            data = SourceData(
                line1: String(format: "%.0f°F  %@ %.0f mph", tempF, bearing, windAvg),
                line2: String(format: "UV %.1f  %@  Hum %.0f%%", uv, precipLabel, humidity),
                line3: "",
                status: .active,
                sourceName: "Weather",
                sourceIcon: "cloud.sun.fill",
                updatedAt: Date()
            )

        case "rapid_wind":
            guard let ob = json["ob"] as? [Any], data.status == .active else { return }
            let speed = (ob[1] as? Double ?? 0) * 2.237
            let dir   = ob[2] as? Double ?? 0
            let bearing = compassBearing(degrees: dir)
            // Update just line1 with rapid wind
            let parts = data.line1.components(separatedBy: "  ")
            if parts.count >= 1 {
                data.line1 = "\(parts[0])  \(bearing) \(String(format: "%.0f", speed)) mph"
                data.updatedAt = Date()
            }
        default: break
        }
    }

    private func compassBearing(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return dirs[Int((degrees / 22.5).rounded()) % 16]
    }
}
