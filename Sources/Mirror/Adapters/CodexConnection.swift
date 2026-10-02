import Foundation
import MirrorCore

enum ConnectionError: Error, LocalizedError, Equatable {
    case missingCLI, disconnected, timeout, invalidResponse
    case rejected(Int)
    case forbidden
    var retryable: Bool { self == .disconnected || self == .timeout }
    var errorDescription: String? {
        switch self {
        case .missingCLI:
            return localized(
                "Codex was not found. Choose its executable in Setup & Permissions.",
                "未找到 Codex，请在设置与权限中选择它的程序。")
        case .disconnected:
            return localized(
                "Could not reconnect to Codex history. Your previous content is preserved.",
                "暂时无法重新连接 Codex，已有内容已保留。")
        case .timeout:
            return localized(
                "Codex history took too long to respond. Your previous content is preserved.",
                "Codex 读取超时，已有内容已保留。")
        case .invalidResponse:
            return localized(
                "Codex returned an invalid history response. Check CLI compatibility.",
                "Codex 返回的数据格式异常，请检查程序版本兼容性。")
        case .rejected(let code):
            return localized(
                "Codex rejected the history request (code \(code)).", "Codex 拒绝了读取请求（代码 \(code)）。")
        case .forbidden: return localized("Mirror blocked a non-reading operation.", "Mirror 已阻止非只读操作。")
        }
    }
}

protocol HistoryConnection: Sendable {
    func request(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue
    func disconnect() async
}

/// The deadline spans the entire logical read, including all pages and transport retries.
func withHistoryDeadline<T: Sendable>(
    _ deadline: TimeInterval, operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            throw ConnectionError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

/// No task is spawned for each pipe chunk. Yield under the same lock as the read;
/// a single consumer drains bytes and EOF in order, including the final response.
private final class OrderedHistoryOutput: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let handle: FileHandle
    private let lock = NSLock()
    private var stopped = false
    init(_ handle: FileHandle) {
        self.handle = handle
        var sink: AsyncStream<Data>.Continuation!
        stream = AsyncStream { sink = $0 }
        continuation = sink
        handle.readabilityHandler = { [weak self] handle in self?.read(handle) }
    }
    private func read(_ handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        let data = handle.availableData
        if data.isEmpty {
            stopped = true
            continuation.finish()
            handle.readabilityHandler = nil
        } else {
            continuation.yield(data)
        }
    }
    func stop() {
        handle.readabilityHandler = nil
        lock.lock()
        stopped = true
        continuation.finish()
        lock.unlock()
        try? handle.close()
    }
}

actor CodexConnection: HistoryConnection {
    struct Configuration: Sendable {
        var requestTimeout: TimeInterval = 15
        var handshakeTimeout: TimeInterval = 8
        var totalTimeout: TimeInterval = 45
        var retryDelays: [TimeInterval] = [0.25, 0.75]
    }
    private struct SessionFailure: Error {
        let error: ConnectionError
        let epoch: UUID
    }
    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timer: Task<Void, Never>
    }
    private struct StartupWaiter {
        let continuation: CheckedContinuation<UUID, Error>
        let timer: Task<Void, Never>
    }
    private let configuration: Configuration
    private let command: @Sendable () throws -> (String, [String])
    private var process: Process?
    private var input: FileHandle?
    private var output: OrderedHistoryOutput?
    private var receiver: Task<Void, Never>?
    private var buffer = Data()
    private var scanned = 0
    private var sequence = 0
    private var pending: [Int: Pending] = [:]
    private var startup: Task<Void, Never>?
    private var startupWaiters: [UUID: StartupWaiter] = [:]
    private var ready = false
    private var shutdown = false
    private var generation = UUID()

    init(
        configuration: Configuration = Configuration(),
        command: @escaping @Sendable () throws -> (String, [String]) = {
            guard let path = CodexInstallation.executablePath else { throw ConnectionError.missingCLI }
            return (path, ["app-server", "--stdio", "-c", "analytics.enabled=false"])
        }
    ) {
        self.configuration = configuration
        self.command = command
    }
    var pendingCount: Int { pending.count + startupWaiters.count }

