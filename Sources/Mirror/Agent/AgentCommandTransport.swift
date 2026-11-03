import Darwin
import Foundation
import MirrorCore

enum AgentTransportError: Error, LocalizedError {
    case unsafePath, alreadyRunning, unavailable, timeout, oversized, malformed, io
    var status: String {
        switch self {
        case .unsafePath: return "unsafe_path"
        case .alreadyRunning: return "already_running"
        case .unavailable: return "service_unavailable"
        case .timeout: return "timeout"
        case .oversized: return "message_too_large"
        case .malformed: return "invalid_request"
        case .io: return "connection_failed"
        }
    }
    var errorDescription: String? {
        switch self {
        case .unsafePath: return "Mirror's local socket path or permissions are unsafe."
        case .alreadyRunning: return "Another Mirror command service is already running."
        case .unavailable: return "Mirror's local command service is not available."
        case .timeout: return "Mirror did not respond before the command deadline."
        case .oversized: return "Mirror commands and responses must be smaller than 64 KB."
        case .malformed: return "Expected one valid Mirror command JSON object."
        case .io: return "The local Mirror connection ended unexpectedly."
        }
    }
}

/// A private Unix socket, accessible only to the current macOS user. It never listens on TCP.
final class AgentCommandServer: @unchecked Sendable {
    private let socketURL: URL
    private let handler: @MainActor (AgentRequest) -> AgentResponse
    private let queue = DispatchQueue(label: "local.mirror.agent", qos: .userInitiated)
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var listener: Int32 = -1
    private var generation: UUID?
    private var connections: Set<Int32> = []
    private var identity: SocketIdentity?

