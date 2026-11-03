import AppKit

if CommandLine.arguments.contains("--agent-command") {
    exit(AgentCommandClient.run(socketURL: mirrorAgentSocketURL()))
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

func mirrorAgentSocketURL() -> URL {
    if let path = ProcessInfo.processInfo.environment["MIRROR_AGENT_SOCKET"] {
        return URL(fileURLWithPath: path)
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Mirror/agent.sock")
}
