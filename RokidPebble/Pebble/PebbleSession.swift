import Foundation

// MARK: - PPOGATT + Pebble Protocol session
//
// PPOGATT packet format:
//   byte 0: header = (serial << 3) | command
//     cmd 0 = data, cmd 1 = ACK, cmd 2 = setup req, cmd 3 = setup resp
//   bytes 1+: Pebble Protocol data (command 0 only)
//
// Pebble Protocol message format (big-endian):
//   [length: 2B][endpoint: 2B][payload...]
//
// App Message (endpoint 48) payload:
//   [cmd:1][txId:1][uuid:16][tupleCount:1][tuples... (little-endian)]
//   Tuple: [key:4B LE][type:1][len:2B LE][value...]
//     Types: 0=BYTEARRAY 1=CSTRING 2=UINT 3=INT

final class PebbleSession {

    // MARK: - Constants

    private static let endpointPhoneVersion: UInt16 = 17
    private static let endpointApplicationMessage: UInt16 = 48
    private static let endpointPing: UInt16 = 2001

    private static let appMsgPush: UInt8 = 0x01
    private static let appMsgAck:  UInt8 = 0xFF

    // MARK: - Callbacks

    /// Called when a framed Pebble Protocol message is ready to send over BLE
    var onSend: ((Data) -> Void)?
    /// Called when the watch sends a button press App Message
    var onButtonEvent: ((Int) -> Void)?

    // MARK: - State

    private var rxBuffer = Data()
    private var rxSerial = -1
    private var txSerial = 0
    private var txId: UInt8 = 0
    private var mtu = 20  // bytes; updated after negotiation

    func setMTU(_ mtu: Int) { self.mtu = max(mtu, 20) }

    // MARK: - Receive (from BLE layer)

    func receivePPOGATT(_ data: Data) {
        guard !data.isEmpty else { return }
        let header  = data[0]
        let command = Int(header & 0x07)
        let serial  = Int(header >> 3)

        switch command {
        case 0x02:  // setup request from watch
            let response: [UInt8] = data.count > 1 ? [0x03, 0x19, 0x19] : [0x03]
            onSend?(Data(response))

        case 0x00:  // data packet
            sendPPOGATTAck(serial: serial)
            rxBuffer.append(data.dropFirst())
            parsePebbleProtocol()

        case 0x01:  // ACK — nothing needed
            break

        default:
            break
        }
    }

    // MARK: - Pebble Protocol parser

    private func parsePebbleProtocol() {
        while rxBuffer.count >= 4 {
            let length   = UInt16(rxBuffer[0]) << 8 | UInt16(rxBuffer[1])
            let endpoint = UInt16(rxBuffer[2]) << 8 | UInt16(rxBuffer[3])
            let total    = 4 + Int(length)
            guard rxBuffer.count >= total else { break }
            let payload  = rxBuffer.subdata(in: 4 ..< total)
            rxBuffer.removeFirst(total)
            handleEndpoint(endpoint, payload: payload)
        }
    }

    private func handleEndpoint(_ endpoint: UInt16, payload: Data) {
        switch endpoint {
        case Self.endpointPhoneVersion:
            sendPhoneVersion()

        case Self.endpointApplicationMessage:
            guard payload.count >= 18 else { return }
            let cmd = payload[0]
            let id  = payload[1]
            if cmd == Self.appMsgPush {
                // ACK it back
                let uuidBytes = payload.subdata(in: 2 ..< 18)
                sendAppMessageAck(id: id, uuidData: uuidBytes)
                // Parse dict for button events
                parseAppMessageDict(payload: payload.dropFirst(18))
            }

        case Self.endpointPing:
            // Pong
            guard payload.count >= 5 else { return }
            var pong = Data([0x01])
            pong.append(payload.subdata(in: 1 ..< 5))  // echo cookie
            sendPebbleProtocol(endpoint: Self.endpointPing, payload: pong)

        default:
            break
        }
    }

    // MARK: - App Message dict parsing

