import Foundation
import Testing
@testable import MenubarTranslateCore

@Suite("AppLog")
struct AppLogTests {

    @Test("formats a structured line with level, category, message, and fields")
    func formatsLine() {
        let line = AppLog.format(
            level: .info,
            category: .history,
            message: "coalesce",
            fields: ["action": "update", "count": "1"],
            date: Date(timeIntervalSince1970: 1_724_000_000)
        )
        #expect(line.hasPrefix("2024-08-18T"))
        #expect(line.contains(" level=info"))
        #expect(line.contains(" cat=history"))
        #expect(line.contains(" msg=coalesce"))
        #expect(line.contains(" action=update"))
        #expect(line.contains(" count=1"))
        #expect(line.hasSuffix("\n"))
    }

    @Test("respects minimum level via sink capture when emitting")
    func writesThroughSink() {
        final class Box: @unchecked Sendable {
            var lines: [String] = []
        }
        let box = Box()
        let previous = AppLog.sink
        AppLog.sink = { box.lines.append($0) }
        defer { AppLog.sink = previous }

        AppLog.info(.history, "keep")
        AppLog.error(.translate, "err", ["code": "unavailable"])
        #expect(box.lines.count >= 2)
        #expect(box.lines.contains { $0.contains("msg=keep") })
        #expect(box.lines.contains { $0.contains("level=error") && $0.contains("code=unavailable") })
    }

    @Test("escapes spaces in field values")
    func escapesSpaces() {
        let line = AppLog.format(
            level: .debug,
            category: .translate,
            message: "done",
            fields: ["src": "hello world"],
            date: Date(timeIntervalSince1970: 0)
        )
        #expect(line.contains("src=hello_world"))
    }

    @Test("MBT_LOG_LEVEL parses known levels and defaults to debug")
    func envLevel() {
        #expect(AppLog.Level.parse("error") == .error)
        #expect(AppLog.Level.parse("WARN") == .warn)
        #expect(AppLog.Level.parse("info") == .info)
        #expect(AppLog.Level.parse("debug") == .debug)
        #expect(AppLog.Level.parse(nil) == .debug)
        #expect(AppLog.Level.parse("nope") == .debug)
    }
}
