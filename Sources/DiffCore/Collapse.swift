/// 「只顯示差異」可以摺疊的列範圍（rows 的索引）。變動前後各留 context 列，
/// 可隱藏的列少於 minimumHidden 就不摺疊，範圍頭尾一定是左右都有的列。
public func collapsibleRegions(rows: [DiffRow], context: Int = 3, minimumHidden: Int = 2) -> [Range<Int>] {
    var regions: [Range<Int>] = []
    var k = 0
    while k < rows.count {
        guard rows[k].kind == .unchanged else { k += 1; continue }
        let runStart = k
        while k < rows.count, rows[k].kind == .unchanged { k += 1 }
        var start = runStart == 0 ? runStart : runStart + context
        var end = k == rows.count ? k : k - context
        while start < end, rows[start].left == nil || rows[start].right == nil { start += 1 }
        while start < end, rows[end - 1].left == nil || rows[end - 1].right == nil { end -= 1 }
        if end - start >= minimumHidden { regions.append(start..<end) }
    }
    return regions
}
