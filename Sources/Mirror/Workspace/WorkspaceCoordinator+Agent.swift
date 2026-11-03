import AppKit
import MirrorCore

extension WorkspaceCoordinator {
    func humanDidInteract() {
        guard !applyingAgentCommand else { return }
        agentRevision += 1
        for reference in windows.values { reference.relinquishAgentLoad() }
    }

    func setAgentEnabled(_ enabled: Bool) {
        humanDidInteract()
        agentEnabled = enabled
        MirrorPreferences.defaults.set(!enabled, forKey: "mirror.agent.paused")
    }

    func setBinding(_ host: HostWindow, workspaceID: UUID) {
        guard let index = saved.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        monitor.bindings[workspaceID] = host
        saved.workspaces[index].hostTitle = host.title
        saved.workspaces[index].hostBundleID = host.bundleID
        scheduleSave()
    }

    func removeBinding(workspaceID: UUID) {
        monitor.bindings[workspaceID] = nil
        if let index = saved.workspaces.firstIndex(where: { $0.id == workspaceID }) {
            // Empty titles cannot be restored by the normal host matcher.
            saved.workspaces[index].hostTitle = "Unbound"
        }
        scheduleSave()
        updateVisibility()
    }

    private func agentSnapshot() -> [AgentWindowSnapshot] {
        windows.values.sorted { $0.state.id.uuidString < $1.state.id.uuidString }.map {
            AgentWindowSnapshot(
                id: $0.state.id, conversationID: $0.state.conversationID,
                messageID: $0.state.anchor?.messageID, collapsed: $0.state.collapsed,
                bound: monitor.bindings[$0.state.workspaceID] != nil,
                fontSize: $0.state.settings.fontSize, frame: $0.state.frame,
                loading: $0.isLoading, contentStatus: $0.contentStatus)
        }
    }

    func agentResponse(
        ok: Bool, status: String, message: String? = nil,
        windowID: UUID? = nil, binding: String? = nil
    ) -> AgentResponse {
        AgentResponse(
            ok: ok, status: status, message: message, revision: agentRevision,
            windows: agentSnapshot(), windowID: windowID, binding: binding,
            loading: windowID.flatMap { windows[$0]?.isLoading },
            agentEnabled: agentEnabled, appVersion: "1.0.0",
            accessibilityGranted: monitor.trusted)
    }

    func handleAgent(_ request: AgentRequest) -> AgentResponse {
        if let error = request.validationError {
            return agentResponse(ok: false, status: "invalid_arguments", message: error)
        }
        if request.action == "status" || request.action == "list" {
            return agentResponse(ok: true, status: "ready")
        }
        if let (original, receipt) = agentReceipts[request.requestID] {
            guard original == request else {
                return agentResponse(ok: false, status: "request_id_conflict")
            }
            return receipt
        }
        guard agentEnabled else { return agentResponse(ok: false, status: "agent_paused") }
        guard request.expectedRevision == agentRevision else {
            return agentResponse(
                ok: false, status: "revision_conflict",
                message:
                    "Mirror changed after your last observation. Stop and respect the user's action; do not automatically retry."
            )
        }
        applyingAgentCommand = true
        defer { applyingAgentCommand = false }
        let result = performAgent(request)
        agentReceipts[request.requestID] = (request, result)
        agentReceiptOrder.append(request.requestID)
        if agentReceiptOrder.count > 128 {
            agentReceipts[agentReceiptOrder.removeFirst()] = nil
        }
        return result
    }

    private func automaticBinding(_ reference: ReferenceWindow, candidate: (HostWindow?, String)? = nil)
        -> String
    {
        if agentHostResolver == nil && !monitor.trusted { return "permission_required" }
        if monitor.bindings[reference.state.workspaceID] != nil {
            if agentHostResolver != nil { return "bound" }
            switch monitor.availability(reference.state.workspaceID) {
            case .closed: return "host_not_found"
            case .unavailable: return "host_unavailable"
            default: return "bound"
            }
        }
        let (host, status) = candidate ?? agentHostResolver?() ?? monitor.automaticHost()
        if let host { setBinding(host, workspaceID: reference.state.workspaceID) }
        return status
    }

