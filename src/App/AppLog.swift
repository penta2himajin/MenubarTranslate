import Foundation

/// Structured application logger for behaviour analysis.
///
/// Lines go to stderr by default. `CrashLog.install()` already redirects stdio
/// to `~/Library/Logs/MenubarTranslate/console.log`, so these lines land in the
/// same file as llama.cpp noise and status stamps.
///
/// Minimum level: `MBT_LOG_LEVEL` (`debug`/`info`/`warn`/`error`), default `debug`.
public enum AppLog {
    public enum Level: Int, Comparable, Sendable {
        case debug = 0
        case info = 1
        case warn = 2
        case error = 3

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .debug: return "debug"
            case .info: return "info"
            case .warn: return "warn"
            case .error: return "error"
            }
        }

        public static func parse(_ raw: String?) -> Level {
            switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "error": return .error
            case "warn", "warning": return .warn
            case "info": return .info
            case "debug": return .debug
            default: return .debug
            }
        }
    }

    public enum Category: String, Sendable {
        case app
        case translate
        case history
        case residency
        case http
        case model
        case ui
    }

    public static let minimumLevel: Level = Level.parse(
        ProcessInfo.processInfo.environment["MBT_LOG_LEVEL"]
    )

    /// Override sink in tests. Production writes UTF-8 lines to stderr.
    nonisolated(unsafe) public static var sink: @Sendable (String) -> Void = {
        FileHandle.standardError.write(Data($0.utf8))
    }

    private static let lock = NSLock()

    public static func debug(
        _ category: Category, _ message: String, _ fields: [String: String] = [:]
    ) {
        log(level: .debug, category: category, message: message, fields: fields)
    }

    public static func info(
        _ category: Category, _ message: String, _ fields: [String: String] = [:]
    ) {
        log(level: .info, category: category, message: message, fields: fields)
    }

    public static func warn(
        _ category: Category, _ message: String, _ fields: [String: String] = [:]
    ) {
        log(level: .warn, category: category, message: message, fields: fields)
    }

    public static func error(
        _ category: Category, _ message: String, _ fields: [String: String] = [:]
    ) {
        log(level: .error, category: category, message: message, fields: fields)
    }

    public static func log(
        level: Level,
        category: Category,
        message: String,
        fields: [String: String] = [:]
    ) {
        guard level >= minimumLevel else { return }
        let line = format(
            level: level,
            category: category,
            message: message,
            fields: fields,
            date: Date()
        )
        lock.lock()
        defer { lock.unlock() }
        sink(line)
    }

    public static func format(
        level: Level,
        category: Category,
        message: String,
        fields: [String: String],
        date: Date,
        dateFormatter: ISO8601DateFormatter = makeISO8601()
    ) -> String {
        var parts = [
            dateFormatter.string(from: date),
            "level=\(level.label)",
            "cat=\(category.rawValue)",
            "msg=\(sanitize(message))",
        ]
        for key in fields.keys.sorted() {
            parts.append("\(sanitize(key))=\(sanitize(fields[key] ?? ""))")
        }
        return parts.joined(separator: " ") + "\n"
    }

    public static func makeISO8601() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    /// Spaces and newlines become underscores / escapes so each log stays one line.
    public static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: " ", with: "_")
    }
}
