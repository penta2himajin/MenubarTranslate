import Foundation
import Testing
@testable import MenubarTranslateCore

@Suite("CrashLog")
struct CrashLogTests {

    @Test("diagnostic reports match this process by prefix and suffix")
    func matchesOurReports() {
        #expect(CrashLog.isOurDiagnosticReport("MenubarTranslateApp-2026-08-14-213045.ips"))
        #expect(CrashLog.isOurDiagnosticReport("MenubarTranslateApp-2026-08-14-213045.crash"))
        #expect(!CrashLog.isOurDiagnosticReport("Safari-2026-08-14-213045.ips"))
        #expect(CrashLog.isOurDiagnosticReport("MenubarTranslate-2026-08-14-213045.ips"))
        #expect(!CrashLog.isOurDiagnosticReport("MenubarTranslateApp.txt"))
    }

    @Test("harvest copies unseen reports and skips duplicates")
    func harvestCopiesOnce() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("DiagnosticReports", isDirectory: true)
        let dest = root.appendingPathComponent("Logs", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let ours = src.appendingPathComponent("MenubarTranslateApp-1.ips")
        let other = src.appendingPathComponent("Safari-1.ips")
        try "crash".write(to: ours, atomically: true, encoding: .utf8)
        try "nope".write(to: other, atomically: true, encoding: .utf8)

        try CrashLog.harvest(from: src, into: dest, fileManager: fm)
        try CrashLog.harvest(from: src, into: dest, fileManager: fm)

        let copied = try fm.contentsOfDirectory(atPath: dest.path)
        #expect(copied == ["MenubarTranslateApp-1.ips"])
    }

    @Test("console log rotates when it exceeds the size cap")
    func rotatesOversizedConsoleLog() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let log = dir.appendingPathComponent("console.log")
        try Data(repeating: 0x61, count: Int(CrashLog.maxConsoleBytes)).write(to: log)

        try CrashLog.prepareConsoleLog(at: log, fileManager: fm)

        #expect(!fm.fileExists(atPath: log.path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("console.log.old").path))
    }
}
