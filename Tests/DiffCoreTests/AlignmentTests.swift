import Testing
import CoreGraphics
@testable import DiffCore

@Test func fillerForDeletedLine() {
    let rows = [DiffRow(left: 0, right: 0, kind: .unchanged), DiffRow(left: 1, right: nil, kind: .deleted),
                DiffRow(left: 2, right: 1, kind: .unchanged)]
    let p = alignmentPadding(rows: rows, leftHeights: [20, 40, 20], rightHeights: [20, 20])
    #expect(p.left == [0, 0, 0, 0] && p.right == [0, 40, 0])
}

@Test func differentWrapHeights() {
    let rows = [DiffRow(left: 0, right: 0, kind: .modified), DiffRow(left: 1, right: 1, kind: .unchanged)]
    let p = alignmentPadding(rows: rows, leftHeights: [60, 20], rightHeights: [20, 20])
    #expect(p.left == [0, 0, 0] && p.right == [0, 40, 0])
}

@Test func trailingPadding() {
    let rows = [DiffRow(left: 0, right: 0, kind: .unchanged), DiffRow(left: nil, right: 1, kind: .inserted)]
    let p = alignmentPadding(rows: rows, leftHeights: [20], rightHeights: [20, 30])
    #expect(p.left == [0, 30] && p.right == [0, 0, 0])
}

@Test func deletedAndInsertedSitSideBySide() {
    let rows = [DiffRow(left: 0, right: nil, kind: .deleted), DiffRow(left: nil, right: 0, kind: .inserted),
                DiffRow(left: 1, right: 1, kind: .unchanged)]
    let p = alignmentPadding(rows: rows, leftHeights: [20, 20], rightHeights: [30, 20])
    #expect(p.left == [0, 10, 0] && p.right == [0, 0, 0])
}