    init(socketURL: URL, handler: @escaping @MainActor (AgentRequest) -> AgentResponse) {
        self.socketURL = socketURL
        self.handler = handler
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }
        try AgentSocket.prepareParent(socketURL, create: true)
        try AgentSocket.removeStaleSocket(socketURL)
        let fd = try AgentSocket.makeSocket()
        var owned: SocketIdentity?
        do {
            try AgentSocket.withAddress(socketURL) { address, length in
                guard Darwin.bind(fd, address, length) == 0 else { throw AgentTransportError.io }
            }
            owned = try AgentSocket.socketIdentity(socketURL)
            guard chmod(socketURL.path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
                throw AgentTransportError.io
            }
            let token = UUID()
            let newSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            newSource.setEventHandler { [weak self] in self?.acceptConnections(fd, generation: token) }
            newSource.setCancelHandler { Darwin.close(fd) }
            listener = fd
            generation = token
            identity = owned
            source = newSource
            newSource.resume()
        } catch {
            Darwin.close(fd)
            if let owned { AgentSocket.unlink(socketURL, matching: owned) }
            throw error
        }
    }

    func stop() {
        lock.lock()
        let oldSource = source
        let oldListener = listener
        let oldIdentity = identity
        source = nil
        listener = -1
        generation = nil
        identity = nil
        for fd in connections { _ = Darwin.shutdown(fd, SHUT_RDWR) }
        lock.unlock()
        if oldListener >= 0 { _ = Darwin.shutdown(oldListener, SHUT_RDWR) }
        oldSource?.cancel()
        if let oldIdentity { AgentSocket.unlink(socketURL, matching: oldIdentity) }
    }

    deinit { stop() }

    private func isActive(_ token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    private func acceptConnections(_ listener: Int32, generation token: UUID) {
        while isActive(token) {
            let fd = Darwin.accept(listener, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return
            }
            lock.lock()
            let active = generation == token
            if active { connections.insert(fd) }
            lock.unlock()
            guard active else {
                Darwin.close(fd)
                return
            }
            defer {
                lock.lock()
                connections.remove(fd)
                lock.unlock()
                Darwin.close(fd)
            }
            do {
                try AgentSocket.configure(fd)
                try AgentSocket.verifyPeer(fd)
                let connectionDeadline = AgentSocket.now + 4
                let bytes = try AgentSocket.readLine(fd, deadline: connectionDeadline)
                let request: AgentRequest
                do { request = try JSONDecoder().decode(AgentRequest.self, from: bytes) } catch {
                    throw AgentTransportError.malformed
                }
                try request.validate()
                let callerDeadline = try JSONDecoder().decode(CommandDeadline.self, from: bytes).deadline
                let deadline = min(connectionDeadline, callerDeadline ?? connectionDeadline)
                let result = ResponseBox()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isActive(token), AgentSocket.now < deadline,
                        AgentSocket.peerStillConnected(fd)
                    else {
                        result.finish(AgentResponse(ok: false, status: "service_unavailable"))
                        return
                    }
                    result.finish(self.handler(request))
                }
                guard result.ready.wait(timeout: .now() + max(0, deadline - AgentSocket.now)) == .success,
                    let response = result.value
                else { throw AgentTransportError.timeout }
                try AgentSocket.writeJSON(response, to: fd, deadline: deadline)
            } catch {
                // A malformed or slow client must not stop the next local command.
                try? AgentSocket.writeJSON(
                    AgentSocket.errorResponse(error), to: fd,
                    deadline: AgentSocket.now + 0.1)
            }
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var response: AgentResponse?
    var value: AgentResponse? {
        lock.lock()
        defer { lock.unlock() }
        return response
    }
    func finish(_ value: AgentResponse) {
        lock.lock()
        response = value
        lock.unlock()
        ready.signal()
    }
}

enum AgentCommandClient {
    /// Called before NSApplication is created; stdin/stdout are the complete CLI interface.
    static func run(socketURL: URL) -> Int32 {
        let outputDeadline = AgentSocket.now + 5
        let deadline = outputDeadline - 0.05
        let response: AgentResponse
        do {
            let bytes = try AgentSocket.readLine(STDIN_FILENO, deadline: deadline, allowEOF: true)
            let request: AgentRequest
            do { request = try JSONDecoder().decode(AgentRequest.self, from: bytes) } catch {
                throw AgentTransportError.malformed
            }
            response = try send(request: request, socketURL: socketURL, deadline: deadline)
        } catch { response = AgentSocket.errorResponse(error) }
        // Output itself is bounded too, even when the caller does not drain stdout.
        let outputFlags = fcntl(STDOUT_FILENO, F_GETFL)
        guard outputFlags >= 0, fcntl(STDOUT_FILENO, F_SETFL, outputFlags | O_NONBLOCK) == 0 else { return 1 }
        defer { _ = fcntl(STDOUT_FILENO, F_SETFL, outputFlags) }
        do { try AgentSocket.writeJSON(response, to: STDOUT_FILENO, deadline: outputDeadline) } catch {
            return 1
        }
        return response.ok ? 0 : 1
    }

    static func send(request: AgentRequest, socketURL: URL, timeout: TimeInterval = 5) throws -> AgentResponse
    {
        try send(request: request, socketURL: socketURL, deadline: AgentSocket.now + min(5, max(0, timeout)))
    }

    private static func send(request: AgentRequest, socketURL: URL, deadline: TimeInterval) throws
        -> AgentResponse
    {
        try request.validate()
        try AgentSocket.prepareParent(socketURL, create: false)
        let identity = try AgentSocket.socketIdentity(socketURL)
        guard identity.mode & 0o777 == 0o600 else { throw AgentTransportError.unsafePath }
        let fd = try AgentSocket.makeSocket()
        defer { Darwin.close(fd) }
        try AgentSocket.connect(fd, url: socketURL, deadline: deadline)
        try AgentSocket.verifyPeer(fd)
        try AgentSocket.writeJSON(
            WireRequest(request: request, deadline: deadline), to: fd, deadline: deadline)
        let data = try AgentSocket.readLine(fd, deadline: deadline)
        do { return try JSONDecoder().decode(AgentResponse.self, from: data) } catch {
            throw AgentTransportError.io
        }
    }
}

// The transport supplies the caller's monotonic deadline without changing the public command
// or request equality. A queued command cannot run after its CLI caller has timed out.
private struct CommandDeadline: Decodable {
    var deadline: TimeInterval?
    enum CodingKeys: String, CodingKey { case deadline = "_deadlineUptime" }
}

private struct WireRequest: Encodable {
    var request: AgentRequest
    var deadline: TimeInterval
    func encode(to encoder: Encoder) throws {
        try request.encode(to: encoder)
        var values = encoder.container(keyedBy: CommandDeadline.CodingKeys.self)
        try values.encode(deadline, forKey: .deadline)
    }
}

private struct SocketIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
}

