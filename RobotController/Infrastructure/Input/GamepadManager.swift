import GameController
import Combine
import UIKit

// MARK: - Gamepad Manager

@MainActor
final class GamepadManager: ObservableObject {
    @Published var isConnected = false
    @Published var controllerName = ""
    @Published var leftStick: (x: Float, y: Float) = (0, 0)
    @Published var rightStick: (x: Float, y: Float) = (0, 0)

    private var controller: GCController?
    private weak var trackViewModel: RobotViewModel?
    private weak var handsViewModel: RobotViewModel?
    private var didStart = false
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?

    // PWM state for variable speed
    private var drivePWMTask: Task<Void, Never>?
    private var handsPWMTask: Task<Void, Never>?
    private var currentDriveLeftSpeed: Float = 0
    private var currentDriveRightSpeed: Float = 0
    private var currentHandLeftSpeed: Float = 0
    private var currentHandRightSpeed: Float = 0

    // Deadzone
    private static let deadzone: Float = 0.15
    private static let pwmCycleMs: UInt64 = 50 // 20Hz PWM cycle

    func start(trackViewModel: RobotViewModel, handsViewModel: RobotViewModel) {
        guard !ProcessInfo.processInfo.isRunningTests else { return }
        self.trackViewModel = trackViewModel
        self.handsViewModel = handsViewModel
        guard !didStart else { return }
        didStart = true

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            if let gc = note.object as? GCController {
                Task { @MainActor in self?.attach(gc) }
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.detach() }
        }

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppDidBecomeActive() }
        }

        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppWillResignActive() }
        }

        // Check if already connected
        if let gc = GCController.controllers().first {
            attach(gc)
        }

        GCController.startWirelessControllerDiscovery {}
    }

    func stop() {
        didStart = false
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
            self.connectObserver = nil
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
            self.didBecomeActiveObserver = nil
        }
        if let willResignActiveObserver {
            NotificationCenter.default.removeObserver(willResignActiveObserver)
            self.willResignActiveObserver = nil
        }
        GCController.stopWirelessControllerDiscovery()
        drivePWMTask?.cancel()
        handsPWMTask?.cancel()
        detach()
    }

    // MARK: - Attach / Detach

    private func attach(_ gc: GCController) {
        controller = gc
        isConnected = true
        controllerName = gc.productCategory

        if let gamepad = gc.extendedGamepad {
            setupExtendedGamepad(gamepad)
        } else if let gamepad = gc.microGamepad {
            setupMicroGamepad(gamepad)
        }

        startPWMTasks()
        AppLog.debug("[Gamepad] Connected: \(gc.productCategory)")
    }

    private func detach() {
        let wasConnected = controller != nil || isConnected
        controller = nil
        isConnected = false
        controllerName = ""
        leftStick = (0, 0)
        rightStick = (0, 0)
        drivePWMTask?.cancel()
        handsPWMTask?.cancel()
        currentDriveLeftSpeed = 0
        currentDriveRightSpeed = 0
        currentHandLeftSpeed = 0
        currentHandRightSpeed = 0
        trackViewModel?.sendMotor(.stop)
        handsViewModel?.sendMotor(.stop)
        if wasConnected {
            AppLog.debug("[Gamepad] Disconnected")
        }
    }

    // MARK: - Extended Gamepad (PS5, Xbox, etc.)

    private func setupExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        // Left stick → tank drive (arcade style: Y=forward/back, X=turn)
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.leftStick = (x, y)
                self?.updateDriveFromArcade(x: x, y: y)
            }
        }

        // Right stick → hand controller
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.rightStick = (x, y)
                self?.updateHandsFromArcade(x: x, y: y)
            }
        }

        // Buttons
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                guard let self else { return }
                // A = toggle both LEDs
                if pressed {
                    let bothOn = self.trackViewModel?.ledState.left == true && self.trackViewModel?.ledState.right == true
                    if bothOn {
                        self.trackViewModel?.toggleLeftLED()
                        self.trackViewModel?.toggleRightLED()
                    } else {
                        if self.trackViewModel?.ledState.left == false { self.trackViewModel?.toggleLeftLED() }
                        if self.trackViewModel?.ledState.right == false { self.trackViewModel?.toggleRightLED() }
                    }
                }
            }
        }

        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                // B = emergency stop
                if pressed {
                    self?.currentDriveLeftSpeed = 0
                    self?.currentDriveRightSpeed = 0
                    self?.currentHandLeftSpeed = 0
                    self?.currentHandRightSpeed = 0
                    self?.trackViewModel?.sendMotor(.stop)
                    self?.handsViewModel?.sendMotor(.stop)
                }
            }
        }

        // Triggers for individual LEDs
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                if pressed { self?.trackViewModel?.toggleLeftLED() }
            }
        }

        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                if pressed { self?.trackViewModel?.toggleRightLED() }
            }
        }

        // D-pad → feed into the same arcade system as the stick
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                // D-pad gives -1/0/1 values, treat like a digital stick
                self?.updateDriveFromArcade(x: x, y: y)
            }
        }
    }

    // MARK: - Micro Gamepad (Siri Remote)

    private func setupMicroGamepad(_ gamepad: GCMicroGamepad) {
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.updateDriveFromArcade(x: x, y: y)
            }
        }
    }

    // MARK: - Arcade Drive → Tank Speeds

    private func updateDriveFromArcade(x: Float, y: Float) {
        let (left, right) = arcadeSpeeds(x: x, y: y)
        currentDriveLeftSpeed = left
        currentDriveRightSpeed = right
    }

    private func updateHandsFromArcade(x: Float, y: Float) {
        let synced = abs(y) > Self.deadzone ? y : 0
        currentHandLeftSpeed = synced
        currentHandRightSpeed = synced
    }

    private func handleAppDidBecomeActive() {
        guard didStart else { return }
        if let gc = GCController.controllers().first {
            attach(gc)
        } else {
            detach()
            GCController.startWirelessControllerDiscovery {}
        }
    }

    private func handleAppWillResignActive() {
        currentDriveLeftSpeed = 0
        currentDriveRightSpeed = 0
        currentHandLeftSpeed = 0
        currentHandRightSpeed = 0
        leftStick = (0, 0)
        rightStick = (0, 0)
        trackViewModel?.sendMotor(.stop)
        handsViewModel?.sendMotor(.stop)
        drivePWMTask?.cancel()
        handsPWMTask?.cancel()
    }

    private func arcadeSpeeds(x: Float, y: Float) -> (Float, Float) {
        let dx = abs(x) > Self.deadzone ? x : 0
        let dy = abs(y) > Self.deadzone ? y : 0

        // Arcade to tank conversion
        // left = y - x, right = y + x
        let left = max(-1, min(1, dy - dx))
        let right = max(-1, min(1, dy + dx))
        return (left, right)
    }

    // MARK: - PWM Motor Control

    /// Since the robot has binary speed (on/off), we simulate variable speed
    /// by rapidly cycling the motors on/off. At 20Hz with duty cycle proportional
    /// to stick position.
    private func startPWMTasks() {
        drivePWMTask?.cancel()
        handsPWMTask?.cancel()
        drivePWMTask = makePWMTask(
            viewModel: { [weak self] in self?.trackViewModel },
            speeds: { [weak self] in
                guard let self else { return (0, 0) }
                return (self.currentDriveLeftSpeed, self.currentDriveRightSpeed)
            }
        )
        handsPWMTask = makePWMTask(
            viewModel: { [weak self] in self?.handsViewModel },
            speeds: { [weak self] in
                guard let self else { return (0, 0) }
                return (self.currentHandLeftSpeed, self.currentHandRightSpeed)
            }
        )
    }

    private func makePWMTask(
        viewModel: @escaping @MainActor () -> RobotViewModel?,
        speeds: @escaping @MainActor () -> (left: Float, right: Float)
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let vm = viewModel() else { break }

                let (left, right) = speeds()

                if abs(left) < Self.deadzone && abs(right) < Self.deadzone {
                    // Both sticks centered → stop
                    vm.sendMotor(.stop)
                    try? await Task.sleep(for: .milliseconds(Self.pwmCycleMs))
                    continue
                }

                // Full speed threshold — above 0.7, just send constant on
                if abs(left) > 0.7 && abs(right) > 0.7 {
                    vm.sendMotor(Self.makeMotorCommand(left: left, right: right))
                    try? await Task.sleep(for: .milliseconds(Self.pwmCycleMs))
                    continue
                }

                // PWM: on for duty%, off for rest
                let leftDuty = abs(left)
                let rightDuty = abs(right)
                let maxDuty = max(leftDuty, rightDuty)
                let onTimeMs = UInt64(maxDuty * Float(Self.pwmCycleMs))
                let offTimeMs = Self.pwmCycleMs - onTimeMs

                if onTimeMs > 0 {
                    vm.sendMotor(Self.makeMotorCommand(left: left, right: right))
                    try? await Task.sleep(for: .milliseconds(onTimeMs))
                }

                if offTimeMs > 5 {
                    vm.sendMotor(.stop)
                    try? await Task.sleep(for: .milliseconds(offTimeMs))
                }
            }
        }
    }

    private static func makeMotorCommand(left: Float, right: Float) -> MotorCommand {
        let leftDir: UInt8 = abs(left) > deadzone ? (left > 0 ? 0x01 : 0x02) : 0x00
        let rightDir: UInt8 = abs(right) > deadzone ? (right > 0 ? 0x01 : 0x02) : 0x00
        let leftSpd: UInt8 = abs(left) > deadzone ? 0x80 : 0x00
        let rightSpd: UInt8 = abs(right) > deadzone ? 0x80 : 0x00

        return MotorCommand(
            leftDirection: MotorDirection(rawValue: leftDir) ?? .brake,
            leftSpeed: leftSpd,
            rightDirection: MotorDirection(rawValue: rightDir) ?? .brake,
            rightSpeed: rightSpd
        )
    }
}
