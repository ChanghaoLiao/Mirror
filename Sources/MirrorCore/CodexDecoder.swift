import Foundation

public enum CodexDecoder {
    public static func summary(_ thread: JSONValue) throws -> ConversationSummary {
        guard let id = thread["id"].string else { throw DecodeError.missingIdentifier }
        return ConversationSummary(
            id: id,
            title: thread["name"].string
                ?? String((thread["preview"].string ?? "Untitled conversation").prefix(100)))
    }

    public static func messages(_ turns: [JSONValue]) throws -> [Message] {
        var result: [Message] = []
        var seen: Set<String> = []
        for turn in turns {
            guard turn["itemsView"].string == nil || turn["itemsView"].string == "full"
            else { throw DecodeError.incompleteHistory }
            guard let turnID = turn["id"].string else { throw DecodeError.missingIdentifier }
            guard case .array(let items) = turn["items"] else { throw DecodeError.incompleteHistory }
            for item in items {
                guard let itemID = item["id"].string else { throw DecodeError.missingIdentifier }
                let id = turnID + "/" + itemID
                guard seen.insert(id).inserted else { continue }
                let type = item["type"].string ?? "unknown"
                let role: String
                let text: String
                switch type {
                case "userMessage":
                    role = "You"
                    guard case .array(let content) = item["content"] else {
                        throw DecodeError.incompleteHistory
                    }
                    text = content.map { part in
                        switch part["type"].string {
                        case "text": return part["text"].string ?? part.formatted
                        case "localImage": return "![Attached image](\(part["path"].string ?? ""))"
                        case "image": return "![Attached image](\(part["url"].string ?? ""))"
                        default: return part.formatted
                        }
                    }.joined(separator: "\n\n")
                case "agentMessage", "plan":
                    role = type == "plan" ? "Plan" : "Assistant"
                    text = item["text"].string ?? item.formatted
                default:
                    role = type
                    // Keep unfamiliar/tool fields visible, rather than silently dropping text.
                    text = "````json\n\(item.formatted)\n````"
                }
                result.append(Message(id: id, role: role, text: text))
            }
        }
        return result
    }

    public enum DecodeError: Error, LocalizedError {
        case missingIdentifier, incompleteHistory
        public var errorDescription: String? {
            switch self {
            case .missingIdentifier: return "Codex returned a record without a stable identifier."
            case .incompleteHistory:
                return "Codex returned partial history; Mirror has not treated it as complete."
            }
        }
    }
}
