import Foundation

// MARK: - Connection Phase

enum RobotControllerRole: String, CaseIterable, Identifiable {
    case tracks
    case hands

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tracks:
            return "Tracks"
        case .hands:
            return "Hands"
        }
    }

    var systemImage: String {
        switch self {
        case .tracks:
            return "figure.roll"
        case .hands:
            return "hand.raised.fill"
        }
    }
}

enum RobotConnectionPhase: Equatable {
    case idle
    case unavailable
    case scanning
    case connecting
    case discovering
    case ready
    case disconnecting
    case disconnected

    var displayName: String {
        switch self {
        case .idle, .disconnected:
            return "Disconnected"
        case .unavailable:
            return "Bluetooth Unavailable"
        case .scanning:
            return "Scanning…"
        case .connecting:
            return "Connecting…"
        case .discovering:
            return "Discovering Controls…"
        case .ready:
            return "Connected"
        case .disconnecting:
            return "Disconnecting…"
        }
    }

    var isReady: Bool {
        self == .ready
    }

    var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .discovering, .disconnecting:
            return true
        case .idle, .unavailable, .ready, .disconnected:
            return false
        }
    }
}

// MARK: - Motor Command

enum MotorDirection: UInt8 {
    case brake = 0x00
    case forward = 0x01
    case backward = 0x02
}

struct MotorCommand: Equatable {
    let leftDirection: MotorDirection
    let leftSpeed: UInt8
    let rightDirection: MotorDirection
    let rightSpeed: UInt8

    var data: Data {
        Data([leftDirection.rawValue, leftSpeed, 0x00,
              rightDirection.rawValue, rightSpeed, 0x00])
    }

    static let forward   = MotorCommand(leftDirection: .forward,  leftSpeed: 0x80, rightDirection: .forward,  rightSpeed: 0x80)
    static let backward  = MotorCommand(leftDirection: .backward, leftSpeed: 0x80, rightDirection: .backward, rightSpeed: 0x80)
    static let spinLeft  = MotorCommand(leftDirection: .forward,  leftSpeed: 0x80, rightDirection: .backward, rightSpeed: 0x80)
    static let spinRight = MotorCommand(leftDirection: .backward, leftSpeed: 0x80, rightDirection: .forward,  rightSpeed: 0x80)
    static let stop      = MotorCommand(leftDirection: .brake,    leftSpeed: 0x00, rightDirection: .brake,    rightSpeed: 0x00)

    static func leftOnly(_ direction: MotorDirection, speed: UInt8 = 0x80) -> MotorCommand {
        MotorCommand(
            leftDirection: direction,
            leftSpeed: direction == .brake ? 0x00 : speed,
            rightDirection: .brake,
            rightSpeed: 0x00
        )
    }

    static func rightOnly(_ direction: MotorDirection, speed: UInt8 = 0x80) -> MotorCommand {
        MotorCommand(
            leftDirection: .brake,
            leftSpeed: 0x00,
            rightDirection: direction,
            rightSpeed: direction == .brake ? 0x00 : speed
        )
    }
}

struct RobotPeripheralDescriptor: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String

    var displayName: String {
        let suffix = id.uuidString.suffix(4).uppercased()
        return "\(name) \(suffix)"
    }
}

// MARK: - LED State

struct LEDState: Equatable {
    var left: Bool
    var right: Bool

    var byte: UInt8 {
        var v: UInt8 = 0
        if left  { v |= 0x01 }
        if right { v |= 0x02 }
        return v
    }

    init(left: Bool = false, right: Bool = false) {
        self.left = left
        self.right = right
    }

    init(byte: UInt8) {
        left = byte & 0x01 != 0
        right = byte & 0x02 != 0
    }
}

// MARK: - Sensor Data

struct SensorData: Equatable {
    let val1: UInt16
    let val2: UInt16
    let val3: UInt16

    init(val1: UInt16, val2: UInt16, val3: UInt16) {
        self.val1 = val1
        self.val2 = val2
        self.val3 = val3
    }

    init?(data: Data) {
        guard data.count >= 6 else { return nil }
        val1 = UInt16(data[0]) | (UInt16(data[1]) << 8)
        val2 = UInt16(data[2]) | (UInt16(data[3]) << 8)
        val3 = UInt16(data[4]) | (UInt16(data[5]) << 8)
    }
}
