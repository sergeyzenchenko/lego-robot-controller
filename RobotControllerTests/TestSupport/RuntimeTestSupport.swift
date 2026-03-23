import CoreBluetooth
import Foundation
@testable import RobotController

struct RuntimeTestPerception: RobotPerceptionProviding {
    func capturePhoto() async throws -> Data {
        Data()
    }

    func captureDepth() async -> AgentDepthPayload {
        .unavailable
    }
}

@MainActor
final class RuntimeSpeechSynthesizer: RobotSpeechSynthesizing {
    func speak(_ text: String, apiKey: String, voice: String) async {}
}

actor RuntimeCancellationClock: RobotClock {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        if !started {
            started = true
            let continuations = waiters
            waiters.removeAll()
            continuations.forEach { $0.resume() }
        }

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(10))
        }

        throw CancellationError()
    }

    func waitUntilSleepStarts() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@MainActor
final class TransportDelegateSpy: RobotTransportDelegate {
    var phases: [RobotConnectionPhase] = []
    var sensors: [SensorData] = []

    func transportDidChangePhase(_ phase: RobotConnectionPhase) {
        phases.append(phase)
    }

    func transportDidReceiveSensor(_ data: SensorData) {
        sensors.append(data)
    }
}

final class FakeBLECentralManager: BLECentralManaging {
    var state: CBManagerState
    private(set) var stopScanCallCount = 0
    private(set) var scanCallCount = 0
    private(set) var connectedPeripherals: [any BLEPeripheralManaging] = []
    private(set) var cancelledPeripherals: [any BLEPeripheralManaging] = []

    init(state: CBManagerState) {
        self.state = state
    }

    func stopScan() {
        stopScanCallCount += 1
    }

    func scanForPeripherals() {
        scanCallCount += 1
    }

    func connect(_ peripheral: any BLEPeripheralManaging) {
        connectedPeripherals.append(peripheral)
    }

    func cancelPeripheralConnection(_ peripheral: any BLEPeripheralManaging) {
        cancelledPeripherals.append(peripheral)
    }
}

final class FakeBLEPeripheral: BLEPeripheralManaging {
    struct Write {
        let uuid: CBUUID
        let data: Data
    }

    let identifier: UUID
    let name: String?
    weak var delegate: CBPeripheralDelegate?
    private(set) var discoverServicesCallCount = 0
    private(set) var notifyUUIDs: [CBUUID] = []
    private(set) var writes: [Write] = []
    private(set) var discoveredCharacteristicServices = 0

    init(name: String?, identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
    }

    func discoverServices() {
        discoverServicesCallCount += 1
    }

    func discoverCharacteristics(for service: any BLEServiceManaging) {
        discoveredCharacteristicServices += 1
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: any BLECharacteristicManaging) {
        guard enabled else { return }
        notifyUUIDs.append(characteristic.uuid)
    }

    func writeValue(_ data: Data, for characteristic: any BLECharacteristicManaging) {
        writes.append(Write(uuid: characteristic.uuid, data: data))
    }
}

struct FakeBLECharacteristic: BLECharacteristicManaging {
    let uuid: CBUUID
}
