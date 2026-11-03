import Darwin
import Foundation
import MirrorCore
import XCTest

@testable import Mirror

final class AgentTransportTests: XCTestCase {
    private func socketURL() throws -> URL {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/agent-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let directory = base.appendingPathComponent(String(UUID().uuidString.prefix(8)), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("s")
    }

    @MainActor
    func testRoundTripMainActorPermissionsAndStop() async throws {
        let url = try socketURL()
        let request = AgentRequest(action: "status")
        var received: AgentRequest?
        let server = AgentCommandServer(socketURL: url) { value in
            XCTAssertTrue(Thread.isMainThread)
            received = value
            return AgentResponse(ok: true, status: "ready", revision: 7, agentEnabled: true)
        }
        try server.start()
        defer { server.stop() }
        let response = try await Task.detached {
            try AgentCommandClient.send(request: request, socketURL: url)
        }.value
        XCTAssertEqual(received, request)
        XCTAssertEqual(response.revision, 7)
        let parent = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        let socket = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((parent[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((socket[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testDoesNotUnlinkAnActiveService() async throws {
        let url = try socketURL()
        let first = AgentCommandServer(socketURL: url) { _ in AgentResponse(ok: true, status: "first") }
        let second = AgentCommandServer(socketURL: url) { _ in AgentResponse(ok: true, status: "second") }
        try first.start()
        defer {
            first.stop()
            second.stop()
        }
        XCTAssertThrowsError(try second.start()) { error in
            XCTAssertEqual((error as? AgentTransportError)?.status, "already_running")
        }
        let response = try await Task.detached {
            try AgentCommandClient.send(request: AgentRequest(action: "status"), socketURL: url)
        }.value
        XCTAssertEqual(response.status, "first")
    }

    @MainActor
    func testStaleSocketRecoveryAndUnsafeFilePreservation() async throws {
        let url = try socketURL()
        let fd = try Self.connectableSocket(url, bindOnly: true)
        Darwin.close(fd)
        let server = AgentCommandServer(socketURL: url) { _ in AgentResponse(ok: true, status: "ready") }
        try server.start()
        server.stop()
        let marker = Data("keep me".utf8)
        try marker.write(to: url)
        XCTAssertThrowsError(try server.start())
        XCTAssertEqual(try Data(contentsOf: url), marker)
    }

    @MainActor
    func testRejectsSocketAndDirectorySymlinks() throws {
        let url = try socketURL()
        let target = url.deletingLastPathComponent().appendingPathComponent("target")
        try Data("keep me".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let server = AgentCommandServer(socketURL: url) { _ in AgentResponse(ok: true, status: "ready") }
        XCTAssertThrowsError(try server.start())
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep me")
        let sibling = url.deletingLastPathComponent().appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(
            at: sibling, withDestinationURL: url.deletingLastPathComponent())
        let linkedServer = AgentCommandServer(socketURL: sibling.appendingPathComponent("socket")) { _ in
            AgentResponse(ok: true, status: "ready")
        }
        XCTAssertThrowsError(try linkedServer.start())
    }

    @MainActor
    func testMalformedAndOversizedRequestsDoNotReachHandler() async throws {
        let url = try socketURL()
        var calls = 0
        let server = AgentCommandServer(socketURL: url) { _ in
            calls += 1
            return AgentResponse(ok: true, status: "ready")
        }
        try server.start()
        defer { server.stop() }
        for (payload, expected) in [
            (Data("{not json}\n".utf8), "invalid_request"),
            (Data(repeating: 65, count: 65_537), "message_too_large"),
            (try JSONEncoder().encode(AgentRequest(action: "execute")) + Data([10]), "invalid_request"),
        ] {
            let response = try await Task.detached { try Self.rawCommand(payload, url: url) }.value
            XCTAssertFalse(response.ok)
            XCTAssertEqual(response.status, expected)
        }
        XCTAssertEqual(calls, 0)
        let response = try await Task.detached {
            try AgentCommandClient.send(request: AgentRequest(action: "status"), socketURL: url)
        }.value
        XCTAssertTrue(response.ok)
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testExpiredQueuedMutationNeverRuns() async throws {
        let url = try socketURL()
        var calls = 0
        let server = AgentCommandServer(socketURL: url) { _ in
            calls += 1
            return AgentResponse(ok: true, status: "applied")
        }
        try server.start()
        defer { server.stop() }
        let completed = DispatchSemaphore(value: 0)
        let client = Task.detached {
            defer { completed.signal() }
            return try? AgentCommandClient.send(
                request: AgentRequest(
                    action: "close", expectedRevision: 0,
                    windowID: UUID()), socketURL: url, timeout: 0.05)
        }
        // Deliberately keep main actor occupied until the caller's socket has closed.
        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        _ = await client.value
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testOversizedResponseReturnsBoundedError() async throws {
        let url = try socketURL()
        let server = AgentCommandServer(socketURL: url) { _ in
            AgentResponse(ok: true, status: "ready", message: String(repeating: "中", count: 30_000))
        }
        try server.start()
        defer { server.stop() }
        let response = try await Task.detached {
            try AgentCommandClient.send(request: AgentRequest(action: "status"), socketURL: url)
        }.value
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.status, "message_too_large")
    }

    func testProtocolValidationAndUnicodeRoundTrip() throws {
        let request = AgentRequest(action: "find", expectedRevision: 0, windowID: UUID(), query: "中文 🪞")
        XCTAssertNil(request.validationError)
        XCTAssertEqual(
            try JSONDecoder().decode(AgentRequest.self, from: JSONEncoder().encode(request)), request)
        for invalid in [
            AgentRequest(action: "shell"),
            AgentRequest(action: "open", conversationID: "../secret"),
            AgentRequest(action: "open", conversationID: "thread", messageID: "missing-turn"),
            AgentRequest(action: "open", windowID: UUID(), conversationID: "thread", newWindow: true),
            AgentRequest(action: "close"),
            AgentRequest(action: "status", query: "unrelated"),
            AgentRequest(action: "find", windowID: UUID(), query: "bad\u{0}"),
            AgentRequest(action: "find", windowID: UUID(), query: String(repeating: "中", count: 1366)),
            AgentRequest(action: "font", windowID: UUID(), fontSize: .nan),
            AgentRequest(action: "font", windowID: UUID(), fontSize: 27),
        ] { XCTAssertNotNil(invalid.validationError, invalid.action) }
        var frame = WindowFrame()
        frame.width = 279
        XCTAssertNotNil(AgentRequest(action: "frame", windowID: UUID(), frame: frame).validationError)
    }

    private static func connectableSocket(_ url: URL, bindOnly: Bool = false) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentTransportError.io }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(url.path.utf8) + [UInt8(0)]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw AgentTransportError.unsafePath
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bindOnly
                    ? Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    : Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw AgentTransportError.io
        }
        var enabled: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private static func rawCommand(_ payload: Data, url: URL) throws -> AgentResponse {
        let fd = try connectableSocket(url)
        defer { Darwin.close(fd) }
        var sent = 0
        while sent < payload.count {
            let count = payload.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: sent), payload.count - sent)
            }
            guard count > 0 else { throw AgentTransportError.io }
            sent += count
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.last != 10 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0, result.count + count <= 65_536 else { throw AgentTransportError.io }
            result.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode(AgentResponse.self, from: result)
    }
}
