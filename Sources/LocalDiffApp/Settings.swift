import AppKit
import DiffCore
import DiffEditor
import SwiftUI

/// 偏好設定的 UserDefaults key。只存偏好，不存比對的文字。
enum SettingsKey {
    static let language = "language"
    static let appearance = "appearance"
    static let fontSize = "fontSize"
    static let wrapsLines = "wrapsLines"
    static let contextLines = "contextLines"
    static let showOnlyChanges = "defaultShowOnlyChanges"
    static let ignoreWhitespace = "defaultIgnoreWhitespace"
    static let ignoreBlankLines = "defaultIgnoreBlankLines"
    static let ignoreCase = "defaultIgnoreCase"
    static let ignoreWidth = "defaultIgnoreWidth"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    func label(_ strings: Strings) -> String {
        switch self {
        case .system: strings.appearanceSystem
        case .light: strings.appearanceLight
        case .dark: strings.appearanceDark
        }
    }

    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// App 開啟時工具列開關的初始狀態。
enum LaunchDefaults {
    static var options: CompareOptions {
        let defaults = UserDefaults.standard
        return CompareOptions(ignoreWhitespace: defaults.bool(forKey: SettingsKey.ignoreWhitespace),
                              ignoreBlankLines: defaults.bool(forKey: SettingsKey.ignoreBlankLines),
                              ignoreCase: defaults.bool(forKey: SettingsKey.ignoreCase),
                              ignoreWidth: defaults.bool(forKey: SettingsKey.ignoreWidth))
    }

    static var showOnlyChanges: Bool { UserDefaults.standard.bool(forKey: SettingsKey.showOnlyChanges) }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.language) private var language = AppLanguage.default
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.fontSize) private var fontSize = Double(EditorStyle.default.fontSize)
    @AppStorage(SettingsKey.wrapsLines) private var wrapsLines = true
    @AppStorage(SettingsKey.contextLines) private var contextLines = 3
    @AppStorage(SettingsKey.showOnlyChanges) private var showOnlyChanges = false
    @AppStorage(SettingsKey.ignoreWhitespace) private var ignoreWhitespace = false
    @AppStorage(SettingsKey.ignoreBlankLines) private var ignoreBlankLines = false
    @AppStorage(SettingsKey.ignoreCase) private var ignoreCase = false
    @AppStorage(SettingsKey.ignoreWidth) private var ignoreWidth = false

    var body: some View {
        let strings = Strings.for(language)
        Form {
            Section(strings.generalSection) {
                Picker(strings.language, selection: $language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }
                Picker(strings.appearance, selection: $appearance) {
                    ForEach(Appearance.allCases) { Text(verbatim: $0.label(strings)).tag($0) }
                }
            }
            Section(strings.editorSection) {
                Stepper(value: $fontSize, in: Double(EditorStyle.fontSizes.lowerBound)...Double(EditorStyle.fontSizes.upperBound)) {
                    LabeledContent(strings.fontSize) { Text(verbatim: "\(Int(EditorStyle(fontSize: fontSize).fontSize)) pt") }
                }
                Toggle(strings.wrapLines, isOn: $wrapsLines)
                Stepper(value: $contextLines, in: DiffEditorPair.contextLineRange) {
                    LabeledContent(strings.contextLines) { Text(verbatim: "\(contextLines)") }
                }
            }
            Section(strings.launchDefaultsSection) {
                Toggle(strings.showOnlyChanges, isOn: $showOnlyChanges)
                Toggle(strings.ignoreWhitespace, isOn: $ignoreWhitespace)
                Toggle(strings.ignoreBlankLines, isOn: $ignoreBlankLines)
                Toggle(strings.ignoreCase, isOn: $ignoreCase)
                Toggle(strings.ignoreWidth, isOn: $ignoreWidth)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