    private func parseAppMessageDict(payload: Data) {
        guard !payload.isEmpty else { return }
        var offset = 0
        let tupleCount = Int(payload[offset]); offset += 1
        for _ in 0 ..< tupleCount {
            guard offset + 7 <= payload.count else { break }
            let key    = Int(payload[offset]) | Int(payload[offset+1]) << 8 | Int(payload[offset+2]) << 16 | Int(payload[offset+3]) << 24
            let type   = payload[offset+4]
            let length = Int(payload[offset+5]) | Int(payload[offset+6]) << 8
            offset += 7
            guard offset + length <= payload.count else { break }
            if key == PebbleKey.buttonEvent.rawValue, (type == 2 || type == 3), length >= 1 {
                onButtonEvent?(Int(payload[offset]))
            }
            offset += length
        }
    }

    // MARK: - Send App Message (phone → watch)

    func sendAppMessage(source: SourceData) {
        var payload = Data()
        payload.append(Self.appMsgPush)
        payload.append(txId); txId &+= 1

        // UUID (big-endian, 16 bytes)
        let uuid = watchappUUID
        var msb = uuid.uuid.0; withUnsafeBytes(of: uuid.uuid) { raw in
            payload.append(contentsOf: raw.prefix(16))
        }
        _ = msb  // suppress unused warning

        // 4 tuples: sourceName, line1, line2, line3
        let tuples: [(PebbleKey, String)] = [
            (.sourceName, source.sourceName),
            (.line1,      source.line1),
            (.line2,      source.line2),
            (.line3,      source.line3)
        ]
        payload.append(UInt8(tuples.count))
        for (key, value) in tuples {
            appendStringTuple(to: &payload, key: key.rawValue, value: value)
        }

        sendPebbleProtocol(endpoint: Self.endpointApplicationMessage, payload: payload)
    }

    private func appendStringTuple(to data: inout Data, key: Int, value: String) {
        let bytes = Array(value.utf8) + [0]  // null-terminated
        appendLE32(&data, UInt32(key))
        data.append(0x01)  // CSTRING
        appendLE16(&data, UInt16(bytes.count))
        data.append(contentsOf: bytes)
    }

    // MARK: - ACK / phone version

    private func sendAppMessageAck(id: UInt8, uuidData: Data) {
        var payload = Data([Self.appMsgAck, id])
        payload.append(uuidData)
        sendPebbleProtocol(endpoint: Self.endpointApplicationMessage, payload: payload)
    }

    private func sendPhoneVersion() {
        // 25-byte payload (endpoint 17 response)
        var payload = Data()
        payload.append(0x01)                                  // response cmd
        appendBE32(&payload, 0xFFFFFFFF)                      // session caps
        appendBE32(&payload, 0x00000000)                      // remote caps
        appendBE32(&payload, 0x00000001)                      // OS = iOS
        payload.append(contentsOf: [0x02, 0x04, 0x01, 0x01]) // magic + version
        appendLE64(&payload, 0x00000000000029AF)              // flags
        sendPebbleProtocol(endpoint: Self.endpointPhoneVersion, payload: payload)
    }

    // MARK: - Protocol framing

    private func sendPebbleProtocol(endpoint: UInt16, payload: Data) {
        var msg = Data()
        appendBE16(&msg, UInt16(payload.count))
        appendBE16(&msg, endpoint)
        msg.append(payload)
        sendFragmented(msg)
    }

    private func sendFragmented(_ data: Data) {
        let chunkSize = max(mtu - 1, 1)
        var offset = 0
        while offset < data.count {
            let end   = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset ..< end)
            var packet = Data([UInt8((txSerial << 3) | 0x00)])
            packet.append(chunk)
            onSend?(packet)
            txSerial = (txSerial + 1) % 32
            offset = end
        }
    }

    private func sendPPOGATTAck(serial: Int) {
        onSend?(Data([UInt8((serial << 3) | 0x01)]))
    }

    // MARK: - Byte helpers

    private func appendBE16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF))
    }
    private func appendBE32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v >> 24)); d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8(v & 0xFF))
    }
    private func appendLE16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8))
    }
    private func appendLE32(_ d: inout Data, _ v: UInt32) {
        for i in 0..<4 { d.append(UInt8((v >> (i*8)) & 0xFF)) }
    }
    private func appendLE64(_ d: inout Data, _ v: UInt64) {
        for i in 0..<8 { d.append(UInt8((v >> (i*8)) & 0xFF)) }
    }
}
