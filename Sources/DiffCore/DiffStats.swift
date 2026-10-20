public struct DiffStats: Equatable, Sendable {
    public let left: TextStats
    public let right: TextStats
    public let insertedCharacters: Int
    public let deletedCharacters: Int
    public let similarity: Double
}

func makeStats(_ l: Side, _ r: Side, deleted: Int, inserted: Int) -> DiffStats {
    let left = TextStats(text: l.text as String)
    let right = TextStats(text: r.text as String)
    let total = left.characters + right.characters
    let similarity = total == 0 ? 1.0 : Double(total - deleted - inserted) / Double(total)
    return DiffStats(left: left, right: right, insertedCharacters: inserted,
                     deletedCharacters: deleted, similarity: similarity)
}
