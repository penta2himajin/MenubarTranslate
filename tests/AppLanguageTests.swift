import Testing
@testable import MenubarTranslateCore

@Suite("AppLanguage")
struct AppLanguageTests {

    @Test("detects Japanese from kana, Chinese from Han, English from Latin")
    func detectsScript() {
        #expect(AppLanguage.detect("こんにちは") == .ja)
        #expect(AppLanguage.detect("漢字だけ") == .ja)
        #expect(AppLanguage.detect("这是中文") == .zh)
        #expect(AppLanguage.detect("Hello, world.") == .en)
        #expect(AppLanguage.detect("") == nil)
        #expect(AppLanguage.detect("   ") == nil)
    }

    @Test("kana wins over Han when both are present")
    func kanaWinsOverHan() {
        #expect(AppLanguage.detect("日本語の文章") == .ja)
    }

    @Test("pickerLanguages always includes ja/en/zh, Settings order first")
    func pickerAlwaysHasPool() {
        #expect(AppLanguage.pickerLanguages(preferred: ["fr-FR", "de-DE"]) == [.ja, .en, .zh])
        #expect(
            AppLanguage.pickerLanguages(preferred: ["en-US", "ja-JP", "zh-Hans-CN", "fr-FR"])
                == [.en, .ja, .zh]
        )
        #expect(AppLanguage.pickerLanguages(preferred: ["zh-Hant-TW", "en"]) == [.zh, .en, .ja])
    }

    @Test("LanguagePair.named maps ja/en/zh codes")
    func namedPair() {
        let p = LanguagePair.named(source: .zh, target: .en)
        #expect(p.sourceCode == "zh")
        #expect(p.targetCode == "en")
        #expect(p.token == "zh-en")
        #expect(p.sourceName == "Chinese")
        #expect(p.targetName == "English")
    }
}