private enum AgentSocket {
    static let limit = 64 * 1024
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func prepareParent(_ url: URL, create: Bool) throws {
        guard url.isFileURL, url.path == url.standardizedFileURL.path else {
            throw AgentTransportError.unsafePath
        }
        let parent = url.deletingLastPathComponent()
        // Inspect every existing component, rather than following a symlink into another location.
        var component = URL(fileURLWithPath: "/", isDirectory: true)
        let parts = parent.pathComponents.dropFirst()
        for (index, part) in parts.enumerated() {
            component.appendPathComponent(part, isDirectory: true)
            var info = stat()
            if lstat(component.path, &info) != 0 {
                guard create, errno == ENOENT, index == parts.count - 1,
                    mkdir(component.path, 0o700) == 0,
                    lstat(component.path, &info) == 0
                else { throw AgentTransportError.unavailable }
            }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw AgentTransportError.unsafePath }
            if index == parts.count - 1 {
                guard info.st_uid == getuid() else { throw AgentTransportError.unsafePath }
                if create {
                    guard chmod(component.path, 0o700) == 0 else { throw AgentTransportError.unsafePath }
                } else if info.st_mode & 0o777 != 0o700 {
                    throw AgentTransportError.unsafePath
                }
            }
        }
    }

    static func socketIdentity(_ url: URL) throws -> SocketIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw AgentTransportError.unavailable }
        guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else {
            throw AgentTransportError.unsafePath
        }
        return SocketIdentity(device: info.st_dev, inode: info.st_ino, mode: info.st_mode)
    }

    static func unlink(_ url: URL, matching identity: SocketIdentity) {
        guard let current = try? socketIdentity(url), current.device == identity.device,
            current.inode == identity.inode
        else { return }
        _ = Darwin.unlink(url.path)
    }

    static func removeStaleSocket(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            guard errno == ENOENT else { throw AgentTransportError.unsafePath }
            return
        }
        let identity = try socketIdentity(url)
        let fd = try makeSocket()
        defer { Darwin.close(fd) }
        let result = try withAddress(url) { Darwin.connect(fd, $0, $1) }
        if result == 0 || errno == EINPROGRESS || errno == EAGAIN { throw AgentTransportError.alreadyRunning }
        guard errno == ECONNREFUSED else { throw AgentTransportError.unsafePath }
        guard let current = try? socketIdentity(url), current == identity else {
            throw AgentTransportError.unsafePath
        }
        guard Darwin.unlink(url.path) == 0 else { throw AgentTransportError.io }
    }

    static func makeSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentTransportError.io }
        do {
            try configure(fd)
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func configure(_ fd: Int32) throws {
        var enabled: Int32 = 1
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0,
            fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
                == 0
        else { throw AgentTransportError.io }
    }

    static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw AgentTransportError.unsafePath }
    }

    static func peerStillConnected(_ fd: Int32) -> Bool {
        var byte: UInt8 = 0
        let result = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return result > 0 || (result < 0 && (errno == EAGAIN || errno == EINTR))
    }

    static func withAddress<T>(_ url: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws
        -> T
    {
        var address = sockaddr_un()
        let bytes = Array(url.path.utf8) + [UInt8(0)]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentTransportError.unsafePath
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func connect(_ fd: Int32, url: URL, deadline: TimeInterval) throws {
        let result = try withAddress(url) { Darwin.connect(fd, $0, $1) }
        if result == 0 { return }
        guard errno == EINPROGRESS else { throw AgentTransportError.unavailable }
        try wait(fd, events: Int16(POLLOUT), deadline: deadline)
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout.size(ofValue: error))
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
            throw AgentTransportError.unavailable
        }
    }

    static func wait(_ fd: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - now
            guard remaining > 0 else { throw AgentTransportError.timeout }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(5_000, ceil(remaining * 1_000))))
            if result == 0 { throw AgentTransportError.timeout }
            if result < 0 {
                if errno == EINTR { continue }
                throw AgentTransportError.io
            }
            guard descriptor.revents & Int16(POLLNVAL) == 0 else { throw AgentTransportError.io }
            return
        }
    }

    static func readLine(_ fd: Int32, deadline: TimeInterval, allowEOF: Bool = false) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            try wait(fd, events: Int16(POLLIN), deadline: deadline)
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw AgentTransportError.io
            }
            if count == 0 {
                if allowEOF, !data.isEmpty { return data }
                throw AgentTransportError.malformed
            }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= limit else { throw AgentTransportError.oversized }
            if let newline = data.firstIndex(of: 10) {
                guard
                    data.suffix(from: data.index(after: newline)).allSatisfy({
                        $0 == 13 || $0 == 10 || $0 == 32 || $0 == 9
                    })
                else { throw AgentTransportError.malformed }
                return data.prefix(upTo: newline)
            }
        }
    }

    static func writeJSON<T: Encodable>(_ value: T, to fd: Int32, deadline: TimeInterval) throws {
        var bytes = try JSONEncoder().encode(value)
        bytes.append(10)
        guard bytes.count <= limit else { throw AgentTransportError.oversized }
        var offset = 0
        while offset < bytes.count {
            try wait(fd, events: Int16(POLLOUT), deadline: deadline)
            let count = bytes.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw AgentTransportError.io
            }
            guard count > 0 else { throw AgentTransportError.io }
            offset += count
        }
    }

    static func errorResponse(_ error: Error) -> AgentResponse {
        if let error = error as? AgentTransportError {
            return AgentResponse(ok: false, status: error.status, message: error.localizedDescription)
        }
        if let error = error as? AgentProtocolError {
            return AgentResponse(ok: false, status: "invalid_request", message: error.localizedDescription)
        }
        return AgentResponse(
            ok: false, status: "connection_failed", message: "Mirror could not complete this local command.")
    }
}
