import CoreBluetooth
import Foundation

protocol BLECentralManaging: AnyObject {
    var state: CBManagerState { get }
    func stopScan()
    func scanForPeripherals()
    func connect(_ peripheral: any BLEPeripheralManaging)
    func cancelPeripheralConnection(_ peripheral: any BLEPeripheralManaging)
}

protocol BLEPeripheralManaging: AnyObject {
    var identifier: UUID { get }
    var name: String? { get }
    var delegate: CBPeripheralDelegate? { get set }

    func discoverServices()
    func discoverCharacteristics(for service: any BLEServiceManaging)
    func setNotifyValue(_ enabled: Bool, for characteristic: any BLECharacteristicManaging)
    func writeValue(_ data: Data, for characteristic: any BLECharacteristicManaging)
}

protocol BLEServiceManaging {
    var characteristics: [any BLECharacteristicManaging]? { get }
}

protocol BLECharacteristicManaging {
    var uuid: CBUUID { get }
}

final class CoreBluetoothCentralManagerAdapter: NSObject, BLECentralManaging {
    private let manager: CBCentralManager

    init(delegate: CBCentralManagerDelegate) {
        self.manager = CBCentralManager(delegate: delegate, queue: nil)
        super.init()
    }

    var state: CBManagerState { manager.state }

    func stopScan() {
        manager.stopScan()
    }

    func scanForPeripherals() {
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func connect(_ peripheral: any BLEPeripheralManaging) {
        guard let peripheral = peripheral as? CoreBluetoothPeripheralAdapter else { return }
        manager.connect(peripheral.peripheral, options: nil)
    }

    func cancelPeripheralConnection(_ peripheral: any BLEPeripheralManaging) {
        guard let peripheral = peripheral as? CoreBluetoothPeripheralAdapter else { return }
        manager.cancelPeripheralConnection(peripheral.peripheral)
    }
}

final class CoreBluetoothPeripheralAdapter: BLEPeripheralManaging {
    let peripheral: CBPeripheral

    init(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    var identifier: UUID { peripheral.identifier }

    var name: String? { peripheral.name }

    var delegate: CBPeripheralDelegate? {
        get { peripheral.delegate }
        set { peripheral.delegate = newValue }
    }

    func discoverServices() {
        peripheral.discoverServices([RobotUUID.controlService, RobotUUID.secondaryService])
    }

    func discoverCharacteristics(for service: any BLEServiceManaging) {
        guard let service = service as? CoreBluetoothServiceAdapter else { return }
        peripheral.discoverCharacteristics(nil, for: service.service)
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: any BLECharacteristicManaging) {
        guard let characteristic = characteristic as? CoreBluetoothCharacteristicAdapter else { return }
        peripheral.setNotifyValue(enabled, for: characteristic.characteristic)
    }

    func writeValue(_ data: Data, for characteristic: any BLECharacteristicManaging) {
        guard let characteristic = characteristic as? CoreBluetoothCharacteristicAdapter else { return }
        peripheral.writeValue(data, for: characteristic.characteristic, type: .withoutResponse)
    }
}

struct CoreBluetoothServiceAdapter: BLEServiceManaging {
    let service: CBService

    var characteristics: [any BLECharacteristicManaging]? {
        service.characteristics?.map(CoreBluetoothCharacteristicAdapter.init)
    }
}

struct CoreBluetoothCharacteristicAdapter: BLECharacteristicManaging {
    let characteristic: CBCharacteristic

    var uuid: CBUUID { characteristic.uuid }
}
