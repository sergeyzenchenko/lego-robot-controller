# RobotController

A SwiftUI iOS app that controls a **Clementoni RoboMaker START** toy robot over BLE, with LLM-powered autonomous navigation, LiDAR perception, and voice control.

The idea is simple: mount your iPhone on the robot and it becomes the brain. The phone's cameras see the world, its LiDAR measures distances, and an LLM decides what to do next. You can also drive manually with a d-pad or a gamepad, or just tell the robot what to do in natural language.

---

## The Robot

The RoboMaker START (BLE name: `XStRobot`) is a tank-tread educational robot built from Clementoni's Technic-style interlocking pieces. Its BLE protocol was fully reverse-engineered using Python probing scripts (see the parent directory).

**Hardware:**

- 2 DC motors (one per track) — binary on/off through a gearbox, no variable speed
- 4 green LEDs on the brain unit — controlled as left/right pairs
- IR proximity sensor on an articulated arm
- Mechanical gripper/claw (no electronic control)
- 4x AA batteries
- Custom BLE GATT protocol — no standard Bluetooth services

**Calibrated motion:**

| Parameter | Value |
|-----------|-------|
| Forward/backward speed | ~3.5 cm/s |
| Spin turn rate | ~28 deg/s |
| 90-degree turn | ~3.2s |
| 180-degree turn | ~6.4s |

Variable speed is achieved in software via PWM — rapidly toggling the motors on and off at 20 Hz.

---

## App Tabs

The app has six tabs, each a different way to interact with the robot:

### Controls

Manual driving with an on-screen d-pad or a physical gamepad (MFi, Xbox, PS controllers). The left stick drives the tracks, the right stick controls a second robot ("hands" role) if connected. LED toggles are on this screen too.

The gamepad uses software PWM (20 Hz cycle) to provide analog speed control from the joystick — even though the motors are binary on/off.

### Chat

Type a command in natural language (e.g., "drive forward 20cm then turn left"). An LLM parses it into a `RobotPlan` — a structured sequence of motor actions — and executes it immediately. The chat shows the LLM's reasoning, the actions it chose, and execution stats (tokens, latency, tok/s).

Supports voice input via the built-in speech recognizer.

### Autonomous Agent

The most complex mode. Give the robot a high-level task (e.g., "explore the room" or "find the door") and it runs a multi-step **observe-think-act loop**:

1. **Observe** — capture a photo (rear telephoto camera) and LiDAR depth data (5x5 grid, nearest obstacle, clear path distance)
2. **Think** — send the observation + history to an LLM, which returns an `AgentStep`: reasoning, a list of actions, and a decision (`continue` / `done` / `stuck` / `ask_user`)
3. **Act** — execute the actions (move, turn, look around, toggle LEDs, wait)
4. **Repeat** — up to a configurable max steps (default 20)

The agent maintains dead-reckoning position/heading estimates and a full history of observations. It speaks status updates via TTS every few steps. Safety rules prevent driving into obstacles (< 30 cm clearance triggers a turn instead).

Available actions:

| Action | Parameters | Description |
|--------|------------|-------------|
| `move` | direction, distance_cm | Forward/backward, max 35 cm per move |
| `turn` | direction, degrees | Left/right, any angle |
| `look` | direction | Scout left/right/behind — captures photo, returns to original heading |
| `led` | target, status | Toggle left/right/both LEDs on/off |
| `wait` | seconds | Pause |
| `stop` | — | Emergency stop |

### Explore

Frontier-based autonomous exploration — **no LLM needed**. Uses a pure algorithmic approach:

1. Takes LiDAR depth readings and builds an **occupancy grid** (5 cm x 5 cm cells, covering 10 m x 10 m)
2. Raycasts from the robot's position through the depth grid, marking cells as free or occupied
3. Finds **frontiers** — boundaries between known-free and unknown space
4. Navigates to the nearest frontier
5. Repeats until no frontiers remain or max steps reached (default 50)

The UI shows a live canvas rendering of the occupancy grid with the robot's position and heading.

### Depth

LiDAR debug visualization. Shows the raw depth buffer from the phone's LiDAR scanner, useful for understanding what the perception system sees and debugging depth-related issues.

### Voice Agent

Real-time conversational agent using the **OpenAI Realtime API** over WebSocket. You talk to the robot and it talks back — while also being able to see (camera) and act (motors).

The agent has tool-calling capabilities: `act` (execute motor commands with LiDAR + photo capture) and `look` (take a photo without moving). Audio streams bidirectionally over the WebSocket — the phone captures microphone input, sends it to the API, and plays back the model's voice response.

---

## Architecture

```
RobotController/
├── App/                          # Entry point, tab navigation, dependency injection
├── Core/
│   ├── Models/                   # Value types: MotorCommand, LEDState, SensorData, etc.
│   └── Robot/                    # Transport protocol, runtime, connection state machine
├── Features/
│   ├── Autonomous/               # Observe-think-act agent loop + executor
│   ├── Chat/                     # Chat UI, LLM plan generation + execution
│   ├── Controls/                 # D-pad, gamepad control screen
│   ├── Diagnostics/              # LiDAR depth debug visualization
│   ├── Explorer/                 # Frontier-based exploration + occupancy grid
│   └── Realtime/                 # Voice agent (OpenAI Realtime API, WebSocket)
├── Infrastructure/
│   ├── Audio/                    # Speech recognition (VoiceInputManager), TTS (OpenAI)
│   ├── Input/                    # MFi/Xbox/PS gamepad (GameController framework)
│   ├── LLM/                     # LLMProvider protocol + OpenAI, Gemini, on-device
│   ├── Perception/               # Camera, LiDAR depth capture, occupancy grid
│   └── Transport/                # CoreBluetooth BLE implementation
├── Settings/                     # LLM provider/key/model selection (@AppStorage)
└── SharedUI/                     # Connection header, reusable components
```

