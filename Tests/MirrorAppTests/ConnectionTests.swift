import Foundation
import MirrorCore
import XCTest

@testable import Mirror

final class ConnectionTests: XCTestCase {
    private func fixture(
        _ mode: String,
        configuration: CodexConnection.Configuration = .init(
            requestTimeout: 0.25, handshakeTimeout: 0.5, totalTimeout: 2, retryDelays: [0.01, 0.02]
        )
    ) -> (CodexConnection, LaunchCounter) {
        let counter = LaunchCounter()
        let connection = CodexConnection(
            configuration: configuration,
            command: {
                ("/usr/bin/python3", ["-u", "-c", Self.server, mode, String(counter.next())])
            })
        addTeardownBlock { await connection.disconnect() }
        return (connection, counter)
    }
    func testLargeFragmentedUTF8AndConcurrentRequestsUseOneService() async throws {
        let (connection, counter) = fixture("large")
        async let a = connection.request("thread/read", ["tag": .string("a")])
        async let b = connection.request("thread/read", ["tag": .string("b")])
        let results = try await [a, b]
        for (index, result) in results.enumerated() {
            let text = try XCTUnwrap(result["text"].string)
            XCTAssertGreaterThan(text.utf8.count, 5 * 1024 * 1024)
            XCTAssertTrue(text.hasPrefix("你好🪞abc"))
            XCTAssertTrue(text.hasSuffix("你好🪞abc"))
            XCTAssertEqual(result["tag"].string, index == 0 ? "a" : "b")
        }
        XCTAssertEqual(counter.count, 1)
        let pending = await connection.pendingCount
        XCTAssertEqual(pending, 0)
    }
    func testDisconnectAndTimeoutReconnectAutomatically() async throws {
        for mode in ["disconnect-first", "truncated-first", "timeout-first"] {
            let (connection, counter) = fixture(
                mode,
                configuration: .init(
                    requestTimeout: 0.06, handshakeTimeout: 0.5, totalTimeout: 2, retryDelays: [0.01, 0.02]))
            let result = try await connection.request("thread/read", ["tag": .string("recovered")])
            XCTAssertEqual(result["tag"].string, "recovered")
            XCTAssertEqual(counter.count, 2)
            await connection.disconnect()
        }
    }
    func testConcurrentFailuresShareOneReconnect() async throws {
        let (connection, counter) = fixture("disconnect-first")
        async let first = connection.request("thread/read", ["tag": .string("first")])
        async let second = connection.request("thread/list", ["tag": .string("second")])
        let results = try await [first, second]
        XCTAssertEqual(results.map { $0["tag"].string }, ["first", "second"])
        XCTAssertEqual(counter.count, 2)
    }
    func testRetryLimitAndOverallDeadline() async throws {
        let (connection, counter) = fixture("disconnect-always")
        do {
            _ = try await connection.request("thread/read", [:])
            XCTFail("expected three exhausted attempts")
        } catch { XCTAssertEqual(error as? ConnectionError, .disconnected) }
        XCTAssertEqual(counter.count, 3)
        let (slow, starts) = fixture(
            "timeout-always",
            configuration: .init(
                requestTimeout: 0.04, handshakeTimeout: 0.5, totalTimeout: 0.15, retryDelays: [0.01, 0.02]))
        let begin = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await slow.request("thread/read", [:])
            XCTFail("deadline")
        } catch { XCTAssertEqual(error as? ConnectionError, .timeout) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - begin, 0.5)
        XCTAssertLessThanOrEqual(starts.count, 3)
    }
    func testMalformedRejectedAndForbiddenDoNotRetry() async throws {
        for (mode, expected) in [
            ("invalid", ConnectionError.invalidResponse), ("rejected", .rejected(-32602)),
        ] {
            let (connection, counter) = fixture(mode)
            do {
                _ = try await connection.request("thread/read", [:])
                XCTFail(mode)
            } catch { XCTAssertEqual(error as? ConnectionError, expected) }
            XCTAssertEqual(counter.count, 1)
            await connection.disconnect()
        }
        let (connection, counter) = fixture("normal")
        do {
            _ = try await connection.request("thread/resume", [:])
            XCTFail("mutation")
        } catch { XCTAssertEqual(error as? ConnectionError, .forbidden) }
        XCTAssertEqual(counter.count, 0)
    }
    func testCancellationDoesNotInterruptOtherCallerAndLateReplyIsIgnored() async throws {
        let (connection, counter) = fixture("normal")
        let cancelled = Task { try await connection.request("thread/read", ["slow": .bool(true)]) }
        try await Task.sleep(nanoseconds: 40_000_000)
        let survivor = Task { try await connection.request("thread/list", ["tag": .string("survivor")]) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await survivor.value
        XCTAssertEqual(result["tag"].string, "survivor")
        XCTAssertEqual(counter.count, 1)
        let pending = await connection.pendingCount
        XCTAssertEqual(pending, 0)
    }
    func testCancelDuringHandshakeIsImmediateAndPreservesAnotherWaiter() async throws {
        let (connection, counter) = fixture(
            "slow-handshake",
            configuration: .init(
                requestTimeout: 1, handshakeTimeout: 2, totalTimeout: 4, retryDelays: [0.01, 0.02]))
        let first = Task { try await connection.request("thread/read", [:]) }
        let second = Task { try await connection.request("thread/list", ["tag": .string("second")]) }
        let registrationDeadline = ProcessInfo.processInfo.systemUptime + 2
        while await connection.pendingCount < 3, ProcessInfo.processInfo.systemUptime < registrationDeadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let begin = ProcessInfo.processInfo.systemUptime
        first.cancel()
        do {
            _ = try await first.value
            XCTFail("cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - begin, 0.1)
        let value = try await second.value
        XCTAssertEqual(value["tag"].string, "second")
        XCTAssertEqual(counter.count, 1)
    }
    func testFinalReplyBeforeEOFIsNotLost() async throws {
        let (connection, counter) = fixture("exit-after-reply")
        let value = try await connection.request("thread/read", ["tag": .string("final")])
        XCTAssertEqual(value["tag"].string, "final")
        XCTAssertEqual(counter.count, 1)
    }
    func testExplicitDisconnectStopsRetriesAndLogicalDeadlineCancelsWork() async throws {
        let (connection, counter) = fixture("timeout-always")
        let task = Task { try await connection.request("thread/read", [:]) }
        try await Task.sleep(nanoseconds: 40_000_000)
        await connection.disconnect()
        do {
            _ = try await task.value
            XCTFail("shutdown")
        } catch { XCTAssertTrue(error is CancellationError) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(counter.count, 1)
        let pending = await connection.pendingCount
        XCTAssertEqual(pending, 0)
        let begin = ProcessInfo.processInfo.systemUptime
        do {
            let _: JSONValue = try await withHistoryDeadline(begin + 0.03) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return .null
            }
            XCTFail("logical deadline")
        } catch { XCTAssertEqual(error as? ConnectionError, .timeout) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - begin, 0.15)
    }

    private static let server = #"""
        import json,sys,time,os
        mode=sys.argv[1]; launch=int(sys.argv[2])
        def emit(value,split=False):
            data=(json.dumps(value,ensure_ascii=False,separators=(',',':'))+'\n').encode()
            if split:
                for start in range(0,len(data),32771):
                    os.write(1,data[start:start+32771])
            else:
                sys.stdout.buffer.write(data);sys.stdout.buffer.flush()
        for line in sys.stdin:
            request=json.loads(line)
            if 'id' not in request:continue
            ident=request['id']; method=request['method'];params=request.get('params',{})
            if method=='initialize':
                if mode=='slow-handshake':time.sleep(.15)
                emit({'id':ident,'result':{}});continue
            if mode=='disconnect-always' or mode=='disconnect-first' and launch==1:sys.exit(0)
            if mode=='truncated-first' and launch==1:os.write(1,b'{"id":99,"result":{"text":"incomplete');sys.exit(0)
            if mode=='timeout-always' or mode=='timeout-first' and launch==1:continue
            if mode=='invalid':os.write(1,b'not-json\n');continue
            if mode=='rejected':emit({'id':ident,'error':{'code':-32602,'message':'fixture'}});continue
            if params.get('slow'):time.sleep(.1)
            value={'tag':params.get('tag')}
            if mode=='large':value['text']='你好🪞abc'*430000
            emit({'method':'fixture/notification','params':{}})
            emit({'id':ident,'result':value},mode=='large')
            if mode=='exit-after-reply':sys.exit(0)
        """#
}

private final class LaunchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
