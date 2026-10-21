import DiffCore
import DiffEditor
import SwiftUI

private struct Input: Equatable, Sendable {
    let left: String
    let right: String
    let options: CompareOptions
}

struct ContentView: View {
    @State private var left = ""
    @State private var right = ""
    @State private var options = LaunchDefaults.options
    @State private var collapseUnchanged = LaunchDefaults.showOnlyChanges
    @AppStorage(SettingsKey.language) private var language = AppLanguage.default
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.fontSize) private var fontSize = Double(EditorStyle.default.fontSize)
    @AppStorage(SettingsKey.wrapsLines) private var wrapsLines = true
    @AppStorage(SettingsKey.contextLines) private var contextLines = 3
    @State private var comparison: Comparison?
    @State private var generation = 0

    var body: some View {
        let strings = Strings.for(language)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header(strings.before)
                Divider()
                header(strings.after)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            DiffEditorPair(left: $left, right: $right, comparison: comparison, collapseUnchanged: collapseUnchanged,
                           language: language, style: EditorStyle(fontSize: fontSize, wrapsLines: wrapsLines),
                           contextLines: contextLines)
            Divider()
            StatsBar(stats: comparison?.result.stats, strings: strings)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(strings.showOnlyChanges, isOn: $collapseUnchanged)
            }
            ToolbarItemGroup {
                Toggle(strings.ignoreWhitespace, isOn: $options.ignoreWhitespace)
                Toggle(strings.ignoreBlankLines, isOn: $options.ignoreBlankLines)
                Toggle(strings.ignoreCase, isOn: $options.ignoreCase)
                Toggle(strings.ignoreWidth, isOn: $options.ignoreWidth)
            }
            ToolbarItemGroup {
                Button(strings.swap) { (left, right) = (right, left) }
                Button(strings.clear) { left = ""; right = "" }
            }
        }
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { appearance.apply() }
        .task(id: Input(left: left, right: right, options: options)) {
            let input = Input(left: left, right: right, options: options)
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let result = await compare(input)
            guard !Task.isCancelled else { return }
            generation += 1
            comparison = Comparison(generation: generation, left: input.left, right: input.right, result: result)
        }
    }

    @concurrent
    private nonisolated func compare(_ input: Input) async -> DiffResult {
        computeDiff(left: input.left, right: input.right, options: input.options)
    }

    private func header(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

private struct StatsBar: View {
    let stats: DiffStats?
    let strings: Strings

    var body: some View {
        HStack {
            side(stats?.left)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let stats {
                HStack(spacing: 16) {
                    Text(verbatim: strings.added(stats.insertedCharacters.formatted())).foregroundStyle(.green)
                    Text(verbatim: strings.removed(stats.deletedCharacters.formatted())).foregroundStyle(.red)
                    Text(verbatim: strings.similarity(String(format: "%.1f%%", stats.similarity * 100)))
                }
            }
            side(stats?.right)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func side(_ s: TextStats?) -> some View {
        if let s {
            HStack(spacing: 12) {
                Text(verbatim: "\(strings.characters) \(s.characters.formatted())")
                Text(verbatim: "\(strings.cjkCharacters) \(s.cjkCharacters.formatted())")
                Text(verbatim: "\(strings.lines) \(s.lines.formatted())")
                Text(verbatim: "\(strings.estimatedTokens) \(s.estimatedTokens.formatted())")
            }
            .foregroundStyle(.secondary)
        }
    }
}