    private func performAgent(_ request: AgentRequest) -> AgentResponse {
        var reference = request.windowID.flatMap { windows[$0] }
        if request.windowID != nil && reference == nil {
            return agentResponse(ok: false, status: "window_not_found")
        }
        if request.action == "open" {
            guard let conversationID = request.conversationID else {
                return agentResponse(ok: false, status: "invalid_arguments")
            }
            if reference == nil, request.newWindow != true {
                let matches = windows.values.filter { $0.requestedConversationID == conversationID }
                guard matches.count <= 1 else {
                    return agentResponse(
                        ok: false, status: "ambiguous_window",
                        message: "Select one existing window ID, or explicitly request a new reference.")
                }
                reference = matches.first
            }
            // Capture before activating Mirror; activation must not change host selection.
            let candidate = agentHostResolver?() ?? monitor.automaticHost()
            if let existing = reference {
                existing.state.collapsed = false
                if existing.requestedConversationID != conversationID || request.messageID != nil {
                    existing.load(
                        conversationID, anchor: request.messageID.map { ReadingAnchor(messageID: $0) })
                    existing.agentLoadInProgress = true
                }
            } else {
                let id = open(
                    conversationID: conversationID, messageID: request.messageID,
                    hostOverride: candidate.0, agentOrigin: true)
                reference = windows[id]
            }
            guard let reference else { return agentResponse(ok: false, status: "window_not_found") }
            let binding = automaticBinding(reference, candidate: candidate)
            presentAgentReference(reference)
            agentRevision += 1
            scheduleSave()
            return agentResponse(
                ok: true, status: reference.isLoading ? "loading" : "applied",
                windowID: reference.state.id, binding: binding)
        }
        guard let reference else { return agentResponse(ok: false, status: "window_required") }
        var returnedID = reference.state.id
        var binding: String?
        switch request.action {
        case "duplicate":
            reference.captureFrame()
            reference.state.anchor = reference.surface.reader.anchor
            let copy = reference.state.duplicate()
            create(copy, focus: true)
            windows[copy.id]?.agentLoadInProgress = true
            returnedID = copy.id
        case "close": reference.close()
        case "hide": reference.act("collapse")
        case "cancel": reference.cancelLoad()
        case "copy":
            guard reference.displayedSnapshot?.messages.isEmpty == false else {
                return agentResponse(ok: false, status: "content_unavailable")
            }
            reference.act("copy")
        case "show": presentAgentReference(reference)
        case "refresh":
            guard reference.requestedConversationID != nil else {
                return agentResponse(ok: false, status: "content_unavailable")
            }
            reference.act("refresh")
            reference.agentLoadInProgress = reference.isLoading
        case "find":
            guard !reference.isLoading else { return agentResponse(ok: false, status: "content_loading") }
            reference.surface.controls.search.stringValue = request.query ?? ""
            reference.find()
            reference.surface.controls.status.stringValue = reference.surface.reader.search(
                request.query ?? "")
            presentAgentReference(reference)
        case "font": reference.setFontSize(request.fontSize ?? reference.state.settings.fontSize)
        case "frame":
            guard let frame = request.frame, let window = reference.window else {
                return agentResponse(ok: false, status: "invalid_arguments")
            }
            window.setFrame(
                NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), display: true)
            clamp(window)
            reference.captureFrame()
        case "bind":
            binding = automaticBinding(reference)
            guard binding == "bound" else {
                return agentResponse(
                    ok: false, status: binding ?? "host_not_found", windowID: returnedID,
                    binding: binding)
            }
        case "unbind":
            removeBinding(workspaceID: reference.state.workspaceID)
            binding = "unbound"
        default: return agentResponse(ok: false, status: "unsupported_action")
        }
        agentRevision += 1
        scheduleSave()
        updateVisibility()
        return agentResponse(
            ok: true, status: reference.isLoading ? "loading" : "applied",
            windowID: returnedID, binding: binding)
    }

    private func presentAgentReference(_ reference: ReferenceWindow) {
        lastWorkspace = reference.state.workspaceID
        reference.state.collapsed = false
        NSApp.activate(ignoringOtherApps: true)
        reference.window?.makeKeyAndOrderFront(nil)
        updateVisibility()
    }
}
