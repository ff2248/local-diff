import Foundation

public enum RowKind: Equatable, Sendable { case unchanged, modified, deleted, inserted, moved }

public struct DiffRow: Equatable, Sendable {
    public let left: Int?
    public let right: Int?
    public let kind: RowKind
}

public enum HighlightKind: Equatable, Sendable {
    case lineModified, lineDeleted, lineInserted, lineMoved, textDeleted, textInserted
}

public struct Highlight: Equatable, Sendable {
    public let range: NSRange
    public let kind: HighlightKind
}

public struct MovePair: Equatable, Sendable {
    public let left: Int
    public let right: Int
}

public struct DiffResult: Sendable {
    public let rows: [DiffRow]
    public let leftLines: [NSRange]
    public let rightLines: [NSRange]
    public let leftHighlights: [Highlight]
    public let rightHighlights: [Highlight]
    public let moves: [MovePair]
    public let stats: DiffStats
}

let pairingThreshold = 0.3
let inlineMergeGap = 1
let inlineTokenLimit = 4_000_000
let pairingLimit = 200_000
let pairingWindow = 50

/// 所在的 Task 被取消時會提早結束，這時回傳的結果不完整，呼叫端應該丟棄。
public func computeDiff(left: String, right: String, options: CompareOptions) -> DiffResult {
    let l = Side(text: left, options: options)
    let r = Side(text: right, options: options)
    let (rows, moves) = detectMoves(alignRows(l, r, options), l, r)

    var lh: [Highlight] = []
    var rh: [Highlight] = []
    var deletedCount = 0
    var insertedCount = 0
    for row in rows {
        if Task.isCancelled { break }
        switch row.kind {
        case .unchanged:
            break
        case .deleted:
            lh.append(Highlight(range: l.lines[row.left!], kind: .lineDeleted))
            deletedCount += l.line(row.left!).count
        case .inserted:
            rh.append(Highlight(range: r.lines[row.right!], kind: .lineInserted))
            insertedCount += r.line(row.right!).count
        case .modified:
            lh.append(Highlight(range: l.lines[row.left!], kind: .lineModified))
            rh.append(Highlight(range: r.lines[row.right!], kind: .lineModified))
            let inline = inlineDiff(l, row.left!, r, row.right!, options)
            lh += inline.deleted.map { Highlight(range: $0, kind: .textDeleted) }
            rh += inline.inserted.map { Highlight(range: $0, kind: .textInserted) }
            deletedCount += inline.deletedCount
            insertedCount += inline.insertedCount
        case .moved:
            break
        }
    }
    for move in moves where !Task.isCancelled {
        lh.append(Highlight(range: l.lines[move.left], kind: .lineMoved))
        rh.append(Highlight(range: r.lines[move.right], kind: .lineMoved))
        let inline = inlineDiff(l, move.left, r, move.right, options)
        lh += inline.deleted.map { Highlight(range: $0, kind: .textDeleted) }
        rh += inline.inserted.map { Highlight(range: $0, kind: .textInserted) }
        deletedCount += inline.deletedCount
        insertedCount += inline.insertedCount
    }
    return DiffResult(rows: rows, leftLines: l.lines, rightLines: r.lines,
                      leftHighlights: lh, rightHighlights: rh, moves: moves,
                      stats: makeStats(l, r, deleted: deletedCount, inserted: insertedCount))
}

struct Side {
    let text: NSString
    let lines: [NSRange]
    let keys: [String]
    let profiles: [BigramProfile]

    init(text: String, options: CompareOptions) {
        var lines: [NSRange] = []
        var start = 0
        var offset = 0
        for ch in text {
            if ch.isNewline {
                lines.append(NSRange(location: start, length: offset - start))
                start = offset + ch.utf16.count
            }
            offset += ch.utf16.count
        }
        if start < offset { lines.append(NSRange(location: start, length: offset - start)) }
        let ns = text as NSString
        self.text = ns
        self.lines = lines
        self.keys = lines.map { normalizedKey(ns.substring(with: $0), options) }
        self.profiles = keys.map(BigramProfile.init)
    }

    func line(_ i: Int) -> String { text.substring(with: lines[i]) }
}

private func alignRows(_ l: Side, _ r: Side, _ options: CompareOptions) -> [DiffRow] {
    func participates(_ key: String) -> Bool {
        !options.ignoreBlankLines || !key.allSatisfy(\.isWhitespace)
    }
    let lIdx = l.keys.indices.filter { participates(l.keys[$0]) }
    let rIdx = r.keys.indices.filter { participates(r.keys[$0]) }
    let diff = rIdx.map { r.keys[$0] }.difference(from: lIdx.map { l.keys[$0] })
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in diff {
        switch change {
        case .remove(let offset, _, _): removed.insert(offset)
        case .insert(let offset, _, _): inserted.insert(offset)
        }
    }

    var rows: [DiffRow] = []
    var nextLeft = 0
    var nextRight = 0
    func flushBlanks(left upTo: Int?, right upToR: Int?) {
        while nextLeft < (upTo ?? l.lines.count), !participates(l.keys[nextLeft]) {
            rows.append(DiffRow(left: nextLeft, right: nil, kind: .unchanged))
            nextLeft += 1
        }
        while nextRight < (upToR ?? r.lines.count), !participates(r.keys[nextRight]) {
            rows.append(DiffRow(left: nil, right: nextRight, kind: .unchanged))
            nextRight += 1
        }
    }
    func emit(_ row: DiffRow) {
        flushBlanks(left: row.left, right: row.right)
        rows.append(row)
        if let li = row.left { nextLeft = li + 1 }
        if let ri = row.right { nextRight = ri + 1 }
    }

    var i = 0
    var j = 0
    while i < lIdx.count || j < rIdx.count {
        var dels: [Int] = []
        var ins: [Int] = []
        while i < lIdx.count, removed.contains(i) { dels.append(lIdx[i]); i += 1 }
        while j < rIdx.count, inserted.contains(j) { ins.append(rIdx[j]); j += 1 }
        if dels.isEmpty && ins.isEmpty {
            emit(DiffRow(left: lIdx[i], right: rIdx[j], kind: .unchanged))
            i += 1
            j += 1
        } else {
            pairHunk(dels, ins, l, r).forEach(emit)
        }
    }
    flushBlanks(left: nil, right: nil)
    return rows
}

