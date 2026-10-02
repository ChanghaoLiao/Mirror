import Foundation
import MirrorCore

@MainActor final class DemoProvider: ConversationProvider {
    let id = "demo"
    let sample: Conversation
    let other: Conversation
    init() {
        var messages: [Message] = [
            .init(
                id: "requirements", role: "You",
                text: """
                    # A second screen for your AI conversations.

                    Keep the requirements beside your work. Every reference has its own reading position, while the conversation itself stays shared.

                    - Select and copy any text.
                    - Use the **upper-left control** for quiet controls.
                    - Press **⌘D** to open another view.

                    > Your main conversation stays exactly where you left it.
                    """),
            .init(
                id: "architecture", role: "Assistant",
                text: """
                    ## One conversation. Many views.

                    Mirror separates *what you read* from **where you read it**. A window can close without affecting its siblings.

                    ```swift
                    let referenceB = referenceA.duplicate()
                    // Both reference the same conversation; their anchors and window geometry are independent.
                    referenceB.anchor = ReadingAnchor(messageID: "architecture")
                    ```

                    | View | Reading position | Independent |
                    | --- | --- | --- |
                    | Reference A | Requirements | Yes |
                    | Reference B | Architecture | Yes |
                    | Reference C | Another conversation | Yes |

                    [Read the App Server documentation](https://learn.chatgpt.com/docs/app-server)
                    """),
        ]
        for index in 0..<16 {
            messages.append(
                .init(
                    id: "detail-\(index)", role: index.isMultiple(of: 2) ? "You" : "Assistant",
                    text: "## Reading detail \(index + 1)\n\n"
                        + String(
                            repeating:
                                "A semantic anchor follows the same character when a narrow window wraps this paragraph onto additional lines. 中文内容自然换行，文字可以正常选择和复制。 ",
                            count: 9)))
        }
        sample = Conversation(
            summary: .init(id: "sample", title: "Designing a quieter workspace"), messages: messages)
        other = Conversation(
            summary: .init(id: "other", title: "Release checklist"),
            messages: [
                .init(
                    id: "checklist", role: "You",
                    text:
                        "# Ready to read\n\n1. Open a reference.\n2. Duplicate it twice.\n3. Keep each view at a different place.\n\n**This is a separate conversation.**"
                )
            ])
    }
    func listConversations(query: String, cursor: String?) async throws -> ConversationPage {
        let items = [sample.summary, other.summary].filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
        return ConversationPage(conversations: items, nextCursor: nil)
    }
    func getConversation(id: String) async throws -> Conversation {
        switch id {
        case "sample": return sample
        case "other": return other
        default: throw ConnectionError.rejected(404)
        }
    }
    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary? { nil }
}
