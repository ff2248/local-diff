import Testing
@testable import DiffCore

private func rows(_ kinds: String) -> [DiffRow] {
    var l = 0
    var r = 0
    return kinds.map { c in
        switch c {
        case "=": defer { l += 1; r += 1 }; return DiffRow(left: l, right: r, kind: .unchanged)
        case "<": defer { l += 1 }; return DiffRow(left: l, right: nil, kind: .unchanged)
        case "-": defer { l += 1 }; return DiffRow(left: l, right: nil, kind: .deleted)
        default: defer { r += 1 }; return DiffRow(left: nil, right: r, kind: .inserted)
        }
    }
}

@Test func keepsContextAroundChange() {
    // 10 行不變、1 行刪除、10 行不變
    let regions = collapsibleRegions(rows: rows("==========-=========="), context: 3)
    #expect(regions == [0..<7, 14..<21])
}

@Test func shortGapsStayVisible() {
    // 兩處變動之間只有 7 行，扣掉前後脈絡只剩 1 行，不摺疊
    #expect(collapsibleRegions(rows: rows("-=======-"), context: 3).isEmpty)
    // 剩 2 行就摺疊
    #expect(collapsibleRegions(rows: rows("-========-"), context: 3) == [4..<6])
}

@Test func identicalTextCollapsesEverything() {
    #expect(collapsibleRegions(rows: rows("=====")) == [0..<5])
}

@Test func regionsStartAndEndOnPairedRows() {
    // 摺疊範圍邊緣的單邊列（忽略空行時的空行）要讓出來
    #expect(collapsibleRegions(rows: rows("<<====<-"), context: 0) == [2..<6])
}

@Test func emptyAndAllChanged() {
    #expect(collapsibleRegions(rows: []).isEmpty)
    #expect(collapsibleRegions(rows: rows("-+-+")).isEmpty)
}
