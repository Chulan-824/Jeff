import SwiftUI

struct AdvisorView: View {
    @ObservedObject var coordinator: AdvisorCoordinator
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if coordinator.output.isEmpty && !coordinator.isStreaming {
                        TextEditor(text: $coordinator.selectedText)
                            .font(.callout)
                            .frame(height: 80)
                            .accessibilityLabel("待分析内容")
                    } else {
                        Text(coordinator.selectedText).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(4).textSelection(.enabled)
                    }
                    Text(coordinator.sourceApp).font(.caption).foregroundStyle(.secondary)

                    if let error = coordinator.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }

                    Text(coordinator.output)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if coordinator.isStreaming {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(12)
            }

            Divider()

            footer
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    private var header: some View {
        HStack {
            Text("Jeff")
                .font(.headline)
            if coordinator.isStreaming {
                Text("分析中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: coordinator.dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if coordinator.needsAccessibilityPermission {
                Button("授权辅助功能") {
                    _ = SelectionCapture.isTrusted(prompt: true)
                    SelectionCapture.openAccessibilitySettings()
                }
            }
            Spacer()
            if let id = coordinator.recordID,
                let record = history.records.first(where: { $0.id == id })
            {
                Button(record.isFavorite ? "取消收藏" : "收藏") { history.toggleFavorite(id) }
            }
            Button("重新生成", action: coordinator.regenerate)
                .disabled(coordinator.selectedText.isEmpty || coordinator.isStreaming)
            Button("复制结果", action: coordinator.copyOutput)
                .disabled(coordinator.output.isEmpty)
                .keyboardShortcut("c", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
