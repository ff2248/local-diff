import AppKit

/// 配色取自 GitHub Primer 的 diff 色票（淺色、深色各一組，跟隨系統外觀切換）。
@MainActor
enum Theme {
    static let background = color(light: 0xffffffff, dark: 0x0d1117ff)
    static let text = color(light: 0x1f2328ff, dark: 0xf0f6fcff)
    static let lineNumber = color(light: 0x59636eff, dark: 0x9198a1ff)
    static let filler = color(light: 0xf6f8faff, dark: 0x151b23ff)

    static let deletedLine = color(light: 0xffebe9ff, dark: 0xf851491a)
    static let deletedWord = color(light: 0xffcecbff, dark: 0xf8514966)
    static let deletedNumber = color(light: 0xffcecbff, dark: 0xf851494d)
    static let insertedLine = color(light: 0xdafbe1ff, dark: 0x2ea04326)
    static let insertedWord = color(light: 0xaceebbff, dark: 0x2ea04366)
    static let insertedNumber = color(light: 0xaceebbff, dark: 0x3fb9504d)
    static let movedLine = color(light: 0xfbefffff, dark: 0xab7df826)
    static let movedNumber = color(light: 0x8250df26, dark: 0xab7df84d)
    static let hunkLine = color(light: 0xddf4ffff, dark: 0x388bfd1a)
    static let hunkNumber = color(light: 0xb6e3ffff, dark: 0x0c2d6bff)

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            rgba(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }

    private static func rgba(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(value >> 24 & 0xff) / 255, green: CGFloat(value >> 16 & 0xff) / 255,
                blue: CGFloat(value >> 8 & 0xff) / 255, alpha: CGFloat(value & 0xff) / 255)
    }
}

/// 編輯區的字級與換行方式。行高跟著字級等比縮放，標示與行號也以此為準。
public struct EditorStyle: Equatable, Sendable {
    public static let `default` = EditorStyle(fontSize: 13)
    public static let fontSizes: ClosedRange<CGFloat> = 10...24

    public var fontSize: CGFloat
    public var wrapsLines: Bool

    /// 字級會取整數並限制在 `fontSizes` 範圍內，偏好設定檔裡的不合法值不會讓排版出錯。
    public init(fontSize: CGFloat, wrapsLines: Bool = true) {
        self.fontSize = min(max(fontSize.rounded(), Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        self.wrapsLines = wrapsLines
    }

    var lineHeight: CGFloat { (fontSize * 20 / 13).rounded() }

    @MainActor var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    /// 固定行高，讓中英文與 emoji 行一樣高。多出來的空間用 baselineOffset 平均分到上下。
    @MainActor var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    @MainActor var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: Theme.text, .paragraphStyle: paragraphStyle,
         .baselineOffset: (lineHeight - (font.ascender - font.descender)) / 2]
    }
}
