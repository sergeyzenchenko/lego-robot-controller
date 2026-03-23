import XCTest
@testable import RobotController

final class PerceptionMathTests: XCTestCase {

    func testAgentDepthPayloadTextDescriptionForUnavailableLidar() {
        XCTAssertEqual(AgentDepthPayload.unavailable.textDescription, "LiDAR unavailable.")
    }

    func testAgentDepthPayloadTextDescriptionFormatsGridAndWarnings() {
        let payload = AgentDepthPayload(
            grid5x5: [[
                DepthCell(distanceCM: 42, confidence: "low"),
                DepthCell(distanceCM: nil, confidence: "high"),
                DepthCell(distanceCM: 18, confidence: "medium")
            ]],
            nearestObstacleCM: 18,
            nearestObstacleDirection: "left",
            clearPathAheadCM: 55,
            lidarAvailable: true
        )

        let text = payload.textDescription

        XCTAssertTrue(text.contains("Depth grid (5x5, cm, top=far bottom=near, left-to-right):"))
        XCTAssertTrue(text.contains("[42?, -, 18]"))
        XCTAssertTrue(text.contains("Nearest obstacle: 18cm (left)"))
        XCTAssertTrue(text.contains("Clear path ahead: 55cm"))
        XCTAssertTrue(text.contains("WARNING: Object within 20cm dead zone"))
    }

    func testAgentDepthPayloadTextDescriptionAddsCautionForCloseObstacle() {
        let payload = AgentDepthPayload(
            grid5x5: [],
            nearestObstacleCM: 25,
            nearestObstacleDirection: "center",
            clearPathAheadCM: 25,
            lidarAvailable: true
        )

        XCTAssertTrue(payload.textDescription.contains("CAUTION: Very close obstacle"))
    }

    func testRotatedDepthBufferSampleRotatesLandscapeBufferToPortraitCoordinates() {
        let depths: [Float32] = [0, 1, 2, 3, 4, 5]
        let confidences: [UInt8] = [10, 11, 12, 13, 14, 15]

        depths.withUnsafeBufferPointer { depthPtr in
            confidences.withUnsafeBufferPointer { confPtr in
                let buffer = RotatedDepthBuffer(
                    depths: depthPtr.baseAddress!,
                    confs: confPtr.baseAddress!,
                    rawW: 3,
                    rawH: 2
                )

                XCTAssertEqual(buffer.width, 2)
                XCTAssertEqual(buffer.height, 3)

                let topLeft = buffer.sample(x: 0, y: 0)
                let topRight = buffer.sample(x: 1, y: 0)
                let bottomLeft = buffer.sample(x: 0, y: 2)

                XCTAssertEqual(topLeft.0, 3)
                XCTAssertEqual(topLeft.1, 13)
                XCTAssertEqual(topRight.0, 0)
                XCTAssertEqual(topRight.1, 10)
                XCTAssertEqual(bottomLeft.0, 5)
                XCTAssertEqual(bottomLeft.1, 15)
            }
        }
    }

    func testRotatedDepthBufferSampleClampsOutOfRangeCoordinates() {
        let depths: [Float32] = [0, 1, 2, 3, 4, 5]
        let confidences: [UInt8] = [10, 11, 12, 13, 14, 15]

        depths.withUnsafeBufferPointer { depthPtr in
            confidences.withUnsafeBufferPointer { confPtr in
                let buffer = RotatedDepthBuffer(
                    depths: depthPtr.baseAddress!,
                    confs: confPtr.baseAddress!,
                    rawW: 3,
                    rawH: 2
                )

                let sample = buffer.sample(x: -10, y: 99)
                XCTAssertEqual(sample.0, 5)
                XCTAssertEqual(sample.1, 15)
            }
        }
    }

    func testMeasureDistanceCalculatesForwardAndBackwardMovement() {
        let before = makePayload(clearPathAheadCM: 120)
        let forwardAfter = makePayload(clearPathAheadCM: 85)
        let backwardAfter = makePayload(clearPathAheadCM: 150)

        XCTAssertEqual(LiDARMeasurement.measureDistance(before: before, after: forwardAfter, direction: "forward"), 35)
        XCTAssertEqual(LiDARMeasurement.measureDistance(before: before, after: backwardAfter, direction: "backward"), 30)
    }

