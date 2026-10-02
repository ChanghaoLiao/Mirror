import MirrorCore
import XCTest

@testable import Mirror

final class AdapterTests: XCTestCase {
    @MainActor func testFullPaginationReadsEveryPageWithoutMutation() async throws {
        let transport = FixtureConnection(responses: [
            #"{"thread":{"id":"t","name":"Title","historyMode":"paginated"}}"#,
            #"{"data":[{"id":"one","itemsView":"full","items":[{"id":"u","type":"userMessage","content":[{"type":"text","text":"你好"}]}]}],"nextCursor":"next"}"#,
            #"{"data":[{"id":"two","itemsView":"full","items":[{"id":"a","type":"agentMessage","text":"Complete"}]}],"nextCursor":null}"#,
        ])
        let adapter = CodexAdapter(connection: transport)
        var counts: [Int] = []
        let result = try await adapter.getConversation(
            id: "t", progress: { counts.append($0.messages.count) })
        XCTAssertEqual(counts, [1, 2])
        XCTAssertEqual(result.messages.map(\.text), ["你好", "Complete"])
        let methods = await transport.methods
        XCTAssertEqual(methods, ["thread/read", "thread/turns/list", "thread/turns/list"])
        let params = await transport.params
        XCTAssertEqual(params.last?["cursor"], .string("next"))
        XCTAssertEqual(params.last?["itemsView"], .string("full"))
    }
    @MainActor func testRepeatedCursorAndMalformedHistoryFail() async throws {
        for pages in [
            [#"{"data":[],"nextCursor":"same"}"#, #"{"data":[],"nextCursor":"same"}"#],
            [#"{"data":{},"nextCursor":null}"#],
        ] {
            let transport = FixtureConnection(
                responses: [#"{"thread":{"id":"t","name":"Title","historyMode":"paginated"}}"#] + pages)
            do {
                _ = try await CodexAdapter(connection: transport).getConversation(id: "t")
                XCTFail("Incomplete data must not appear as a complete history")
            } catch {}
        }
    }
    @MainActor func testCancelledReadDoesNotStartPagination() async throws {
        let transport = FixtureConnection(responses: [
            #"{"thread":{"id":"t","name":"Title","historyMode":"paginated"}}"#
        ])
        let task = Task { try await CodexAdapter(connection: transport).getConversation(id: "t") }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled read")
        } catch is CancellationError {} catch { XCTFail("unexpected error") }
        let methods = await transport.methods
        XCTAssertLessThanOrEqual(methods.count, 1)
    }
}

private actor FixtureConnection: HistoryConnection {
    var responses: [String]
    var methods: [String] = []
    var params: [[String: JSONValue]] = []
    init(responses: [String]) { self.responses = responses }
    func request(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        methods.append(method)
        self.params.append(params)
        guard !responses.isEmpty else { throw ConnectionError.disconnected }
        return try JSONDecoder().decode(JSONValue.self, from: Data(responses.removeFirst().utf8))
    }
    func disconnect() {}
}
