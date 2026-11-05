import Foundation

enum AdviceAction: String, Codable, CaseIterable, Identifiable {
    case auto, rewrite, reply, analyze

    var id: Self { self }
    var title: String {
        switch self {
        case .auto: "自动"
        case .rewrite: "改写"
        case .reply: "回复"
        case .analyze: "分析"
        }
    }
}

enum CommunicationScene: String, Codable, CaseIterable, Identifiable {
    case general, workplace, government, personal

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "通用"
        case .workplace: "职场"
        case .government: "机关、事业单位、国企"
        case .personal: "家庭朋友"
        }
    }
}

enum CaptureKind: String, Codable {
    case selection, screenshot, clipboard, manual

    var title: String {
        switch self {
        case .selection: "划词"
        case .screenshot: "截图"
        case .clipboard: "剪贴板"
        case .manual: "手动输入"
        }
    }
}

struct AdviceContext: Codable, Equatable {
    var scene: CommunicationScene = .general
    var relationship = ""
    var goal = ""

    var summary: String {
        var parts = [scene.title]
        if !relationship.isEmpty { parts.append("已补充关系") }
        if !goal.isEmpty { parts.append("已补充目标") }
        return parts.joined(separator: " · ")
    }
}

struct AdviceInput: Encodable {
    let originalText: String
    let context: AdviceContext
}

struct AdviceResult: Codable {
    let action: AdviceAction
    let needsContext: Bool
    var content = ""
    var explanation = ""

    var title: String {
        if needsContext { return "需要补充信息" }
        switch action {
        case .rewrite: return "可直接发送"
        case .reply: return "推荐回复"
        case .analyze: return "核心判断与建议"
        case .auto: return "处理结果"
        }
    }

    var fullText: String {
        explanation.isEmpty ? content : content + "\n\n为什么这样说\n" + explanation
    }

    var copyTitle: String { action == .analyze ? "复制分析" : "复制话术" }
}