    func request(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard !shutdown else { throw CancellationError() }
        guard ReadOnlyRPC.methods.contains(method) else { throw ConnectionError.forbidden }
        let deadline = ProcessInfo.processInfo.systemUptime + configuration.totalTimeout
        for attempt in 0...configuration.retryDelays.count {
            try Task.checkCancellation()
            guard !shutdown else { throw CancellationError() }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ConnectionError.timeout }
            do {
                let epoch = try await ensureReady(deadline: deadline)
                return try await send(
                    method, params, epoch: epoch,
                    deadline: min(
                        deadline, ProcessInfo.processInfo.systemUptime + configuration.requestTimeout))
            } catch let failure as SessionFailure {
                try Task.checkCancellation()
                guard !shutdown else { throw CancellationError() }
                guard failure.error.retryable, attempt < configuration.retryDelays.count else {
                    throw failure.error
                }
                invalidate(failure.error, epoch: failure.epoch)
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                let delay = configuration.retryDelays[attempt]
                guard remaining > delay else { throw ConnectionError.timeout }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw ConnectionError.disconnected
    }

    private func ensureReady(deadline: TimeInterval) async throws -> UUID {
        try Task.checkCancellation()
        if ready { return generation }
        if startup == nil {
            generation = UUID()
            let epoch = generation
            startup = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.start(epoch: epoch)
                    await self.finishStartup(epoch: epoch)
                } catch {
                    let kind =
                        (error as? SessionFailure)?.error ?? (error as? ConnectionError) ?? .disconnected
                    await self.invalidate(kind, epoch: epoch)
                }
            }
        }
        let waiter = UUID()
        let epoch = generation
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(
                                max(0, deadline - ProcessInfo.processInfo.systemUptime) * 1_000_000_000))
                    } catch { return }
                    await self?.expireStartup(waiter, epoch: epoch)
                }
                startupWaiters[waiter] = StartupWaiter(continuation: continuation, timer: timer)
            }
        } onCancel: {
            Task { await self.cancelStartup(waiter) }
        }
    }
    private func start(epoch: UUID) async throws {
        let (path, arguments) = try command()
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = arguments
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        try child.run()
        process = child
        input = stdin.fileHandleForWriting
        let reader = OrderedHistoryOutput(stdout.fileHandleForReading)
        output = reader
        receiver = Task { [weak self, stream = reader.stream] in
            for await bytes in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(bytes, epoch: epoch)
            }
            guard !Task.isCancelled else { return }
            await self?.endOfOutput(epoch: epoch)
        }
        // EOF is processed by the consumer after queued bytes, not by a racing termination handler.
        _ = try await send(
            "initialize",
            [
                "clientInfo": .object(["name": .string("mirror"), "version": .string("0.2.1")]),
                "capabilities": .object(["experimentalApi": .bool(true)]),
            ], epoch: epoch, deadline: ProcessInfo.processInfo.systemUptime + configuration.handshakeTimeout)
        try Task.checkCancellation()
        guard generation == epoch else { throw SessionFailure(error: .disconnected, epoch: epoch) }
        do { try write(.object(["method": .string("initialized")])) } catch {
            throw SessionFailure(error: .disconnected, epoch: epoch)
        }
    }
    private func finishStartup(epoch: UUID) {
        guard epoch == generation else { return }
        ready = true
        startup = nil
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters.values {
            waiter.timer.cancel()
            waiter.continuation.resume(returning: epoch)
        }
    }
    private func cancelStartup(_ id: UUID) {
        guard let waiter = startupWaiters.removeValue(forKey: id) else { return }
        waiter.timer.cancel()
        waiter.continuation.resume(throwing: CancellationError())
        if startupWaiters.isEmpty && !ready { invalidate(.disconnected, epoch: generation) }
    }
    private func expireStartup(_ id: UUID, epoch: UUID) {
        guard epoch == generation, let waiter = startupWaiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: SessionFailure(error: .timeout, epoch: epoch))
        if startupWaiters.isEmpty && !ready { invalidate(.timeout, epoch: epoch) }
    }

    private func send(_ method: String, _ params: [String: JSONValue], epoch: UUID, deadline: TimeInterval)
        async throws -> JSONValue
    {
        try Task.checkCancellation()
        guard generation == epoch else { throw SessionFailure(error: .disconnected, epoch: epoch) }
        sequence += 1
        let id = sequence
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(
                                max(0, deadline - ProcessInfo.processInfo.systemUptime) * 1_000_000_000))
                    } catch { return }
                    await self?.expire(id, epoch: epoch)
                }
                pending[id] = Pending(continuation: continuation, timer: timer)
                do {
                    try write(
                        .object([
                            "id": .number(Double(id)), "method": .string(method), "params": .object(params),
                        ]))
                } catch { invalidate(.disconnected, epoch: epoch) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timer.cancel()
        request.continuation.resume(throwing: CancellationError())
    }
    private func expire(_ id: Int, epoch: UUID) {
        guard epoch == generation, pending[id] != nil else { return }
        invalidate(.timeout, epoch: epoch)
    }
    private func write(_ value: JSONValue) throws {
        guard let input else { throw ConnectionError.disconnected }
        var data = try JSONEncoder().encode(value)
        data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ data: Data, epoch: UUID) {
        guard epoch == generation else { return }
        buffer.append(data)
        // Search only the newly appended region when an individual JSON line spans many chunks.
        while let newline = buffer[buffer.index(buffer.startIndex, offsetBy: scanned)...].firstIndex(of: 10) {
            let line = buffer[..<newline]
            let value: JSONValue
            do { value = try JSONDecoder().decode(JSONValue.self, from: line) } catch {
                invalidate(.invalidResponse, epoch: epoch)
                return
            }
            buffer.removeSubrange(...newline)
            scanned = 0
            guard case .object = value else {
                invalidate(.invalidResponse, epoch: epoch)
                return
            }
            guard let number = value["id"].number else { continue }
            guard number.isFinite, number.rounded() == number, number > 0, number < Double(Int.max) else {
                invalidate(.invalidResponse, epoch: epoch)
                return
            }
            guard let request = pending.removeValue(forKey: Int(number)) else { continue }
            request.timer.cancel()
            if value["error"] != .null {
                if let code = value["error"]["code"].number,
                    code.isFinite, code.rounded() == code,
                    code >= Double(Int.min), code < Double(Int.max)
                {
                    request.continuation.resume(throwing: ConnectionError.rejected(Int(code)))
                } else {
                    request.continuation.resume(throwing: ConnectionError.invalidResponse)
                    invalidate(.invalidResponse, epoch: epoch)
                    return
                }
            } else if case .object(let object) = value, let result = object["result"] {
                request.continuation.resume(returning: result)
            } else {
                request.continuation.resume(throwing: ConnectionError.invalidResponse)
                invalidate(.invalidResponse, epoch: epoch)
                return
            }
        }
        scanned = buffer.count
    }
    private func endOfOutput(epoch: UUID) {
        guard epoch == generation else { return }
        // An interrupted line is a broken transport, not a malformed complete response.
        invalidate(.disconnected, epoch: epoch)
    }
    private func invalidate(_ error: ConnectionError, epoch: UUID) {
        guard epoch == generation else { return }
        generation = UUID()
        ready = false
        startup?.cancel()
        startup = nil
        receiver?.cancel()
        receiver = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? input?.close()
        input = nil
        output?.stop()
        output = nil
        buffer.removeAll(keepingCapacity: false)
        scanned = 0
        let abandoned = pending
        pending.removeAll()
        for request in abandoned.values {
            request.timer.cancel()
            request.continuation.resume(throwing: SessionFailure(error: error, epoch: epoch))
        }
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters.values {
            waiter.timer.cancel()
            waiter.continuation.resume(throwing: SessionFailure(error: error, epoch: epoch))
        }
    }
    func disconnect() {
        shutdown = true
        invalidate(.disconnected, epoch: generation)
    }
}

enum CodexInstallation {
    static var executablePath: String? {
        let candidates = [
            ProcessInfo.processInfo.environment["MIRROR_CODEX_PATH"],
            UserDefaults.standard.string(forKey: "codexExecutable"),
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
