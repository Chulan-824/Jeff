import SwiftUI

struct AdviceInputEditor: View {
    @State var text: String
    let isNewInput: Bool
    let onApply: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.callout)
                .frame(minHeight: 100, maxHeight: 180)
                .padding(6)
                .background(
                    Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                .accessibilityLabel("待处理原文")
            HStack {
                Text("修改后统一应用，不会逐字发送。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !isNewInput { Button("取消", action: onCancel) }
                Button(isNewInput ? "开始处理" : "应用并重新生成") { onApply(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct AdviceContextEditor: View {
    @State var context: AdviceContext
    let onApply: (AdviceContext) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("沟通场景", selection: $context.scene) {
                ForEach(CommunicationScene.allCases) { scene in
                    Text(scene.title).tag(scene)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("我是谁，和对方是什么关系").font(.caption)
                TextField("例如：我是小王，张经理是直属领导", text: $context.relationship, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityLabel("人物关系")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("我想达到什么目的").font(.caption)
                TextField("例如：拒绝今晚加班，不承诺明早一定交齐", text: $context.goal, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityLabel("沟通目标")
            }
            Text("背景仅用于本次任务，新一次取词会清空。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("应用并重新生成") {
                    context.relationship = context.relationship.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    context.goal = context.goal.trimmingCharacters(in: .whitespacesAndNewlines)
                    onApply(context)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AdviceResultView: View {
    let result: AdviceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title).font(.caption).foregroundStyle(.secondary)
                Text(result.content).font(.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            if !result.explanation.isEmpty {
                DisclosureGroup("为什么这样说") {
                    Text(result.explanation).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .font(.caption)
            }
        }
    }
}
