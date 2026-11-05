import Foundation

/// Loads the bundled Jeff skill and composes the system prompt.
///
/// The whole skill (~31KB) is injected every request: SKILL.md supplies the
/// workflow/output contract, references/*.md supply per-relationship knowledge.
/// Selective loading could cut tokens later; full injection is more reliable
/// since there is no agent runtime to do step-by-step file reads.
enum SkillStore {

    static func systemPrompt() -> String {
        var parts: [String] = []

        if let skill = loadMarkdown(name: "SKILL") {
            // Strip the YAML front matter.
            parts.append(stripFrontMatter(skill))
        }

        for name in [
            "principles", "relationship-types", "family",
            "romance", "friends", "workplace", "social",
        ] {
            if let ref = loadMarkdown(name: name, subdirectory: "Skills/references") {
                parts.append("\n\n===== 知识库: \(name) =====\n\n" + ref)
            }
        }

        parts.append(
            """

            ===== 输入说明 =====
            用户发来的是他从任意应用中划词选中的一段文字。
            它可能是一段聊天记录、一封邮件草稿、一句想说的话、或对某个场景的描述。
            你的任务：按上面的顾问工作流处理这段内容——分析其中的人际困境并给出策略；
            如果是一段待发送的话，给出优化后的可直接使用的措辞。
            """)
        return parts.joined()
    }

    private static func loadMarkdown(name: String, subdirectory: String = "Skills") -> String? {
        // .app bundle: Contents/Resources/Skills/...
        if let url = Bundle.main.url(
            forResource: name, withExtension: "md",
            subdirectory: subdirectory),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            return text
        }
        // Dev fallback: running via `swift run` from the project root.
        let devPath = "Resources/\(subdirectory)/\(name).md"
        if let text = try? String(contentsOfFile: devPath, encoding: .utf8) {
            return text
        }
        return nil
    }

    private static func stripFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---"),
            let end = text.range(
                of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex)
        else { return text }
        return String(text[end.upperBound...])
    }
}
