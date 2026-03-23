import Foundation
import XCTest

extension XCTestCase {
    @MainActor
    func waitUntil(
        timeoutMS: Int = 500,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
