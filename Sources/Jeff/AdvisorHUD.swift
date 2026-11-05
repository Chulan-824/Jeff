import SwiftUI

struct AdvisorHUD: View {
    @ObservedObject var coordinator: AdvisorCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Jeff").font(.headline)
                Spacer()
                Button(action: coordinator.dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭并停止处理")
            }
            Text(coordinator.actionDescription).font(.caption).foregroundStyle(.secondary)
            if let error = coordinator.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).lineLimit(3)
            }
            Text(coordinator.primaryText.isEmpty ? "正在准备结果…" : coordinator.primaryText)
                .font(.callout).lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message = coordinator.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                if coordinator.isStreaming { ProgressView().controlSize(.small) }
                Spacer()
                Button(
                    coordinator.result?.needsContext == true ? "补充信息" : "展开",
                    action: coordinator.showResult)
                Button(coordinator.copyTitle, action: coordinator.copyPrimary)
                    .disabled(!coordinator.canCopyPrimary)
            }
        }
        .padding(14)
    }
}
