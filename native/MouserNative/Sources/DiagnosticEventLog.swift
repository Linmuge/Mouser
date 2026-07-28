import Foundation

struct DiagnosticEventLog: Equatable, Sendable {
    let limit: Int
    private(set) var lines: [String] = []

    init(limit: Int = 200) {
        self.limit = max(1, limit)
    }

    mutating func append(_ message: String, timestamp: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        lines.append("[\(formatter.string(from: timestamp))] \(message)")
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }

    mutating func clear() {
        lines.removeAll(keepingCapacity: true)
    }
}
