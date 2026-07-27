import Testing
@testable import MenubarTranslateCore

@Suite("PromptBuilder")
struct PromptBuilderTests {
    /// Regression: the gemma turn header must terminate with a newline
    /// (`<start_of_turn>model\n`). Omitting it caused EN→JA artifacts on
    /// GGUF Q4_K_M (instruction-like prefixes, wrong-language output).
    @Test func gemmaPromptEndsModelTurnWithNewline() {
        let p = PromptBuilder.gemma(
            text: "hello",
            pair: LanguagePair(sourceCode: "en", sourceName: "English",
                               targetCode: "ja", targetName: "Japanese"))
        #expect(p.hasSuffix("<start_of_turn>model\n"))
    }

    // MARK: - Hy-MT2 dialects
    //
    // The family ships two mutually incompatible token sets: Hy-MT2-7B uses the
    // legacy <|startoftext|>…<|extra_0|> markers, Hy-MT2-1.8B uses the fullwidth
    // <｜hy_User｜>/<｜hy_Assistant｜> turn markers. Neither set exists in the
    // other's vocabulary, so rendering the wrong one feeds the model raw text
    // where turn markers should be — the same failure class as the gemma
    // newline bug above, only louder.

    @Test func dialectFollowsTheModelsOwnBosToken() {
        #expect(HunyuanDialect(bosToken: "<|startoftext|>") == .startOfText)
        #expect(HunyuanDialect(bosToken: "<｜hy_begin▁of▁sentence｜>") == .hyTurn)
        // Unknown/absent metadata keeps the 7B behaviour that shipped.
        #expect(HunyuanDialect(bosToken: nil) == .startOfText)
    }

    @Test func hyTurnDialectUsesTheFullwidthTurnMarkers() {
        let p = PromptBuilder.hunyuan(text: "こんにちは", pair: .jaToEn, dialect: .hyTurn)
        #expect(p.hasPrefix("<｜hy_begin▁of▁sentence｜><｜hy_User｜>"))
        #expect(p.hasSuffix("<｜hy_Assistant｜>"))
        #expect(p.contains("English"))
        #expect(p.contains("こんにちは"))
        // The 7B markers are absent from the 1.8B vocabulary — they must not leak in.
        #expect(!p.contains("<|startoftext|>"))
        #expect(!p.contains("<|extra_0|>"))
    }

    @Test func startOfTextDialectIsTheDefaultAndKeepsThe7BWireFormat() {
        let p = PromptBuilder.hunyuan(text: "こんにちは", pair: .jaToEn)
        #expect(p.hasPrefix("<|startoftext|>"))
        #expect(p.hasSuffix("<|extra_0|>"))
        #expect(!p.contains("<｜hy_User｜>"))
    }

    /// Both dialects carry the instruction verbatim from the Hy-MT2 model card;
    /// only the framing differs.
    @Test func bothDialectsShareTheInstructionBody() {
        let instruction = "Translate the following text into English. Note that you should "
            + "only output the translated result without any additional explanation:\n\n"
        for dialect in [HunyuanDialect.startOfText, .hyTurn] {
            let p = PromptBuilder.hunyuan(text: "こんにちは", pair: .jaToEn, dialect: dialect)
            #expect(p.contains(instruction), "dialect \(dialect) lost the model-card instruction")
        }
    }
}
