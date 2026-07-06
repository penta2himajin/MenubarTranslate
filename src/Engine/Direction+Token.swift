/// CLI/token affordances for the generated `Direction` enum (primary JA↔EN, ADR 0001).
/// Auto-detect is deferred.
extension Direction {
    /// The CLI token for this direction.
    var token: String {
        switch self {
        case .jaToEn: return "ja-en"
        case .enToJa: return "en-ja"
        }
    }

    /// Parse a CLI/string token into a direction. Throws `DirectionParseError` on garbage.
    static func parse(_ raw: String) throws -> Direction {
        guard let direction = Direction.allCases.first(where: { $0.token == raw }) else {
            throw DirectionParseError(raw: raw)
        }
        return direction
    }
}

/// Thrown when a direction token is not one of the supported pairs.
struct DirectionParseError: Error, Equatable, CustomStringConvertible {
    let raw: String

    var description: String {
        "unknown direction '\(raw)'; expected one of: "
            + Direction.allCases.map(\.token).joined(separator: ", ")
    }
}
