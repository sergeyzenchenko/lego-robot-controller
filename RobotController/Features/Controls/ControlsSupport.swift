import Combine
import SwiftUI

@MainActor
final class ControlsScreenCoordinator: ObservableObject {
    let gamepad: GamepadManager
    let scanner: BLERobotScanner
    let assignmentStore: RobotControllerAssignmentStore

    @Published private(set) var selectedTrackPeripheralID: UUID?
    @Published private(set) var selectedHandsPeripheralID: UUID?

    private weak var trackViewModel: RobotViewModel?
    private weak var handsViewModel: RobotViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var didAttemptAutoConnect = false

    convenience init() {
        self.init(
            gamepad: GamepadManager(),
            scanner: BLERobotScanner(),
            assignmentStore: RobotControllerAssignmentStore()
        )
    }

    init(
        gamepad: GamepadManager,
        scanner: BLERobotScanner,
        assignmentStore: RobotControllerAssignmentStore
    ) {
        self.gamepad = gamepad
        self.scanner = scanner
        self.assignmentStore = assignmentStore

        gamepad.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        scanner.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var discoveredRobots: [RobotPeripheralDescriptor] {
        scanner.discoveredRobots
    }

    var isBluetoothUnavailable: Bool {
        switch scanner.bluetoothState {
        case .unsupported, .unauthorized, .poweredOff:
            return true
        default:
            return false
        }
    }

    var isGamepadConnected: Bool {
        gamepad.isConnected
    }

    var controllerName: String {
        gamepad.controllerName
    }

    var leftStick: (x: Float, y: Float) {
        gamepad.leftStick
    }

    var rightStick: (x: Float, y: Float) {
        gamepad.rightStick
    }

    func handleAppear(trackViewModel: RobotViewModel, handsViewModel: RobotViewModel) {
        self.trackViewModel = trackViewModel
        self.handsViewModel = handsViewModel
        syncSelectionsFromTransport()
        gamepad.start(trackViewModel: trackViewModel, handsViewModel: handsViewModel)
        scanner.refresh()
        autoConnectAssignedRobotsIfNeeded()
    }

    func handleDisappear() {
        scanner.stop()
        gamepad.stop()
    }

    func refreshRobots() {
        scanner.refresh()
    }

    func selectedPeripheralID(for role: RobotControllerRole) -> UUID? {
        switch role {
        case .tracks:
            return selectedTrackPeripheralID
        case .hands:
            return selectedHandsPeripheralID
        }
    }

    func selectedPeripheral(for role: RobotControllerRole) -> RobotPeripheralDescriptor? {
        let selection = selectedPeripheralID(for: role)
        return discoveredRobots.first { $0.id == selection }
    }

    func availableRobots(for role: RobotControllerRole) -> [RobotPeripheralDescriptor] {
        let blockedID: UUID?
        switch role {
        case .tracks:
            blockedID = selectedHandsPeripheralID
        case .hands:
            blockedID = selectedTrackPeripheralID
        }

        return discoveredRobots.filter { descriptor in
            descriptor.id != blockedID || descriptor.id == selectedPeripheralID(for: role)
        }
    }

    func selectionLabel(for role: RobotControllerRole) -> String {
        selectedPeripheral(for: role)?.displayName ?? "Select controller"
    }

    func select(_ descriptor: RobotPeripheralDescriptor?, for role: RobotControllerRole) {
        switch role {
        case .tracks:
            selectedTrackPeripheralID = descriptor?.id
            assignmentStore.setPeripheralID(descriptor?.id, for: .tracks)
            if selectedHandsPeripheralID == descriptor?.id {
                selectedHandsPeripheralID = nil
                assignmentStore.setPeripheralID(nil, for: .hands)
            }
        case .hands:
            selectedHandsPeripheralID = descriptor?.id
            assignmentStore.setPeripheralID(descriptor?.id, for: .hands)
            if selectedTrackPeripheralID == descriptor?.id {
                selectedTrackPeripheralID = nil
                assignmentStore.setPeripheralID(nil, for: .tracks)
            }
        }

        syncSelectionsToTransport()
    }

    func connect(role: RobotControllerRole) {
        syncSelectionsToTransport()
        viewModel(for: role)?.connect()
    }

    func disconnect(role: RobotControllerRole) {
        viewModel(for: role)?.disconnect()
    }

    private func viewModel(for role: RobotControllerRole) -> RobotViewModel? {
        switch role {
        case .tracks:
            return trackViewModel
        case .hands:
            return handsViewModel
        }
    }

    private func syncSelectionsFromTransport() {
        let transportTrackID = (trackViewModel?.transport as? BLETransport)?.targetPeripheralIdentifier
        let transportHandsID = (handsViewModel?.transport as? BLETransport)?.targetPeripheralIdentifier
        selectedTrackPeripheralID = transportTrackID ?? assignmentStore.peripheralID(for: .tracks)
        selectedHandsPeripheralID = transportHandsID ?? assignmentStore.peripheralID(for: .hands)
        assignmentStore.setPeripheralID(selectedTrackPeripheralID, for: .tracks)
        assignmentStore.setPeripheralID(selectedHandsPeripheralID, for: .hands)
        syncSelectionsToTransport()
    }

    private func syncSelectionsToTransport() {
        (trackViewModel?.transport as? BLETransport)?.targetPeripheralIdentifier = selectedTrackPeripheralID
        (handsViewModel?.transport as? BLETransport)?.targetPeripheralIdentifier = selectedHandsPeripheralID
    }

    private func autoConnectAssignedRobotsIfNeeded() {
        guard !didAttemptAutoConnect else { return }
        didAttemptAutoConnect = true

        if selectedTrackPeripheralID != nil {
            autoConnect(viewModel: trackViewModel)
        }

        if selectedHandsPeripheralID != nil {
            autoConnect(viewModel: handsViewModel)
        }
    }

    private func autoConnect(viewModel: RobotViewModel?) {
        guard let viewModel else { return }

        switch viewModel.connectionPhase {
        case .idle, .disconnected:
            viewModel.connect()
        case .unavailable, .scanning, .connecting, .discovering, .ready, .disconnecting:
            break
        }
    }
}
