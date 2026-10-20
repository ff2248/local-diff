import CoreGraphics

public func alignmentPadding(rows: [DiffRow], leftHeights: [CGFloat],
                             rightHeights: [CGFloat]) -> (left: [CGFloat], right: [CGFloat]) {
    var left = Array(repeating: CGFloat(0), count: leftHeights.count + 1)
    var right = Array(repeating: CGFloat(0), count: rightHeights.count + 1)
    var yLeft: CGFloat = 0
    var yRight: CGFloat = 0
    for row in rows {
        if let l = row.left, let r = row.right {
            if yLeft < yRight {
                left[l] = yRight - yLeft
                yLeft = yRight
            } else if yRight < yLeft {
                right[r] = yLeft - yRight
                yRight = yLeft
            }
        }
        if let l = row.left { yLeft += leftHeights[l] }
        if let r = row.right { yRight += rightHeights[r] }
    }
    if yLeft < yRight {
        left[leftHeights.count] = yRight - yLeft
    } else {
        right[rightHeights.count] = yLeft - yRight
    }
    return (left, right)
}
