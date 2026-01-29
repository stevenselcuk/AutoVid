import Foundation

struct Device: Decodable, Hashable, Identifiable, Sendable {
    var id: String { udid }
    let name: String
    let udid: String
    let type: String
    let isUSBConnected: Bool
}

