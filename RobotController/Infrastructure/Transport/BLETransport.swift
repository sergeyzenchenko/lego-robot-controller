import Foundation
import CoreBluetooth

// MARK: - BLE UUIDs

enum RobotUUID {
    static let controlService   = CBUUID(string: "ab210776-333a-666b-2018-bdc2924135c0")
    static let secondaryService = CBUUID(string: "ab210776-333a-666b-2018-bdc2924135a0")
    static let motors = CBUUID(string: "ab210776-333a-666b-2018-bdc2924135c1")
    static let leds   = CBUUID(string: "ab210776-333a-666b-2018-bdc2924135c2")
    static let button = CBUUID(string: "ab210776-333a-666b-2018-bdc2924135b1")
    static let sensor = CBUUID(string: "ab210776-333a-666b-2018-bdc2924135b2")
}

// MARK: - BLE Transport

@MainActor
final class BLETransport: NSObject, RobotTransport {
    weak var delegate: RobotTransportDelegate?
    var targetPeripheralIdentifier: UUID?

    private var centralManager: (any BLECentralManaging)!
    private var peripheral: (any BLEPeripheralManaging)?
    private var motorsChar: (any BLECharacteristicManaging)?
    private var ledsChar: (any BLECharacteristicManaging)?
    private var scanTimeoutTask: Task<Void, Never>?
    private var connectionStateMachine = RobotConnectionStateMachine()

    override init() {
        super.init()
        centralManager = CoreBluetoothCentralManagerAdapter(delegate: self)
    }

    init(
        targetPeripheralIdentifier: UUID? = nil,
        centralManager: any BLECentralManaging
    ) {
        super.init()
        self.targetPeripheralIdentifier = targetPeripheralIdentifier
        self.centralManager = centralManager
    }

    convenience init(centralManager: any BLECentralManaging) {
        self.init(targetPeripheralIdentifier: nil, centralManager: centralManager)
    }

    func connect() {
        guard centralManager.state == .poweredOn else {
            publish(.bluetoothUnavailable)
            return
        }
        centralManager.stopScan()
        peripheral = nil
        motorsChar = nil
        ledsChar = nil
        publish(.connectRequested)
        centralManager.scanForPeripherals()
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            centralManager.stopScan()
            publish(.scanTimedOut)
        }
    }

    func disconnect() {
        scanTimeoutTask?.cancel()
        centralManager.stopScan()
        if let peripheral {
            publish(.disconnectRequested(hasPeripheral: true))
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            publish(.disconnectRequested(hasPeripheral: false))
        }
    }

    func writeMotors(_ data: Data) {
        guard let motorsChar, let peripheral else { return }
        peripheral.writeValue(data, for: motorsChar)
    }

    func writeLEDs(_ data: Data) {
        guard let ledsChar, let peripheral else { return }
        peripheral.writeValue(data, for: ledsChar)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                guard self.peripheral == nil else { return }
                self.publish(.bluetoothReady)
            default:
                self.scanTimeoutTask?.cancel()
                self.peripheral = nil
                self.motorsChar = nil
                self.ledsChar = nil
                self.publish(.bluetoothUnavailable)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            self.handleDiscoveredPeripheral(CoreBluetoothPeripheralAdapter(peripheral))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.handleConnectedPeripheral(CoreBluetoothPeripheralAdapter(peripheral))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.peripheral = nil
            self.motorsChar = nil
            self.ledsChar = nil
            self.publish(.peripheralDisconnected)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services?.map(CoreBluetoothServiceAdapter.init) ?? []
        Task { @MainActor in
            self.handleDiscoveredServices(on: CoreBluetoothPeripheralAdapter(peripheral), services: services)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let wrappedPeripheral = CoreBluetoothPeripheralAdapter(peripheral)
        let characteristics = service.characteristics?.map(CoreBluetoothCharacteristicAdapter.init) ?? []
        Task { @MainActor in
            self.handleDiscoveredCharacteristics(on: wrappedPeripheral, characteristics: characteristics)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            self.handleSensorData(characteristic.value, characteristicUUID: characteristic.uuid)
        }
    }
}