private func pairHunk(_ dels: [Int], _ ins: [Int], _ l: Side, _ r: Side) -> [DiffRow] {
    var rows: [DiffRow] = []
    var from = 0
    for d in dels {
        if Task.isCancelled { break }
        var best: (index: Int, score: Double)?
        for k in from..<min(ins.count, from + pairingWindow) {
            let score = l.profiles[d].dice(r.profiles[ins[k]])
            if score >= pairingThreshold, score > (best?.score ?? -1) { best = (k, score) }
        }
        if let best {
            for k in from..<best.index { rows.append(DiffRow(left: nil, right: ins[k], kind: .inserted)) }
            rows.append(DiffRow(left: d, right: ins[best.index], kind: .modified))
            from = best.index + 1
        } else {
            rows.append(DiffRow(left: d, right: nil, kind: .deleted))
        }
    }
    for k in from..<ins.count { rows.append(DiffRow(left: nil, right: ins[k], kind: .inserted)) }
    return rows
}

struct InlineDiff {
    let deleted: [NSRange]
    let inserted: [NSRange]
    let deletedCount: Int
    let insertedCount: Int
}

func inlineDiff(_ l: Side, _ li: Int, _ r: Side, _ ri: Int, _ options: CompareOptions) -> InlineDiff {
    let lt = tokenize(l.line(li), options)
    let rt = tokenize(r.line(ri), options)
    if lt.count * rt.count > inlineTokenLimit {
        return InlineDiff(deleted: [l.lines[li]], inserted: [r.lines[ri]],
                          deletedCount: l.line(li).count, insertedCount: r.line(ri).count)
    }
    let diff = rt.map(\.key).difference(from: lt.map(\.key))
    var lChanged = Array(repeating: false, count: lt.count)
    var rChanged = Array(repeating: false, count: rt.count)
    for change in diff {
        switch change {
        case .remove(let offset, _, _): lChanged[offset] = true
        case .insert(let offset, _, _): rChanged[offset] = true
        }
    }
    let deletedCount = characterCount(lt, lChanged, in: l.line(li))
    let insertedCount = characterCount(rt, rChanged, in: r.line(ri))
    absorbSmallGaps(&lChanged, &rChanged)
    return InlineDiff(deleted: ranges(lt, lChanged, base: l.lines[li].location),
                      inserted: ranges(rt, rChanged, base: r.lines[ri].location),
                      deletedCount: deletedCount, insertedCount: insertedCount)
}

private func characterCount(_ tokens: [Token], _ changed: [Bool], in line: String) -> Int {
    let ns = line as NSString
    return tokens.indices.filter { changed[$0] }.reduce(0) { $0 + ns.substring(with: tokens[$1].range).count }
}

private func absorbSmallGaps(_ lChanged: inout [Bool], _ rChanged: inout [Bool]) {
    enum Op { case change, equal(Int, Int) }
    var ops: [Op] = []
    var i = 0
    var j = 0
    while i < lChanged.count || j < rChanged.count {
        if i < lChanged.count, lChanged[i] {
            ops.append(.change)
            i += 1
        } else if j < rChanged.count, rChanged[j] {
            ops.append(.change)
            j += 1
        } else {
            ops.append(.equal(i, j))
            i += 1
            j += 1
        }
    }
    var k = 0
    while k < ops.count {
        guard case .equal = ops[k] else { k += 1; continue }
        let runStart = k
        while k < ops.count, case .equal = ops[k] { k += 1 }
        guard runStart > 0, k < ops.count, k - runStart <= inlineMergeGap else { continue }
        for case .equal(let a, let b) in ops[runStart..<k] {
            lChanged[a] = true
            rChanged[b] = true
        }
    }
}

private func ranges(_ tokens: [Token], _ changed: [Bool], base: Int) -> [NSRange] {
    var result: [NSRange] = []
    var k = 0
    while k < tokens.count {
        guard changed[k] else { k += 1; continue }
        let start = tokens[k].range.location
        while k + 1 < tokens.count, changed[k + 1] { k += 1 }
        result.append(NSRange(location: base + start, length: NSMaxRange(tokens[k].range) - start))
        k += 1
    }
    return result
}
