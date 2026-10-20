import DiffCore
import SwiftUI

struct Comparison {
    let generation: Int
    let left: String
    let right: String
    let result: DiffResult
}

private struct Input: Equatable {
    let left: String
    let right: String
    let options: CompareOptions
}

struct ContentView: View {
    @State private var left = ""
    @State private var right = ""
    @State private var options = CompareOptions()
    @State private var comparison: Comparison?
    @State private var generation = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("舊版")
                Divider()
                header("新版")
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            DiffEditorPair(left: $left, right: $right, comparison: comparison)
            Divider()
            StatsBar(stats: comparison?.result.stats)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle("忽略空白", isOn: $options.ignoreWhitespace)
                Toggle("忽略空行", isOn: $options.ignoreBlankLines)
                Toggle("忽略大小寫", isOn: $options.ignoreCase)
                Toggle("忽略全形／半形", isOn: $options.ignoreWidth)
            }
            ToolbarItemGroup {
                Button("對調") { (left, right) = (right, left) }
                Button("清空") { left = ""; right = "" }
            }
        }
        .task(id: Input(left: left, right: right, options: options)) {
            let input = Input(left: left, right: right, options: options)
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let result = await Task.detached {
                computeDiff(left: input.left, right: input.right, options: input.options)
            }.value
            guard !Task.isCancelled else { return }
            generation += 1
            comparison = Comparison(generation: generation, left: input.left, right: input.right, result: result)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

private struct StatsBar: View {
    let stats: DiffStats?

    var body: some View {
        HStack {
            side(stats?.left)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let stats {
                HStack(spacing: 16) {
                    Text("新增 \(stats.insertedCharacters.formatted()) 字").foregroundStyle(.green)
                    Text("刪除 \(stats.deletedCharacters.formatted()) 字").foregroundStyle(.red)
                    Text("相似度 \(String(format: "%.1f", stats.similarity * 100))%")
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
                Text("字元 \(s.characters.formatted())")
                Text("中文字 \(s.cjkCharacters.formatted())")
                Text("行 \(s.lines.formatted())")
                Text("估計 token \(s.estimatedTokens.formatted())")
            }
            .foregroundStyle(.secondary)
        }
    }
}
