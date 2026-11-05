import SwiftUI

struct AdvisorView: View {
    @ObservedObject var coordinator: AdvisorCoordinator
    @ObservedObject private var history = HistoryStore.shared
    @State private var editsOriginal = false
    @State private var editsContext = false
    @State private var expandsOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(
                        "处理动作",
                        selection: Binding(
                            get: { coordinator.action }, set: { coordinator.changeAction($0) })
                    ) {
                        ForEach(AdviceAction.allCases) { action in Text(action.title).tag(action) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("处理动作")
                    Text(coordinator.actionDescription).font(.caption).foregroundStyle(.secondary)
                    original
                    context
                    if let error = coordinator.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout).textSelection(.enabled)
                    }
                    if let message = coordinator.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    if let result = coordinator.result {
                        AdviceResultView(result: result)
                        if !coordinator.isResultComplete && !coordinator.isStreaming
                            && !result.content.isEmpty
                        {
                            Text("未完成的内容，仅供查看。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if result.needsContext {
                            HStack {
                                Button("补充背景") { editsContext = true }
                                Button("编辑原文") { editsOriginal = true }
                            }
                        }
                    } else if !coordinator.legacyOutput.isEmpty {
                        Text(coordinator.legacyOutput).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if coordinator.isStreaming {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(coordinator.progressTitle).font(.caption).foregroundStyle(
                                .secondary)
                        }
                    }
                    previousResult
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 420)
        .onChange(of: coordinator.taskID) { _, _ in
            editsOriginal = false
            editsContext = false
            expandsOriginal = false
        }
        .onExitCommand { coordinator.dismiss() }
    }

    private var header: some View {
        HStack {
            Text("Jeff").font(.headline)
            Spacer()
            Text(coordinator.sourceDescription).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Button(action: coordinator.dismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("关闭并停止处理")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder
    private var original: some View {
        if editsOriginal || coordinator.selectedText.isEmpty {
            AdviceInputEditor(
                text: coordinator.selectedText, isNewInput: coordinator.selectedText.isEmpty,
                onApply: { text in
                    coordinator.applyInput(text)
                    editsOriginal = false
                }, onCancel: { editsOriginal = false }
            )
            .id(coordinator.taskID)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(coordinator.captureKind == .screenshot ? "识别文字 · 可校正" : "本次原文")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("编辑") { editsOriginal = true }.font(.caption)
                }
                Text(coordinator.selectedText).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(expandsOriginal ? nil : 3).textSelection(.enabled)
                Button(expandsOriginal ? "收起原文" : "展开原文") { expandsOriginal.toggle() }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    @ViewBuilder
    private var context: some View {
        HStack {
            Text("场景：\(coordinator.context.summary)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(editsContext ? "收起背景" : "补充背景") { editsContext.toggle() }.font(.caption)
        }
        if editsContext {
            AdviceContextEditor(
                context: coordinator.context,
                onApply: { context in
                    coordinator.applyContext(context)
                    editsContext = false
                }, onCancel: { editsContext = false }
            )
            .id(coordinator.taskID)
        }
    }

    @ViewBuilder
    private var previousResult: some View {
        if let previous = coordinator.previousResult {
            DisclosureGroup("上一版结果 · \(previous.taskDescription)") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(previous.output).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("返回上一版", action: coordinator.restorePrevious)
                }
                .padding(.top, 8)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if coordinator.needsAccessibilityPermission {
                Button("授权辅助功能") {
                    _ = SelectionCapture.isTrusted(prompt: true)
                    SelectionCapture.openAccessibilitySettings()
                }
            }
            Spacer(minLength: 0)
            if let id = coordinator.recordID,
                let record = history.records.first(where: { $0.id == id })
            {
                Button(record.isFavorite ? "取消收藏" : "收藏") { history.toggleFavorite(id) }
            }
            Menu {
                Button("复制完整结果", action: coordinator.copyOutput)
                    .disabled(!coordinator.isResultComplete || coordinator.isStreaming)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多操作")
            if coordinator.isStreaming {
                Button("停止", action: coordinator.stop)
            } else if !coordinator.selectedText.isEmpty {
                Button(
                    coordinator.errorMessage == nil ? "重新生成" : "重试", action: coordinator.regenerate)
            }
            Button(coordinator.copyTitle, action: coordinator.copyPrimary)
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.canCopyPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
