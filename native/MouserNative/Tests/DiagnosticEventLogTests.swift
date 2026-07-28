import Foundation
import Testing
@testable import MouserNative

@Suite("native diagnostic event log")
struct DiagnosticEventLogTests {
    @Test("keeps only the newest bounded event lines")
    func boundsLines() {
        var log = DiagnosticEventLog(limit: 3)
        log.append("one", timestamp: Date(timeIntervalSince1970: 1))
        log.append("two", timestamp: Date(timeIntervalSince1970: 2))
        log.append("three", timestamp: Date(timeIntervalSince1970: 3))
        log.append("four", timestamp: Date(timeIntervalSince1970: 4))

        #expect(log.lines.count == 3)
        #expect(log.lines.first?.hasSuffix("two") == true)
        #expect(log.lines.last?.hasSuffix("four") == true)
    }
}
