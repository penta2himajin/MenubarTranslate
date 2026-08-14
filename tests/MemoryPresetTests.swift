import Testing
@testable import MenubarTranslateCore

@Suite("MemoryPreset")
struct MemoryPresetTests {

    @Test("under 16 GB is conservative, 16 GB and above is permissive")
    func selectsFromPhysicalMemory() {
        let sixteen: UInt64 = 16 * 1024 * 1024 * 1024
        #expect(MemoryPreset.forPhysicalMemory(8 * 1024 * 1024 * 1024) == .conservative8GB)
        #expect(MemoryPreset.forPhysicalMemory(sixteen - 1) == .conservative8GB)
        #expect(MemoryPreset.forPhysicalMemory(sixteen) == .permissive16GB)
        #expect(MemoryPreset.forPhysicalMemory(32 * 1024 * 1024 * 1024) == .permissive16GB)
    }
}
