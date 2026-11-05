import Foundation

/// Decode complete JSON lines so protocol fragments never appear in the UI or clipboard.
struct AdviceStream {
    let requestedAction: AdviceAction
    private var buffer = ""
    private(set) var result: AdviceResult?

    init(requestedAction: AdviceAction) {
        self.requestedAction = requestedAction
    }

    mutating func append(_ chunk: String) throws {
        buffer += chunk
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            try consume(line)
        }
    }

    mutating func finish() throws -> AdviceResult {
        try consume(buffer)
        buffer = ""
        guard var result else { throw FormatError.invalidResponse }
        result.content = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        result.explanation = result.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.content.isEmpty else { throw FormatError.invalidResponse }
        return result
    }

    private mutating func consume(_ rawLine: String) throws {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else {
            throw FormatError.invalidResponse
        }
        switch event.kind {
        case "start":
            guard result == nil, let action = event.action, action != .auto,
                requestedAction == .auto || action == requestedAction,
                let needsContext = event.needsContext
            else { throw FormatError.invalidResponse }
            // Analysis can describe known facts and limits without knowing the user's identity.
            result = AdviceResult(action: action, needsContext: action != .analyze && needsContext)
        case "content", "explanation":
            guard result != nil, let text = event.text else { throw FormatError.invalidResponse }
            if event.kind == "content" {
                result?.content += text
            } else {
                result?.explanation += text
            }
        default:
            throw FormatError.invalidResponse
        }
    }

    private struct Event: Decodable {
        let kind: String
        let action: AdviceAction?
        let needsContext: Bool?
        let text: String?
    }

    private enum FormatError: LocalizedError {
        case invalidResponse
        var errorDescription: String? {
            "模型未按所选动作返回可识别的结果，请重新生成。已有原文和上一版结果已保留。"
        }
    }
}