extension BLETransport {
    func handleDiscoveredPeripheral(_ peripheral: any BLEPeripheralManaging) {
        guard peripheral.name == "XStRobot" else { return }
        if let targetPeripheralIdentifier, peripheral.identifier != targetPeripheralIdentifier {
            return
        }
        centralManager.stopScan()
        scanTimeoutTask?.cancel()
        self.peripheral = peripheral
        publish(.peripheralDiscovered)
        peripheral.delegate = self
        centralManager.connect(peripheral)
    }

    func handleConnectedPeripheral(_ peripheral: any BLEPeripheralManaging) {
        publish(.peripheralConnected)
        peripheral.discoverServices()
    }

    func handleDiscoveredServices(on peripheral: any BLEPeripheralManaging, services: [any BLEServiceManaging]) {
        for service in services {
            peripheral.discoverCharacteristics(for: service)
        }
    }

    func handleDiscoveredCharacteristics(
        on peripheral: any BLEPeripheralManaging,
        characteristics: [any BLECharacteristicManaging]
    ) {
        for characteristic in characteristics {
            switch characteristic.uuid {
            case RobotUUID.motors:
                motorsChar = characteristic
                publishConnectedIfReady()
            case RobotUUID.leds:
                ledsChar = characteristic
                publishConnectedIfReady()
            case RobotUUID.sensor, RobotUUID.button:
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }

    func handleSensorData(_ data: Data?, characteristicUUID: CBUUID) {
        guard characteristicUUID == RobotUUID.sensor else { return }
        guard let data, let parsed = SensorData(data: data) else { return }
        delegate?.transportDidReceiveSensor(parsed)
    }
}

private extension BLETransport {
    func publish(_ event: RobotConnectionEvent) {
        let phase = connectionStateMachine.handle(event)
        delegate?.transportDidChangePhase(phase)
    }

    func publishConnectedIfReady() {
        guard peripheral != nil, motorsChar != nil, ledsChar != nil else { return }
        publish(.characteristicsReady)
    }
}

@MainActor
final class BLERobotScanner: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState
    @Published private(set) var discoveredRobots: [RobotPeripheralDescriptor] = []

    private var centralManager: (any BLECentralManaging)!
    private var scanTimeoutTask: Task<Void, Never>?

    override init() {
        self.bluetoothState = .unknown
        super.init()
        centralManager = CoreBluetoothCentralManagerAdapter(delegate: self)
    }

    init(centralManager: any BLECentralManaging) {
        self.centralManager = centralManager
        self.bluetoothState = centralManager.state
        super.init()
    }

    func refresh() {
        scanTimeoutTask?.cancel()
        discoveredRobots = []

        guard centralManager.state == .poweredOn else {
            bluetoothState = centralManager.state
            return
        }

        bluetoothState = .poweredOn
        centralManager.stopScan()
        centralManager.scanForPeripherals()
        scanTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            centralManager.stopScan()
        }
    }

    func stop() {
        scanTimeoutTask?.cancel()
        centralManager.stopScan()
    }
}

extension BLERobotScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            if central.state != .poweredOn {
                self.scanTimeoutTask?.cancel()
                self.discoveredRobots = []
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            self.record(CoreBluetoothPeripheralAdapter(peripheral))
        }
    }
}

private extension BLERobotScanner {
    func record(_ peripheral: any BLEPeripheralManaging) {
        guard peripheral.name == "XStRobot" else { return }

        let descriptor = RobotPeripheralDescriptor(
            id: peripheral.identifier,
            name: peripheral.name ?? "XStRobot"
        )

        guard !discoveredRobots.contains(descriptor) else { return }
        discoveredRobots.append(descriptor)
        discoveredRobots.sort { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name < rhs.name
        }
    }
}
