import SwiftUI

struct AdvisorHUD: View {
    @ObservedObject var coordinator: AdvisorCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(coordinator.isStreaming ? "Jeff · 分析中…" : "Jeff")
                    .font(.headline)
                Spacer()
                Button(action: coordinator.dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭并停止分析")
            }
            if let error = coordinator.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).lineLimit(3)
            }
            Text(
                coordinator.output.isEmpty && coordinator.errorMessage == nil
                    ? "正在准备建议…" : coordinator.output
            )
            .font(.callout).lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                if coordinator.isStreaming { ProgressView().controlSize(.small) }
                Spacer()
                Button("查看完整结果", action: coordinator.showResult)
                Button("复制", action: coordinator.copyOutput).disabled(coordinator.output.isEmpty)
            }
        }
        .padding(14)
    }
}
