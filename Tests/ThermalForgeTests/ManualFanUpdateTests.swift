import Testing
@testable import ThermalForgeCore

@Suite("Manual fan writes avoid repeated unlocks")
struct ManualFanUpdateTests {
    enum Failure: Error { case unlock, write }
    @Test("An already manual multi-fan M1 update writes targets without unlocking")
    func ready() throws {
        var operations: [String] = []
        try ManualFanUpdate.apply(indices: [0, 1], requiresForceTest: true,
            readMode: { _ in 1 }, readForceTest: { 1 },
            unlock: { operations.append("unlock") }, write: { operations.append("write\($0)") })
        #expect(operations == ["write0", "write1"])
    }
    @Test("Partial manual state, failed reads and cleared Ftst all require unlock")
    func recover() throws {
        for modes: [UInt8?] in [[0,0],[1,0],[1,nil],[1,1]] {
            var operations: [String] = []
            try ManualFanUpdate.apply(indices: [0,1], requiresForceTest: true,
                readMode: { modes[$0] }, readForceTest: { nil },
                unlock: { operations.append("unlock") }, write: { operations.append("write\($0)") })
            #expect(operations == ["unlock", "write0", "write1"])
        }
    }
    @Test("Platforms without Ftst skip that read but still check every fan")
    func noForceTest() throws {
        var forceReads = 0
        var unlocks = 0
        try ManualFanUpdate.apply(indices: [0,1], requiresForceTest: false,
            readMode: { _ in 1 }, readForceTest: { forceReads += 1; return nil },
            unlock: { unlocks += 1 }, write: { _ in })
        #expect(forceReads == 0 && unlocks == 0)
    }
    @Test("A successful first unlock is followed by direct updates, then re-unlock after reset")
    func transitions() throws {
        var manual: UInt8 = 0
        var unlocks = 0
        var writes = 0
        func update() throws {
            try ManualFanUpdate.apply(indices: [0], requiresForceTest: false,
                readMode: { _ in manual }, readForceTest: { nil },
                unlock: { unlocks += 1; manual = 1 }, write: { _ in writes += 1 })
        }
        try update(); try update(); try update()
        #expect(unlocks == 1 && writes == 3)
        manual = 0 // System reset / Default / wake.
        try update()
        #expect(unlocks == 2 && writes == 4)
    }
    @Test("Unlock failure prevents targets; a target failure propagates without unlimited retries")
    func failures() {
        var writes = 0
        #expect(throws: Failure.self) {
            try ManualFanUpdate.apply(indices: [0], requiresForceTest: false,
                readMode: { _ in 0 }, readForceTest: { nil },
                unlock: { throw Failure.unlock }, write: { _ in writes += 1 })
        }
        #expect(writes == 0)
        #expect(throws: Failure.self) {
            try ManualFanUpdate.apply(indices: [0,1], requiresForceTest: false,
                readMode: { _ in 1 }, readForceTest: { nil }, unlock: {},
                write: { _ in writes += 1; throw Failure.write })
        }
        #expect(writes == 1)
    }
}
