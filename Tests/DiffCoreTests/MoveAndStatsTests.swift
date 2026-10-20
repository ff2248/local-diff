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

@Test func typicalPromptSizeIsFast() {
    let (l, r) = syntheticPromptPair()
    let elapsed = ContinuousClock().measure { _ = computeDiff(left: l, right: r, options: CompareOptions()) }
    #expect(elapsed < .milliseconds(500))
}

// 一行 1 萬字、右側約一半的字被換掉，兩行仍會配對成 modified
@Test func hugeSingleLineFallsBack() {
    var rng = SplitMix64(seed: 7)
    let pool = Array("的一是不了人我在有他這中大來上國個到說們為子和你地出道也時年得就那要下以生會自著去之過")
    func pick() -> Character { pool[Int(rng.next() % UInt64(pool.count))] }
    let l = String((0..<10_000).map { _ in pick() })
    let r = String(l.map { c in rng.next() % 2 == 0 ? pick() : c })
    var d: DiffResult?
    let elapsed = ContinuousClock().measure { d = computeDiff(left: l, right: r, options: CompareOptions()) }
    #expect(d?.rows.map(\.kind) == [.modified])
    #expect(elapsed < .milliseconds(300))
}

// 180 行、每行約 70 個中文字，右側每隔一行改 10 字、並把 10 行搬到別處
private func syntheticPromptPair() -> (String, String) {
    var rng = SplitMix64(seed: 42)
    let pool = Array("的一是不了人我在有他這中大來上國個到說們為子和你地出道也時年得就那要下以生會自著去之過家學對可她裡後小麼心多天而能好都然沒日於起還發成事只作當想看文無開手十用主行方又如前所本見經頭面公同三已老從動兩長知民樣現分將外但身些與高意進把法此實回二理美點月明其種聲全工己話兒者向情部正名定女問力機給等幾很業最間新什打便位因重被走電四第門相次東政海口使教西再平真聽世氣信北少關並內加化由卻代軍產入先山五太水萬市眼體別處總才場師書比住員九笑性通目華報立馬命張活難神數件安表原車白應路期叫死常提感金何更反合放做系計或司利受光王果親界及今京務制解各任至清物台象記邊共風戰干接它許八特覺望直服毛林題建南度統色字請交愛讓認算論百吃義科怎元社術結六功指思非流每青管夫連遠資隊跟帶花快條院變聯言權往展該領傳近留紅治決周保達辦運武半候七必城父強步完革深區即求品士轉量空甚眾技輕程告江語英基派滿式李息寫呢識極令黃德收臉錢黨倒未持取設始版雙歷越史商千片容研像找友孩站廣改議形委早房音火際則首單據導影失拿網香似斯專石若兵弟誰校讀志飛觀爭究包組造落視濟喜離雖壞")
    func line() -> String { String((0..<70).map { _ in pool[Int(rng.next() % UInt64(pool.count))] }) }
    let left = (0..<180).map { _ in line() }
    var right = left.enumerated().map { k, s -> String in
        guard k % 2 == 0 else { return s }
        var chars = Array(s)
        for p in stride(from: 5, to: 65, by: 6) { chars[p] = pool[Int(rng.next() % UInt64(pool.count))] }
        return String(chars)
    }
    let moved = (0..<10).map { right.remove(at: 10 + $0 * 7) }
    right.insert(contentsOf: moved, at: right.count / 2)
    return (left.joined(separator: "\n"), right.joined(separator: "\n"))
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
