# RobotController

A SwiftUI iOS app that controls a **Clementoni RoboMaker START** toy robot over BLE, with LLM-powered autonomous navigation, LiDAR perception, and voice control. Mount your iPhone on the robot and it becomes the brain — using its cameras and LiDAR as the perception system.

## The Robot

The RoboMaker START (BLE name: `XStRobot`) is a tank-tread educational robot with:

- **2 DC motors** (one per track) — binary on/off, ~3.5 cm/s forward, ~28 deg/s turning
- **4 green LEDs** — controlled as left/right pairs
- **IR proximity sensor** on an articulated arm
- **Custom BLE GATT protocol** — no standard services, fully reverse-engineered

## Features

| Mode | Description |
|------|-------------|
| **Manual Control** | D-pad UI or MFi/Xbox/PS gamepad |
| **Chat** | Describe a task in natural language; an LLM generates and executes a movement plan |
| **Autonomous Agent** | Multi-turn observe-think-act loop: camera + LiDAR data sent to an LLM, which decides the next action |
| **Frontier Explorer** | Grid-based autonomous exploration using an occupancy map built from LiDAR depth data |
| **Realtime Voice** | Real-time voice + vision agent via OpenAI Realtime API over WebSocket |
| **Diagnostics** | LiDAR depth debug visualization |

## Architecture

```
RobotController/
├── App/                          # Entry point, tab navigation, dependencies
├── Core/
│   ├── Models/                   # Value types, Codable structs, JSON schemas
│   └── Robot/                    # Transport protocol, runtime, connection state machine
├── Features/
│   ├── Autonomous/               # LLM-powered observe-think-act agent + executor
│   ├── Chat/                     # Chat UI, plan generation + execution
│   ├── Controls/                 # Manual d-pad and gamepad control
│   ├── Diagnostics/              # LiDAR depth debug visualization
│   ├── Explorer/                 # Frontier-based exploration with occupancy grid
│   └── Realtime/                 # Real-time voice + vision agent (WebSocket)
├── Infrastructure/
│   ├── Audio/                    # Speech recognition, TTS (OpenAI)
│   ├── Input/                    # MFi/Xbox/PS gamepad support
│   ├── LLM/                     # Provider protocol + OpenAI, Gemini, on-device
│   ├── Perception/               # Camera capture, LiDAR depth, occupancy grid
│   └── Transport/                # CoreBluetooth BLE implementation
├── Settings/                     # LLM provider/key/model selection
└── SharedUI/                     # Reusable UI components (connection header)
```

### Perception Stack

- **Camera** — rear telephoto camera (phone mounted on robot, facing forward)
- **LiDAR** — 5x5 depth grid, nearest obstacle detection, clear path analysis
- **LiDAR Measurement** — before/after depth comparison for movement and turn estimation
- **Occupancy Grid** — spatial map built incrementally from depth frames

### LLM Providers

Configure in the Settings tab:

- **OpenAI** — GPT-4o and compatible models
- **Google Gemini**
- **On-device** — local inference

## Build & Run

```bash
# Open in Xcode
open RobotController.xcodeproj

# Command-line build
xcodebuild -project RobotController.xcodeproj \
  -scheme RobotController -sdk iphoneos build

# Run tests
xcodebuild -project RobotController.xcodeproj \
  -scheme RobotController \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Requires Xcode and an iOS device with BLE. LiDAR features require a device with a LiDAR scanner (iPhone Pro/iPad Pro).

## BLE Protocol

The robot uses a custom GATT protocol (UUID prefix: `ab210776-333a-666b-2018-bdc2924135`):

| Characteristic | Size | Direction | Purpose |
|----------------|------|-----------|---------|
| `c1` | 6 bytes | App -> Robot | Motor control `[m1_dir, m1_speed, 0, m2_dir, m2_speed, 0]` |
| `c2` | 1 byte | App -> Robot | LED bitmask (bit 0 = left, bit 1 = right) |
| `b2` | 6 bytes | Robot -> App | Sensor telemetry at ~15ms (notify) |

**Motor commands:**

```
Forward:    01 80 00 01 80 00
Backward:   02 80 00 02 80 00
Spin left:  01 80 00 02 80 00
Spin right: 02 80 00 01 80 00
Stop:       00 00 00 00 00 00
```

All writes use write-without-response. Speed byte `0x80` is recommended (binary on/off, no variable speed).