    func testMeasureDistanceRejectsDeadZoneAndImplausibleReadings() {
        let deadZone = makePayload(clearPathAheadCM: 20)
        let valid = makePayload(clearPathAheadCM: 100)
        let implausible = makePayload(clearPathAheadCM: 400)

        XCTAssertNil(LiDARMeasurement.measureDistance(before: deadZone, after: valid, direction: "forward"))
        XCTAssertNil(LiDARMeasurement.measureDistance(before: valid, after: deadZone, direction: "forward"))
        XCTAssertNil(LiDARMeasurement.measureDistance(before: valid, after: implausible, direction: "backward"))
        XCTAssertNil(LiDARMeasurement.measureDistance(before: .unavailable, after: valid, direction: "forward"))
    }

    func testMeasureTurnDetectsPositiveAndNegativeColumnShifts() {
        let before = makePayload(middleRow: [100, 150, 200, 250, 300])
        let shiftedRight = makePayload(middleRow: [999, 100, 150, 200, 250])
        let shiftedLeft = makePayload(middleRow: [150, 200, 250, 300, 999])

        XCTAssertEqual(LiDARMeasurement.measureTurn(before: before, after: shiftedRight), 8)
        XCTAssertEqual(LiDARMeasurement.measureTurn(before: before, after: shiftedLeft), -8)
    }

    func testMeasureTurnRejectsLowQualityOrSparseRows() {
        let before = makePayload(middleRow: [100, 150, 200, 250, 300])
        let sparse = makePayload(middleRow: [0, 0, 200, 0, 0])
        let poorMatch = makePayload(middleRow: [400, 450, 500, 550, 600])

        XCTAssertNil(LiDARMeasurement.measureTurn(before: before, after: sparse))
        XCTAssertNil(LiDARMeasurement.measureTurn(before: before, after: poorMatch))
        XCTAssertNil(LiDARMeasurement.measureTurn(before: .unavailable, after: before))
    }

    func testLiDARMeasurementFormatsMoveAndTurnLogs() {
        XCTAssertEqual(
            LiDARMeasurement.formatMoveLog(direction: "forward", requestedCM: 20, measuredCM: 24),
            "Moved forward 20cm (LiDAR: 24cm, +4cm)"
        )
        XCTAssertEqual(
            LiDARMeasurement.formatMoveLog(direction: "forward", requestedCM: 20, measuredCM: nil),
            "Moved forward 20cm (LiDAR: n/a)"
        )
        XCTAssertEqual(
            LiDARMeasurement.formatTurnLog(direction: "right", requestedDeg: 90, measuredDeg: -96),
            "Turned right 90° (LiDAR: ~96°, +6°)"
        )
        XCTAssertEqual(
            LiDARMeasurement.formatTurnLog(direction: "left", requestedDeg: 90, measuredDeg: nil),
            "Turned left 90° (LiDAR: n/a)"
        )
    }

    private func makePayload(
        clearPathAheadCM: Int = 100,
        nearestObstacleCM: Int = 100,
        lidarAvailable: Bool = true,
        middleRow: [Int] = [100, 150, 200, 250, 300]
    ) -> AgentDepthPayload {
        let fillerRow = [
            DepthCell(distanceCM: 300, confidence: "high"),
            DepthCell(distanceCM: 300, confidence: "high"),
            DepthCell(distanceCM: 300, confidence: "high"),
            DepthCell(distanceCM: 300, confidence: "high"),
            DepthCell(distanceCM: 300, confidence: "high")
        ]
        let targetRow = middleRow.map { value in
            DepthCell(distanceCM: value > 0 ? value : nil, confidence: value > 20 ? "high" : "low")
        }

        return AgentDepthPayload(
            grid5x5: [fillerRow, fillerRow, targetRow, fillerRow, fillerRow],
            nearestObstacleCM: nearestObstacleCM,
            nearestObstacleDirection: "center",
            clearPathAheadCM: clearPathAheadCM,
            lidarAvailable: lidarAvailable
        )
    }
}
