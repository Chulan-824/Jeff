import AppKit
import SwiftUI

@MainActor
private final class ServiceConfig: ObservableObject {
    @Published var apiKey = ""
    @Published var model = "deepseek-chat"
    @Published var baseURL = "https://api.deepseek.com"
    @Published var status: String?
    @Published private(set) var isTesting = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var canAccessKeychain = false
    private var saved = [String]()
    private var testTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    var isDirty: Bool { [apiKey, model, baseURL] != saved }
    var isBusy: Bool { isLoading || isSaving || isTesting }
    private var client: AIClient { AIClient(apiKey: apiKey, model: model, baseURL: baseURL) }

    func load() {
        guard !isSaving else { return }
        cancelPendingWork()
        model = UserDefaults.standard.string(forKey: "model") ?? "deepseek-chat"
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        canAccessKeychain = false
        isLoading = true
        status = "正在读取钥匙串，请留意系统的访问授权提示…"
        loadTask = Task { [weak self] in
            do {
                let key = try await KeychainStore.shared.loadAPIKey() ?? ""
                guard !Task.isCancelled, let self else { return }
                self.apiKey = key
                self.canAccessKeychain = true
                self.saved = [key, self.model, self.baseURL]
                self.status = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = error.localizedDescription
            }
            self?.isLoading = false
        }
    }

    func usePreset(openAI: Bool) {
        cancelPendingWork()
        baseURL = openAI ? "https://api.openai.com/v1" : "https://api.deepseek.com"
        model = openAI ? "gpt-4.1-mini" : "deepseek-chat"
        apiKey = ""
        status = "预设已填入，请填写对应服务的密钥并保存。原配置可通过撤销恢复。"
    }

    func save() {
        guard canAccessKeychain, !isBusy else { return }
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try client.validatedEndpoint()
            let key = apiKey
            let model = model
            let baseURL = baseURL
            isSaving = true
            status = "正在保存到钥匙串…"
            Task {
                do {
                    try await KeychainStore.shared.save(apiKey: key)
                    UserDefaults.standard.set(model, forKey: "model")
                    UserDefaults.standard.set(baseURL, forKey: "baseURL")
                    saved = [key, model, baseURL]
                    status = "已保存"
                } catch { status = error.localizedDescription }
                isSaving = false
            }
        } catch { status = error.localizedDescription }
    }

    func cancelPendingWork() {
        loadTask?.cancel()
        testTask?.cancel()
        isLoading = false
        isTesting = false
    }

    func testConnection() {
        guard !isBusy else { return }
        cancelPendingWork()
        let client = client
        status = "验证中，不会保存当前配置…"
        isTesting = true
        testTask = Task { [weak self] in
            do {
                for try await _ in client.stream(
                    systemPrompt: "Reply with the single word: ok", userContent: "ping")
                {
                    try Task.checkCancellation()
                }
                guard !Task.isCancelled else { return }
                self?.status = "连接正常，配置尚未自动保存。"
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = error.localizedDescription
            }
            self?.isTesting = false
        }
    }
}

struct ServicePage: View {
    @AppStorage("serviceEnabled") private var enabled = true
    @StateObject private var config = ServiceConfig()
    @State private var showsAPIKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("处理服务").font(.title2).bold()
                    Text("配置一个 OpenAI 兼容的 Chat Completions 服务。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用服务", isOn: $enabled).toggleStyle(.switch)
            }
            Divider()
            Form {
                HStack {
                    Text("填入预设")
                    Spacer()
                    Button("DeepSeek") { config.usePreset(openAI: false) }
                    Button("OpenAI") { config.usePreset(openAI: true) }
                }
                Text("选择预设会清空待保存的密钥，请填写该服务的 API Key。也可直接修改地址和模型接入其他兼容服务。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Base URL", text: $config.baseURL)
                    .accessibilityLabel("Base URL")
                Text("填写接口前缀，例如 https://api.openai.com/v1；应用会追加 /chat/completions。本机 HTTP 服务也可使用。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("模型", text: $config.model).accessibilityLabel("模型")
                HStack {
                    Group {
                        if showsAPIKey {
                            TextField("API Key", text: $config.apiKey)
                        } else {
                            SecureField("API Key", text: $config.apiKey)
                        }
                    }
                    .accessibilityLabel("API Key")
                    Button {
                        showsAPIKey.toggle()
                    } label: {
                        Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(showsAPIKey ? "隐藏 API Key" : "显示 API Key")
                }
                Text("密钥仅存入系统钥匙串。原文、补充背景和沟通提示词会发送到这里配置的服务地址。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("验证连接") { config.testConnection() }.disabled(config.isTesting)
                    if config.isBusy { ProgressView().controlSize(.small) }
                }
                if let status = config.status {
                    Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .disabled(config.isBusy)
            HStack {
                if !config.canAccessKeychain {
                    Button("重新读取钥匙串") { config.load() }.disabled(config.isBusy)
                }
                if config.isTesting { Button("停止验证") { config.cancelPendingWork() } }
                Spacer()
                Button("撤销") { config.load() }.disabled(!config.isDirty || config.isBusy)
                Button("保存") { config.save() }
                    .disabled(!config.isDirty || config.isBusy || !config.canAccessKeychain)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { config.load() }
        .onDisappear { config.cancelPendingWork() }
    }
}
