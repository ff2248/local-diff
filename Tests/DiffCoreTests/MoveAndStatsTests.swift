import Foundation
import Testing
@testable import DiffCore

private let longPara = "這是一段會被搬到最後面的長段落"

@Test func detectsMovedParagraph() {
    let d = computeDiff(left: "\(longPara)\n第二行內容\n第三行內容",
                        right: "第二行內容\n第三行內容\n\(longPara)", options: CompareOptions())
    #expect(d.moves == [MovePair(left: 0, right: 2)])
    #expect(d.rows.contains(DiffRow(left: 0, right: nil, kind: .moved)))
    #expect(d.rows.contains(DiffRow(left: nil, right: 2, kind: .moved)))
    #expect(!d.leftHighlights.contains { $0.kind == .lineDeleted })
    #expect(d.stats.insertedCharacters == 0 && d.stats.deletedCharacters == 0)
}

@Test func shortLinesAreNotMoved() {
    let d = computeDiff(left: "```\na\nb", right: "a\nb\n```", options: CompareOptions())
    #expect(d.moves.isEmpty)
}

@Test func charCounts() {
    let ins = computeDiff(left: "今天天氣很好", right: "今天天氣很好呀", options: CompareOptions()).stats
    #expect(ins.insertedCharacters == 1 && ins.deletedCharacters == 0)
    #expect(abs(ins.similarity - 12.0 / 13.0) < 1e-9)
    let mod = computeDiff(left: "今天天氣很好", right: "今天天氣不好", options: CompareOptions()).stats
    #expect(mod.insertedCharacters == 1 && mod.deletedCharacters == 1)
    #expect(abs(mod.similarity - 10.0 / 12.0) < 1e-9)
}

@Test func similarityEdgeCases() {
    #expect(computeDiff(left: "", right: "", options: CompareOptions()).stats.similarity == 1.0)
    let one = computeDiff(left: "", right: "abc", options: CompareOptions()).stats
    #expect(one.similarity == 0.0 && one.insertedCharacters == 3)
}

// 一行 1 萬字、右側約一半的字被換掉，兩行仍會配對成 modified
@Test func hugeSingleLineFallsBack() {
    var rng = SplitMix64(seed: 7)
    let pool = Array("的一是不了人我在有他這中大來上國個到說們為子和你地出道也時年得就那要下以生會自著去之過")
    func pick() -> Character { pool[Int(rng.next() % UInt64(pool.count))] }
    let l = String((0..<10_000).map { _ in pick() })
    let r = String(l.map { c in rng.next() % 2 == 0 ? pick() : c })
    let work = DiffWork()
    let d = computeDiff(left: l, right: r, options: CompareOptions(), work: work)
    #expect(d.rows.map(\.kind) == [.modified])
    #expect(work.inlineFallbacks == 1 && work.inlineDiffs == 0)
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Test func statsCountRawChangesNotMergedHighlights() {
    let stats = computeDiff(left: "甲乙丙丁戊己庚辛", right: "甲子丙寅戊己庚辛", options: CompareOptions()).stats
    #expect(stats.deletedCharacters == 2 && stats.insertedCharacters == 2)
}

@Test func indentedShortLinesAreNotMoved() {
    let d = computeDiff(left: "func a() {\n    if x {\n            }\n}\nlet q = 1",
                        right: "func a() {\n    if x {\n}\nlet q = 1\n                }", options: CompareOptions())
    #expect(d.moves.isEmpty)
}

// 兩份各 4000 行、共用一組關鍵字但互不相關的程式碼
@Test func largeUnrelatedInputsBoundTheirWork() {
    var rng = SplitMix64(seed: 3)
    let words = ["func", "let", "var", "return", "if", "else", "self", "value", "items", "count",
                 "index", "result", "map", "filter", "guard", "for", "in", "where"]
    func codeLine() -> String {
        String(repeating: " ", count: Int(rng.next() % 12))
            + (0..<8).map { _ in words[Int(rng.next() % UInt64(words.count))] }.joined(separator: " ")
    }
    let l = (0..<4000).map { _ in codeLine() }.joined(separator: "\n")
    let r = (0..<4000).map { _ in codeLine() }.joined(separator: "\n")
    let work = DiffWork()
    _ = computeDiff(left: l, right: r, options: CompareOptions(), work: work)
    #expect(work.similarityChecks <= 4000 * pairingWindow)
    #expect(work.moveDetectionSkipped)
}

// 20 行、每行 1500 字且都有修改，沒有取消時要做 20 次行內 diff
@Test func cancelledDiffStopsEarly() async {
    var rng = SplitMix64(seed: 11)
    let pool = Array("的一是不了人我在有他這中大來上國個到說們為子和你地出道也時年得就那要下以生會自著去之過")
    func pick() -> Character { pool[Int(rng.next() % UInt64(pool.count))] }
    let leftLines = (0..<20).map { _ in String((0..<1500).map { _ in pick() }) }
    let rightLines = leftLines.map { String($0.map { c in rng.next() % 3 == 0 ? pick() : c }) }
    let l = leftLines.joined(separator: "\n")
    let r = rightLines.joined(separator: "\n")
    func inlineDiffs(cancelled: Bool) async -> Int {
        await Task {
            if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
            let work = DiffWork()
            _ = computeDiff(left: l, right: r, options: CompareOptions(), work: work)
            return work.inlineDiffs
        }.value
    }
    #expect(await inlineDiffs(cancelled: false) == 20)
    #expect(await inlineDiffs(cancelled: true) == 0)
}
