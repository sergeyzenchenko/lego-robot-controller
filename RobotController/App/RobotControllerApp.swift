import SwiftUI
import UIKit

@main
struct RobotControllerApp: App {
    private let dependencies = RobotAppDependencies()

    init() {
        // Pre-warm the keyboard so first tap doesn't freeze UI
        if !ProcessInfo.processInfo.isRunningTests {
            KeyboardWarmer.warmUp()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
    }
}

/// Forces iOS to load the keyboard process at launch (off-screen)
/// so the first text field tap doesn't hitch.
enum KeyboardWarmer {
    static func warmUp() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else {
                return
            }

            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            window.isHidden = true
            let field = UITextField(frame: .zero)
            window.addSubview(field)
            window.makeKeyAndVisible()
            field.becomeFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                field.resignFirstResponder()
                field.removeFromSuperview()
                window.isHidden = true
            }
        }
    }
}
