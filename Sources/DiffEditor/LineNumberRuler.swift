import AppKit

final class LineNumberRuler: NSRulerView {
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    init(textView: DiffTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    required init(coder: NSCoder) { fatalError() }

    func updateThickness(lineCount: Int) {
        let digits = String(max(lineCount, 1)).count
        let thickness = max(36, CGFloat(digits) * 7 + 16)
        if ruleThickness != thickness { ruleThickness = thickness }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? DiffTextView else { return }
        for (number, y) in textView.lineNumberPositions(in: textView.visibleRect) {
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            let point = convert(NSPoint(x: 0, y: y), from: textView)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: point.y + 2), withAttributes: attributes)
        }
    }
}
