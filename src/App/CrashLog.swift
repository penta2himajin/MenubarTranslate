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

    public static func defaultDiagnosticReportDirectories(
        fileManager: FileManager = .default
    ) -> [URL] {
        let user = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        let system = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true)
        return [user, system]
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

    public static func harvestAll(
        from diagnosticDirs: [URL],
        into destDir: URL,
        fileManager: FileManager = .default
    ) throws {
        for dir in diagnosticDirs {
            try harvest(from: dir, into: destDir, fileManager: fileManager)
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

    public static func appendCrashText(
        _ text: String,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let dir = directory ?? logsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("last-crash.log")
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// Redirects stdio, records uncaught NSExceptions and fatal signals,
    /// harvests Crash Reporter files.
    public static func install(fileManager: FileManager = .default) {
        let dir = logsDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let console = dir.appendingPathComponent("console.log")
        try? prepareConsoleLog(at: console, fileManager: fileManager)
        redirectStdio(to: console)

        let crashNote = dir.appendingPathComponent("last-crash.log")
        openCrashNoteFD(at: crashNote)

        NSSetUncaughtExceptionHandler { exception in
            CrashLog.recordException(exception)
        }
        UserDefaults.standard.set(true, forKey: "NSApplicationCrashOnExceptions")
        installFatalSignalHandlers()

        try? harvestAll(
            from: defaultDiagnosticReportDirectories(fileManager: fileManager),
            into: dir,
            fileManager: fileManager
        )
    }

    private static func redirectStdio(to url: URL) {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        dup2(fd, STDERR_FILENO)
        dup2(fd, STDOUT_FILENO)
        if fd != STDERR_FILENO, fd != STDOUT_FILENO {
            close(fd)
        }
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
        let exe = CommandLine.arguments.first ?? ""
        let stamp =
            "--- \(ISO8601DateFormatter().string(from: Date())) pid=\(getpid()) exe=\(exe) ---\n"
        FileHandle.standardError.write(Data(stamp.utf8))
    }

    private static func recordException(_ exception: NSException) {
        let body = """
        \(ISO8601DateFormatter().string(from: Date())) NSException \(exception.name.rawValue): \(exception.reason ?? "")
        \(exception.callStackSymbols.joined(separator: "\n"))

        """
        try? appendCrashText(body)
    }

    // MARK: - Fatal signals (ggml abort, Swift fatalError)

    #if canImport(Darwin)
    private static func openCrashNoteFD(at url: URL) {
        mbtCrashNoteFD = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }

    private static func installFatalSignalHandlers() {
        signal(SIGABRT, mbtFatalSignal)
        signal(SIGSEGV, mbtFatalSignal)
        signal(SIGBUS, mbtFatalSignal)
        signal(SIGILL, mbtFatalSignal)
        signal(SIGTRAP, mbtFatalSignal)
    }
    #else
    private static func openCrashNoteFD(at url: URL) {}
    private static func installFatalSignalHandlers() {}
    #endif
}

#if canImport(Darwin)
/// Written only from `install`; read from the signal handler (async-signal-safe).
nonisolated(unsafe) private var mbtCrashNoteFD: Int32 = -1

private let mbtFatalSignalLine: StaticString =
    "fatal signal — see last-crash.log and console.log\n"

private let mbtFatalSignal: @convention(c) (Int32) -> Void = { sig in
    let ptr = UnsafeRawPointer(mbtFatalSignalLine.utf8Start)
    let n = mbtFatalSignalLine.utf8CodeUnitCount
    _ = write(STDERR_FILENO, ptr, n)
    if mbtCrashNoteFD >= 0 {
        _ = write(mbtCrashNoteFD, ptr, n)
        _ = fsync(mbtCrashNoteFD)
    }
    _exit(128 + sig)
}
#endif
