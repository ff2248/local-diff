let moveMinLength = 12
let moveThreshold = 0.7

func detectMoves(_ rows: [DiffRow], _ l: Side, _ r: Side) -> (rows: [DiffRow], moves: [MovePair]) {
    let dels = rows.indices.filter { rows[$0].kind == .deleted && l.keys[rows[$0].left!].count >= moveMinLength }
    let ins = rows.indices.filter { rows[$0].kind == .inserted && r.keys[rows[$0].right!].count >= moveMinLength }
    var candidates: [(del: Int, ins: Int, score: Double)] = []
    for d in dels {
        for i in ins {
            let score = l.profiles[rows[d].left!].dice(r.profiles[rows[i].right!])
            if score >= moveThreshold { candidates.append((d, i, score)) }
        }
    }
    candidates.sort { $0.score > $1.score }

    var result = rows
    var usedDel = Set<Int>()
    var usedIns = Set<Int>()
    var moves: [MovePair] = []
    for c in candidates where !usedDel.contains(c.del) && !usedIns.contains(c.ins) {
        usedDel.insert(c.del)
        usedIns.insert(c.ins)
        result[c.del] = DiffRow(left: rows[c.del].left, right: nil, kind: .moved)
        result[c.ins] = DiffRow(left: nil, right: rows[c.ins].right, kind: .moved)
        moves.append(MovePair(left: rows[c.del].left!, right: rows[c.ins].right!))
    }
    moves.sort { $0.left < $1.left }
    return (result, moves)
}

struct BigramProfile {
    let bigrams: [Int]
    let length: Int

    init(_ key: String) {
        let chars = Array(key)
        length = chars.count
        bigrams = chars.count < 2 ? [] : (0..<(chars.count - 1)).map { k in
            var h = Hasher()
            h.combine(chars[k])
            h.combine(chars[k + 1])
            return h.finalize()
        }.sorted()
        single = chars.count == 1 ? chars[0] : nil
    }

    private let single: Character?

    func dice(_ other: BigramProfile) -> Double {
        if length < 2 || other.length < 2 {
            return length == other.length && single == other.single ? 1 : 0
        }
        var common = 0
        var a = 0
        var b = 0
        while a < bigrams.count, b < other.bigrams.count {
            if bigrams[a] == other.bigrams[b] {
                common += 1
                a += 1
                b += 1
            } else if bigrams[a] < other.bigrams[b] {
                a += 1
            } else {
                b += 1
            }
        }
        return Double(2 * common) / Double(bigrams.count + other.bigrams.count)
    }
}
