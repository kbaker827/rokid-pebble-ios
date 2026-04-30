import Foundation
import CoreBluetooth

// MARK: - BLE UUIDs (from Gadgetbridge / Pebble open source)

private let watchMainService       = CBUUID(string: "0000FED9-0000-1000-8000-00805F9B34FB")
private let ppogattService         = CBUUID(string: "30000003-328E-0FBB-C642-1AA6699BDADA")
private let ppogattReadChar        = CBUUID(string: "30000004-328E-0FBB-C642-1AA6699BDADA")  // watch→phone
private let ppogattWriteChar       = CBUUID(string: "30000006-328E-0FBB-C642-1AA6699BDADA")  // phone→watch

private let phoneServerService     = CBUUID(string: "10000000-328E-0FBB-C642-1AA6699BDADA")
private let phoneServerWriteChar   = CBUUID(string: "10000001-328E-0FBB-C642-1AA6699BDADA")  // bidirectional data
private let phoneServerReadChar    = CBUUID(string: "10000002-328E-0FBB-C642-1AA6699BDADA")  // phone responds to reads

private let cccdUUID               = CBUUID(string: "00002902-0000-1000-8000-00805F9B34FB")

// MARK: - Connection state

enum PebbleConnectionState: Equatable {
    case off, scanning, connecting, handshake, connected, disconnected
}

// MARK: - Manager

@MainActor
class PebbleBLEManager: NSObject, ObservableObject {

    @Published var connectionState: PebbleConnectionState = .off
    @Published var watchName: String?

    var session = PebbleSession()
    var nameFilter: String = "Pebble"

    // Central (phone connects to watch)
    private var central: CBCentralManager?
    private var pebblePeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?  // phone writes to watch

    // Peripheral (phone acts as GATT server)
    private var peripheralManager: CBPeripheralManager?
    private var serverWriteChar: CBMutableCharacteristic?
    private var serverConnectedCentral: CBCentral?

    override init() {
        super.init()
        session.onSend = { [weak self] data in
            Task { @MainActor [weak self] in self?.sendBLE(data) }
        }
    }

    // MARK: - Start / Stop

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func stop() {
        central?.stopScan()
        if let p = pebblePeripheral { central?.cancelPeripheralConnection(p) }
        peripheralManager?.stopAdvertising()
        connectionState = .disconnected
    }

    // MARK: - Send raw PPOGATT bytes

    private func sendBLE(_ data: Data) {
        // Prefer server path (standard mode) — phone notifies watch via server characteristic
        if let serverWriteChar, let central = serverConnectedCentral {
            peripheralManager?.updateValue(data, for: serverWriteChar, onSubscribedCentrals: [central])
            return
        }
        // Fallback: client-only path — write directly to watch's PPOGATT write characteristic
        if let peripheral = pebblePeripheral, let txChar = txCharacteristic {
            peripheral.writeValue(data, for: txChar, type: .withResponse)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PebbleBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                connectionState = .scanning
                central.scanForPeripherals(withServices: [watchMainService], options: nil)
            } else {
                connectionState = .off
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        Task { @MainActor in
            guard name.localizedCaseInsensitiveContains(nameFilter) else { return }
            self.watchName = name
            self.pebblePeripheral = peripheral
            central.stopScan()
            connectionState = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = .handshake
            peripheral.delegate = self
            peripheral.discoverServices([watchMainService, ppogattService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .disconnected
            txCharacteristic = nil
            // Rescan after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                connectionState = .scanning
                central.scanForPeripherals(withServices: [watchMainService], options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension PebbleBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                if service.uuid == ppogattService {
                    peripheral.discoverCharacteristics([ppogattReadChar, ppogattWriteChar], for: service)
                } else if service.uuid == watchMainService {
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                switch char.uuid {
                case ppogattReadChar:
                    peripheral.setNotifyValue(true, for: char)
                case ppogattWriteChar:
                    txCharacteristic = char
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        Task { @MainActor in
            if characteristic.uuid == ppogattReadChar {
                session.receivePPOGATT(value)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if characteristic.uuid == ppogattReadChar, characteristic.isNotifying {
                // Request larger MTU
                let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
                session.setMTU(mtu)
                connectionState = .connected
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate  (phone acts as GATT server)

extension PebbleBLEManager: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ pm: CBPeripheralManager) {
        Task { @MainActor in
            guard pm.state == .poweredOn else { return }
            setupServer(pm)
        }
    }

    private func setupServer(_ pm: CBPeripheralManager) {
        // Read characteristic — watch reads this; we respond with a static capability byte
        let readChar = CBMutableCharacteristic(
            type: phoneServerReadChar,
            properties: .read,
            value: nil,
            permissions: .readable
        )

        // Write/notify characteristic — watch writes data here AND subscribes to notifications from us
        let writeChar = CBMutableCharacteristic(
            type: phoneServerWriteChar,
            properties: [.writeWithoutResponse, .notify],
            value: nil,
            permissions: .writeable
        )
        serverWriteChar = writeChar

        let service = CBMutableService(type: phoneServerService, primary: true)
        service.characteristics = [readChar, writeChar]
        pm.add(service)
        pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [phoneServerService]])
    }

    nonisolated func peripheralManager(_ pm: CBPeripheralManager, didAdd service: CBService, error: Error?) {}

    nonisolated func peripheralManager(_ pm: CBPeripheralManager, central: CBCentral,
                                       didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in serverConnectedCentral = central }
    }

    nonisolated func peripheralManager(_ pm: CBPeripheralManager, central: CBCentral,
                                       didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in serverConnectedCentral = nil }
    }

    nonisolated func peripheralManager(_ pm: CBPeripheralManager,
                                       didReceiveRead request: CBATTRequest) {
        // Capability response bytes (from Gadgetbridge source)
        request.value = Data([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
        pm.respond(to: request, withResult: .success)
    }

    nonisolated func peripheralManager(_ pm: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            guard req.characteristic.uuid == phoneServerWriteChar,
                  let value = req.value else { continue }
            Task { @MainActor [weak self] in self?.session.receivePPOGATT(value) }
        }
    }
}
