import SwiftUI

struct TranslateSettingsPage: View {
    @ObservedObject private var coordinator = AdvisorCoordinator.shared
    @State private var axTrusted = false
    @AppStorage("quietMode") private var quietMode = false
    @AppStorage("autoCopyOutput") private var autoCopy = false
    @AppStorage("saveHistory") private var saveHistory = false
    @AppStorage("mergeOCRLines") private var mergeOCRLines = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("分析设置")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("全局快捷键")
                    VStack(spacing: 0) {
                        shortcutRow(
                            "划词分析", description: "选中一段聊天或场景描述，按下快捷键获取建议。",
                            shortcut: coordinator.selectionShortcut,
                            onRecord: coordinator.saveSelectionShortcut)
                        separator
                        shortcutRow(
                            "截图取词分析", shortcut: coordinator.snipShortcut,
                            onRecord: coordinator.saveSnipShortcut)
                    }
                    .background(groupBackground, in: RoundedRectangle(cornerRadius: 9))

                    sectionTitle("结果与记录")
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("静默模式", isOn: $quietMode)
                        Text("划词、截图和剪贴板分析只显示小浮窗，不主动切换焦点。完成后 12 秒隐藏，可从菜单栏查看完整结果。")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("完整结果自动复制到剪贴板", isOn: $autoCopy)
                        Toggle("保存本机历史", isOn: $saveHistory)
                        Text("默认关闭。开启后保存原文、建议、模型、时间和来源应用；保留最近 100 条普通记录，收藏单独保留。关闭后已有记录仍可查看和删除。")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("OCR 合并同段落换行", isOn: $mergeOCRLines)
                        Text("适合横排单栏截图。聊天气泡、多栏或竖排文字可关闭合并。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("剪贴板分析、手动输入和历史收藏可从菜单栏打开。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(groupBackground, in: RoundedRectangle(cornerRadius: 9))

                    sectionTitle("权限")
                    HStack {
                        Text("辅助功能")
                        Spacer()
                        Circle()
                            .fill(axTrusted ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(axTrusted ? "已授权" : "未授权")
                            .foregroundStyle(.secondary)
                        Button("去授权") {
                            _ = SelectionCapture.isTrusted(prompt: true)
                            SelectionCapture.openAccessibilitySettings()
                        }
                    }
                    .font(.system(size: 13))
                    .padding(10)
                    .background(groupBackground, in: RoundedRectangle(cornerRadius: 9))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            axTrusted = SelectionCapture.isTrusted(prompt: false)
            coordinator.needsAccessibilityPermission = !axTrusted
        }
    }

    private var groupBackground: Color { Color(nsColor: .quaternaryLabelColor).opacity(0.3) }

    private var separator: some View {
        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.2))
            .padding(.horizontal, 10)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.leading, 10)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }

    private func shortcutRow(
        _ title: String, description: String? = nil, shortcut: RecordedShortcut? = nil,
        onRecord: ((RecordedShortcut?) -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, description == nil ? 5 : 0)

            ShortcutRecorder(
                shortcut: shortcut, isEnabled: onRecord != nil,
                label: title, onRecord: { onRecord?($0) }
            )
            .frame(width: 190, height: 28)
            .help(onRecord == nil ? "此功能暂未接入" : "点击录制快捷键，Esc 取消；点击 × 清除")
        }
        .padding(10)
    }
}
