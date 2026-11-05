import Foundation

struct AIClient {
    var apiKey: String
    var model: String
    var baseURL: String

    enum ClientError: LocalizedError {
        case configuration(String)
        case httpStatus(Int)
        case invalidResponse
        case incomplete(String)

        var errorDescription: String? {
            switch self {
            case .configuration(let message): return message
            case .httpStatus(let code): return "服务返回 HTTP \(code)，请检查密钥、模型、额度和服务地址。"
            case .invalidResponse: return "服务返回了无法识别的响应，请确认支持 Chat Completions 流式接口。"
            case .incomplete(let reason): return "结果未完成（\(reason)），部分内容已保留，请重试。"
            }
        }
    }

    func validatedEndpoint() throws -> URL {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.configuration("请在设置中填写 API Key。")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.configuration("请填写模型名称。")
        }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            url.scheme == "https"
                || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host))
        else {
            throw ClientError.configuration("Base URL 必须是 HTTPS 地址，本机服务也可使用 HTTP；不要包含密钥、查询参数或片段。")
        }
        return url.appendingPathComponent("chat/completions")
    }

    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: try validatedEndpoint())
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 120
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userContent],
                        ],
                    ])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ClientError.httpStatus(http.statusCode)
                    }

                    var finishReason: String?
                    var hasContent = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                            let obj = try JSONSerialization.jsonObject(with: data)
                                as? [String: Any],
                            obj["error"] == nil,
                            let choices = obj["choices"] as? [[String: Any]]
                        else {
                            throw ClientError.invalidResponse
                        }
                        guard let choice = choices.first else { continue }
                        if let reason = choice["finish_reason"] as? String { finishReason = reason }
                        if let delta = choice["delta"] as? [String: Any],
                            let content = delta["content"] as? String, !content.isEmpty
                        {
                            hasContent = true
                            continuation.yield(content)
                        }
                    }
                    try Task.checkCancellation()
                    guard finishReason == "stop" else {
                        throw ClientError.incomplete(finishReason ?? "连接提前结束")
                    }
                    guard hasContent else { throw ClientError.invalidResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
