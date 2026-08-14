import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Local crash capture for the menu-bar app.
///
/// macOS Crash Reporter still writes `.ips` files; this also keeps stderr
/// (llama.cpp / ggml aborts) and copies those reports into
/// `~/Library/Logs/MenubarTranslate` so a Dock-less accessory process is
/// inspectable without Console.app.
public enum CrashLog {
    public static let maxConsoleBytes: UInt64 = 5 * 1024 * 1024

    private static let processPrefix = "MenubarTranslate"

    public static func logsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MenubarTranslate", isDirectory: true)
    }

    public static func isOurDiagnosticReport(_ filename: String) -> Bool {
        filename.hasPrefix(processPrefix)
            && (filename.hasSuffix(".ips") || filename.hasSuffix(".crash"))
    }

    public static func harvest(
        from diagnosticDir: URL,
        into destDir: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: diagnosticDir.path) else { return }
        let items = try fileManager.contentsOfDirectory(
            at: diagnosticDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in items where isOurDiagnosticReport(url.lastPathComponent) {
            let dest = destDir.appendingPathComponent(url.lastPathComponent)
            if !fileManager.fileExists(atPath: dest.path) {
                try fileManager.copyItem(at: url, to: dest)
            }
        }
    }

    public static func prepareConsoleLog(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? UInt64) ?? 0
        guard size >= maxConsoleBytes else { return }
        let bak = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".old")
        try? fileManager.removeItem(at: bak)
        try fileManager.moveItem(at: url, to: bak)
    }

    /// Redirects stdio, records uncaught NSExceptions, harvests Crash Reporter files.
    public static func install(fileManager: FileManager = .default) {
        let dir = logsDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let console = dir.appendingPathComponent("console.log")
        try? prepareConsoleLog(at: console, fileManager: fileManager)
        redirectStdio(to: console)

        NSSetUncaughtExceptionHandler { exception in
            CrashLog.recordException(exception)
        }
        UserDefaults.standard.set(true, forKey: "NSApplicationCrashOnExceptions")

        let reports = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        try? harvest(from: reports, into: dir, fileManager: fileManager)
    }

    private static func redirectStdio(to url: URL) {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        dup2(fd, STDERR_FILENO)
        dup2(fd, STDOUT_FILENO)
        if fd != STDERR_FILENO, fd != STDOUT_FILENO {
            close(fd)
        }
        let stamp = "--- \(ISO8601DateFormatter().string(from: Date())) pid=\(getpid()) ---\n"
        FileHandle.standardError.write(Data(stamp.utf8))
    }

    private static func recordException(_ exception: NSException) {
        let body = """
        \(ISO8601DateFormatter().string(from: Date())) NSException \(exception.name.rawValue): \(exception.reason ?? "")
        \(exception.callStackSymbols.joined(separator: "\n"))

        """
        let url = logsDirectory().appendingPathComponent("last-crash.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(body.utf8))
    }
}
