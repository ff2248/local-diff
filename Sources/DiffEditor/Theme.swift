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

    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let lineHeight: CGFloat = 20

    /// 固定行高，讓中英文與 emoji 行一樣高。多出來的空間用 baselineOffset 平均分到上下。
    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }()

    static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: text, .paragraphStyle: paragraphStyle,
         .baselineOffset: (lineHeight - (font.ascender - font.descender)) / 2]
    }

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
