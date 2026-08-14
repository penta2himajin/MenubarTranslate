import Foundation

/// User-facing translation language. The shipping UI picks a **target** only;
/// the source is inferred from script (ja / zh / en are script-separable).
public enum AppLanguage: String, Sendable, CaseIterable, Hashable {
    case ja
    case en
    case zh

    public var code: String { rawValue }

    public var englishName: String {
        switch self {
        case .ja: return "Japanese"
        case .en: return "English"
        case .zh: return "Chinese"
        }
    }

    public var menuLabel: String {
        switch self {
        case .ja: return "日本語"
        case .en: return "English"
        case .zh: return "中文"
        }
    }

    /// Parse a BCP-47 tag from System Settings → Languages (`ja-JP`, `zh-Hans`, …).
    public init?(preferredTag: String) {
        let primary = preferredTag.split(separator: "-").first.map(String.init)?.lowercased()
        switch primary {
        case "ja": self = .ja
        case "en": self = .en
        case "zh": self = .zh
        default: return nil
        }
    }

    /// Script-first detection. Kana ⇒ Japanese even when Han is also present.
    public static func detect(_ text: String) -> AppLanguage? {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return nil }
        if scalars.contains(where: isKana) { return .ja }
        if scalars.contains(where: isHan) { return .zh }
        if scalars.contains(where: isLatin) { return .en }
        return nil
    }

    /// Always the ja/en/zh pool. Settings preferred languages only affect order.
    public static func pickerLanguages(
        preferred: [String] = Locale.preferredLanguages
    ) -> [AppLanguage] {
        var seen = Set<AppLanguage>()
        let fromSettings = preferred.compactMap(AppLanguage.init(preferredTag:))
            .filter { seen.insert($0).inserted }
        let rest = AppLanguage.allCases.filter { !seen.contains($0) }
        return fromSettings + rest
    }
}

extension LanguagePair {
    public static func named(source: AppLanguage, target: AppLanguage) -> LanguagePair {
        LanguagePair(
            sourceCode: source.code, sourceName: source.englishName,
            targetCode: target.code, targetName: target.englishName
        )
    }

    public static func isSupported(_ pair: LanguagePair) -> Bool {
        let codes: Set<String> = ["ja", "en", "zh"]
        return codes.contains(pair.sourceCode) && codes.contains(pair.targetCode)
    }
}

private func isKana(_ s: Unicode.Scalar) -> Bool {
    (0x3040...0x309F).contains(s.value) || (0x30A0...0x30FF).contains(s.value)
}

private func isHan(_ s: Unicode.Scalar) -> Bool {
    (0x4E00...0x9FFF).contains(s.value)
}

private func isLatin(_ s: Unicode.Scalar) -> Bool {
    s.properties.isAlphabetic && s.isASCII
}
