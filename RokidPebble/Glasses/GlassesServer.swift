import Foundation
import Network

@MainActor
class GlassesServer: ObservableObject {
    @Published var clientCount = 0

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    static let tcpPort: UInt16 = 8090

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Self.tcpPort),
              let listener = try? NWListener(using: params, on: port) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        listener.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        clientCount = 0
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        clientCount = connections.count
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self] in self?.remove(id) }
            default: break
            }
        }
        conn.start(queue: .global(qos: .utility))
    }

    private func remove(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
        clientCount = connections.count
    }

    func broadcastSummary(_ sources: [SourceData]) {
        let active = sources.filter { $0.status == .active }
        let lines = active.map { "\($0.sourceIcon.isEmpty ? "" : "")\($0.sourceName): \($0.line1)" }
        let text  = lines.isEmpty ? "No active sources" : lines.joined(separator: "  |  ")
        send(["type": "summary", "text": text, "sources": active.count])
    }

    func broadcastSource(_ source: SourceData) {
        send([
            "type": "source",
            "sourceName": source.sourceName,
            "line1": source.line1,
            "line2": source.line2,
            "line3": source.line3,
            "status": "\(source.status)"
        ])
    }

    func broadcastAlert(_ text: String) {
        send(["type": "alert", "text": text])
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }
        let payload = Data((str + "\n").utf8)
        for conn in connections.values {
            conn.send(content: payload, completion: .idempotent)
        }
    }
}
