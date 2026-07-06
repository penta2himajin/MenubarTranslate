import Foundation

/// A minimal, reference-typed output sink so the CLI driver can write to real file handles
/// in production and to an in-memory buffer in tests.
///
/// `Sendable`: the sinks are passed from the main-actor-isolated executable entry point into
/// the nonisolated driver, so the type must cross isolation. The concrete sinks are used from
/// a single execution context in practice (the CLI is single-threaded), so they adopt
/// `@unchecked Sendable`. Public: this is the `mbt` executable's API surface.
public protocol TextSink: AnyObject, Sendable {
    func write(_ text: String)
}

/// Collects output in memory for assertions.
public final class StringSink: TextSink, @unchecked Sendable {
    public private(set) var buffer = ""
    public init() {}
    public func write(_ text: String) { buffer += text }
}

/// Writes to a `FileHandle` (e.g. standard output / standard error).
public final class FileHandleSink: TextSink, @unchecked Sendable {
    private let handle: FileHandle
    public init(_ handle: FileHandle) { self.handle = handle }
    public func write(_ text: String) {
        if let data = text.data(using: .utf8) { handle.write(data) }
    }
}
