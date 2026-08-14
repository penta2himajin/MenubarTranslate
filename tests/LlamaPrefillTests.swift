import Testing
import MTEngineLlama

@Suite("LlamaPrefill")
struct LlamaPrefillTests {

    @Test("chunks cover the suffix without overlap")
    func chunkRangesCover() {
        #expect(LlamaPrefill.chunkRanges(count: 0, batchSize: 512) == [])
        #expect(LlamaPrefill.chunkRanges(count: 3, batchSize: 512) == [0..<3])
        #expect(LlamaPrefill.chunkRanges(count: 512, batchSize: 512) == [0..<512])
        #expect(LlamaPrefill.chunkRanges(count: 513, batchSize: 512) == [0..<512, 512..<513])
        #expect(LlamaPrefill.chunkRanges(count: 1024, batchSize: 512) == [0..<512, 512..<1024])
    }
}
