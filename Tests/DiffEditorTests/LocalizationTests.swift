import Testing
@testable import DiffEditor

@Suite struct LocalizationTests {
    @Test func englishIsTheDefault() {
        #expect(AppLanguage.default == .english)
        #expect(Strings.for(.english).before == "Before")
        #expect(Strings.for(.english).after == "After")
        #expect(Strings.for(.traditionalChinese).before == "修改前")
        #expect(Strings.for(.traditionalChinese).after == "修改後")
    }

    @Test func noLanguageLeavesAStringEmpty() {
        for language in AppLanguage.allCases {
            let texts = Mirror(reflecting: Strings.for(language)).children.compactMap { $0.value as? String }
            #expect(!texts.isEmpty)
            #expect(texts.allSatisfy { !$0.isEmpty }, "\(language)")
        }
    }

    @Test func formattedStrings() {
        let en = Strings.for(.english)
        let zh = Strings.for(.traditionalChinese)
        #expect(en.unchangedLines(12) == "⋯ 12 unchanged lines")
        #expect(zh.unchangedLines(12) == "⋯ 未變動 12 行")
        #expect(en.movedTo(3) == "Moved to line 3 in After. ⌘-click to jump there.")
        #expect(zh.movedFrom(5) == "從修改前第 5 行移來，⌘ 點一下跳過去")
    }

    @Test func languagesNameThemselves() {
        #expect(AppLanguage.english.displayName == "English")
        #expect(AppLanguage.traditionalChinese.displayName == "繁體中文")
        #expect(AppLanguage(rawValue: "zh-Hant") == .traditionalChinese)
    }
}
