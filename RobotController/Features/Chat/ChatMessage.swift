import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()

    enum Role {
        case user
        case reasoning
        case action
        case stats
        case error
    }
}
