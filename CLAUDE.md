# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Structure

```
RobotController/
├── RobotControllerApp.swift        — App entry point
├── Models/                         — Data types, enums, Codable structs (no logic)
├── Transport/                      — BLE communication protocol and implementation
├── LLM/                            — LLM provider protocol and API implementations (OpenAI, Gemini, on-device)
├── Perception/                     — Camera capture, LiDAR depth, distance measurement, occupancy grid
├── Agent/                          — Autonomous agent logic: executors, multi-step agent loops, frontier exploration
├── ViewModels/                     — Observable state objects bridging models to views
├── Services/                       — Hardware/OS services: speech recognition, TTS, gamepad input
├── Views/                          — All SwiftUI views and UI components
├── Assets.xcassets/
└── Info.plist
RobotControllerTests/               — Unit tests with MockTransport for hardware-free testing
```