### Key Design Decisions

- **Protocol-based transport** — `RobotTransport` is a protocol with `writeMotors(_:)` and `writeLEDs(_:)`. `BLETransport` implements it with CoreBluetooth; `MockTransport` enables hardware-free testing.
- **Connection state machine** — BLE connection lifecycle (idle -> scanning -> connecting -> discovering -> ready) is modeled as a state machine with explicit transitions.
- **LLM provider abstraction** — `LLMProvider` protocol with `generatePlan(for:)` method. Swap between OpenAI, Gemini, or on-device without changing any calling code.
- **Structured output** — Agent actions use JSON schemas (via `@Schemable` / JSONSchemaBuilder) to get reliable structured responses from LLMs.
- **Dependency injection** — `RobotAppDependencies` provides factory methods for all major components, making them testable and configurable.

### Perception Pipeline

The phone is mounted on the robot facing forward. The perception system uses:

1. **Rear telephoto camera** — captures photos that are sent to the LLM as base64-encoded images
2. **LiDAR depth** — the `DepthCaptureManager` runs an ARKit session, captures the depth buffer (256x192 landscape, rotated 90 degrees CW for portrait), and produces:
   - A 5x5 grid of depth values (cm) covering the field of view
   - Nearest obstacle distance and direction
   - Clear path ahead distance
   - Confidence indicators per cell
3. **LiDAR measurement** — before/after depth snapshots to estimate actual movement and turn angles
4. **Occupancy grid** — a 2D grid map (5 cm cells) built by raycasting LiDAR depth readings from the robot's estimated position

---

## LLM Providers

Configure in the Settings tab (gear icon on Chat or Voice Agent tabs):

| Provider | Models | Use Case |
|----------|--------|----------|
| **OpenAI** | GPT-4o, GPT-4.1, and compatible | Best quality for autonomous agent |
| **Google Gemini** | Gemini models | Alternative cloud provider |
| **On-device** | Local inference | No API key needed, lower quality |

The autonomous agent and voice agent always use the OpenAI API key for TTS (text-to-speech) regardless of which LLM provider is selected.

---

## Build & Run

### Requirements

- Xcode
- iOS device with BLE (all iPhones)
- LiDAR scanner for depth features (iPhone 12 Pro and later, iPad Pro)
- API key for at least one LLM provider (for chat/agent modes)

### Xcode

```bash
open RobotController.xcodeproj
```

### Command Line

```bash
# Build for device
xcodebuild -project RobotController.xcodeproj \
  -scheme RobotController -sdk iphoneos build

# Run tests (simulator, no hardware needed)
xcodebuild -project RobotController.xcodeproj \
  -scheme RobotController \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### Testing

Tests use a `MockTransport` that records all motor/LED writes for assertion. No physical robot or BLE connection needed. Coverage includes:

- Connection state machine transitions
- Motor command byte encoding
- Robot runtime and command execution
- Autonomous agent support logic
- Realtime agent support
- TTS and voice input
- LiDAR depth math

---

## BLE Protocol

The robot uses a fully custom GATT protocol with no standard Bluetooth services. The protocol was reverse-engineered by decompiling the official Android app and probing with Python scripts.

**UUID prefix:** `ab210776-333a-666b-2018-bdc2924135`

### Characteristics

| Char | UUID suffix | Size | Direction | Purpose |
|------|-------------|------|-----------|---------|
| c1 | `c1` | 6 bytes | App -> Robot | Motor control |
| c2 | `c2` | 1 byte | App -> Robot | LED bitmask |
| b1 | `b1` | — | Robot -> App | Button input (notify) |
| b2 | `b2` | 6 bytes | Robot -> App | Sensor telemetry ~15ms (notify) |
| a3 | `a3` | 20 bytes | App -> Robot | Audio streaming (ADPCM) |
| a4 | `a4` | 6 bytes | App -> Robot | Sensor activation / config |

### Motor Control (c1)

6-byte payload: `[m1_dir, m1_speed, 0x00, m2_dir, m2_speed, 0x00]`

- Direction: `0x00` = brake, `0x01` = forward, `0x02` = backward
- Speed: `0x00` = off, `0x04`-`0xFF` = full speed (binary, no variable). Recommended: `0x80`
- Motor 1 = left track, Motor 2 = right track

```
Forward:    01 80 00 01 80 00
Backward:   02 80 00 02 80 00
Spin left:  01 80 00 02 80 00
Spin right: 02 80 00 01 80 00
Stop:       00 00 00 00 00 00
```

### LED Control (c2)

1-byte bitmask: bit 0 = left pair, bit 1 = right pair.

| Value | Effect |
|-------|--------|
| `0x00` | Both off |
| `0x01` | Left on |
| `0x02` | Right on |
| `0x03` | Both on |

### Sensor Telemetry (b2)

Three little-endian uint16 values at ~15ms intervals:

| Field | Bytes | Idle Range | Notes |
|-------|-------|------------|-------|
| val1 | 0-1 | ~2980-3130 | Likely battery voltage |
| val2 | 2-3 | ~39-52 | Purpose unclear |
| val3 | 4-5 | ~3547-3560 | Inversely tracks val2 |

### Connection Notes

- All writes use **write-without-response**
- Scan by name (`XStRobot`), not by address (varies per host)
- Robot plays a sound on BLE connection
- Auto-disconnects after inactivity
