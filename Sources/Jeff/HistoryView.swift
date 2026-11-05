import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var selectedID: UUID?
    @State private var deleting: AdviceRecord?
    @State private var confirmsClear = false

    private var filtered: [AdviceRecord] {
        store.records.filter {
            (!favoritesOnly || $0.isFavorite)
                && (query.isEmpty
                    || ($0.input + $0.output + $0.sourceApp + $0.taskDescription
                        + ($0.context?.relationship ?? "") + ($0.context?.goal ?? ""))
                        .localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索内容、动作或背景", text: $query)
                Toggle("仅收藏", isOn: $favoritesOnly)
                Button("清空全部") { confirmsClear = true }
                    .disabled(store.records.isEmpty && store.errorMessage == nil)
            }
            .padding()
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.orange).padding(.horizontal)
            }
            HSplitView {
                List(filtered, selection: $selectedID) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if record.isFavorite {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                            Text(record.input).lineLimit(2)
                        }
                        Text(
                            "\(record.sourceApp) · \(record.date.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(record.taskDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(record.id)
                }
                .frame(minWidth: 230, idealWidth: 260, maxHeight: .infinity)
                if let record = filtered.first(where: { $0.id == selectedID }) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(record.model).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(record.isFavorite ? "取消收藏" : "收藏") {
                                store.toggleFavorite(record.id)
                            }
                            Button("查看结果") { AdvisorCoordinator.shared.restore(record) }
                            Button(record.result?.copyTitle ?? "复制完整结果") {
                                AdvisorCoordinator.shared.copy(
                                    record.result?.content ?? record.output)
                            }
                            .disabled(record.result?.needsContext == true)
                            Menu {
                                Button("复制完整结果") { AdvisorCoordinator.shared.copy(record.output) }
                                Button("删除", role: .destructive) { deleting = record }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("记录操作")
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(record.input).foregroundStyle(.secondary)
                                Text(record.taskDescription).font(.caption).foregroundStyle(
                                    .secondary)
                                if let context = record.context {
                                    if !context.relationship.isEmpty {
                                        Text("人物关系：\(context.relationship)")
                                    }
                                    if !context.goal.isEmpty { Text("沟通目标：\(context.goal)") }
                                }
                                Divider()
                                if let result = record.result {
                                    AdviceResultView(result: result)
                                } else {
                                    Text(record.output)
                                }
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding().frame(minWidth: 420, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        filtered.isEmpty ? "暂无记录" : "选择一条记录", systemImage: "clock",
                        description: Text("在使用设置中开启历史后，完整结果会保存在本机。")
                    )
                    .frame(minWidth: 420, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 440)
        .alert(
            "删除这条记录？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let deleting { store.remove(deleting.id) }
                deleting = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("清空全部历史和收藏？", isPresented: $confirmsClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.clear() }
        } message: {
            Text("仅清除本机保存的记录，操作无法恢复。")
        }
    }
}
