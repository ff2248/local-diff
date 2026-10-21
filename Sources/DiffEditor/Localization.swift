/// 介面語言。新增語言時加一個 case，並在 `Strings.for(_:)` 提供完整的翻譯。
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    public static let `default` = AppLanguage.english

    public var id: String { rawValue }

    /// 以該語言本身書寫的名稱，讓看不懂目前語言的人也找得到。
    public var displayName: String {
        switch self {
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        }
    }
}

/// 所有介面文字。每個欄位都必填，新增語言時漏翻會編譯失敗。
public struct Strings: Sendable {
    public let before: String
    public let after: String

    public let showOnlyChanges: String
    public let ignoreWhitespace: String
    public let ignoreBlankLines: String
    public let ignoreCase: String
    public let ignoreWidth: String
    public let swap: String
    public let clear: String

    public let characters: String
    public let cjkCharacters: String
    public let lines: String
    public let estimatedTokens: String
    public let added: @Sendable (String) -> String
    public let removed: @Sendable (String) -> String
    public let similarity: @Sendable (String) -> String

    public let generalSection: String
    public let language: String
    public let appearance: String
    public let appearanceSystem: String
    public let appearanceLight: String
    public let appearanceDark: String
    public let editorSection: String
    public let fontSize: String
    public let wrapLines: String
    public let contextLines: String
    public let launchDefaultsSection: String

    public let unchangedLines: @Sendable (Int) -> String
    public let movedTo: @Sendable (Int) -> String
    public let movedFrom: @Sendable (Int) -> String
    public let dropMultipleFiles: String
    public let dropTooLarge: String
    public let dropNotText: String

    public static func `for`(_ language: AppLanguage) -> Strings {
        switch language {
        case .english: .english
        case .traditionalChinese: .traditionalChinese
        }
    }

    static let english = Strings(
        before: "Before",
        after: "After",
        showOnlyChanges: "Show Only Changes",
        ignoreWhitespace: "Ignore Whitespace",
        ignoreBlankLines: "Ignore Blank Lines",
        ignoreCase: "Ignore Case",
        ignoreWidth: "Ignore Full/Half Width",
        swap: "Swap",
        clear: "Clear",
        characters: "Characters",
        cjkCharacters: "CJK",
        lines: "Lines",
        estimatedTokens: "Est. Tokens",
        added: { "Added \($0)" },
        removed: { "Removed \($0)" },
        similarity: { "Similarity \($0)" },
        generalSection: "General",
        language: "Language",
        appearance: "Appearance",
        appearanceSystem: "System",
        appearanceLight: "Light",
        appearanceDark: "Dark",
        editorSection: "Editor",
        fontSize: "Font Size",
        wrapLines: "Wrap Long Lines",
        contextLines: "Context Lines Around Changes",
        launchDefaultsSection: "On Launch",
        unchangedLines: { "⋯ \($0) unchanged lines" },
        movedTo: { "Moved to line \($0) in After. ⌘-click to jump there." },
        movedFrom: { "Moved from line \($0) in Before. ⌘-click to jump there." },
        dropMultipleFiles: "Drop one file at a time.",
        dropTooLarge: "The file is larger than 5 MB.",
        dropNotText: "This isn't a UTF-8 text file."
    )

    static let traditionalChinese = Strings(
        before: "修改前",
        after: "修改後",
        showOnlyChanges: "只顯示差異",
        ignoreWhitespace: "忽略空白",
        ignoreBlankLines: "忽略空行",
        ignoreCase: "忽略大小寫",
        ignoreWidth: "忽略全形／半形",
        swap: "對調",
        clear: "清空",
        characters: "字元",
        cjkCharacters: "中文字",
        lines: "行",
        estimatedTokens: "估計 token",
        added: { "新增 \($0) 字" },
        removed: { "刪除 \($0) 字" },
        similarity: { "相似度 \($0)" },
        generalSection: "一般",
        language: "語言",
        appearance: "外觀",
        appearanceSystem: "跟隨系統",
        appearanceLight: "淺色",
        appearanceDark: "深色",
        editorSection: "編輯器",
        fontSize: "字級",
        wrapLines: "自動換行",
        contextLines: "摺疊時保留的行數",
        launchDefaultsSection: "開啟時預設",
        unchangedLines: { "⋯ 未變動 \($0) 行" },
        movedTo: { "已移到修改後第 \($0) 行，⌘ 點一下跳過去" },
        movedFrom: { "從修改前第 \($0) 行移來，⌘ 點一下跳過去" },
        dropMultipleFiles: "一次只能拖放一個檔案。",
        dropTooLarge: "檔案超過 5 MB，無法載入。",
        dropNotText: "這不是 UTF-8 文字檔，無法載入。"
    )
}
