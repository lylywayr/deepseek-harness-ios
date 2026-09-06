import Foundation

/// These tests exercise the same builders/parsers used by `HarnessRuntime`.
#if canImport(XCTest)
import XCTest

final class HarnessWireTests: XCTestCase {
    func testSessionListUsesReservedRequestWrapper() throws {
        let request = HarnessWire.rpcRequest(
            endpoint: "session/list",
            args: HarnessWire.sessionListArguments(),
            rpcID: "list-1"
        )
        let payload = try XCTUnwrap(request["payload"] as? [String: Any])
        let args = try XCTUnwrap(payload["args"] as? [String: Any])
        XCTAssertEqual(args.count, 1)
        XCTAssertTrue(args["_request"] is [String: Any])
    }

    func testRequestRemoteUsesOfficialRequestWrapper() throws {
        let args = HarnessWire.requestArguments(["sessionId": "session-1"])
        XCTAssertEqual(args.count, 1)
        let request = try XCTUnwrap(args["request"] as? [String: Any])
        XCTAssertEqual(request["sessionId"] as? String, "session-1")
    }

    func testRequestArgumentsForSessionCreationAndPermissionStayOfficial() throws {
        let create = HarnessWire.sessionCreateArguments(workspaceID: "workspace-1")
        let createRequest = try XCTUnwrap(create["request"] as? [String: Any])
        XCTAssertEqual(createRequest["workspaceId"] as? String, "workspace-1")
        let permission = HarnessWire.permissionCommandArguments(sessionID: "session-1", value: "workspace-write")
        XCTAssertEqual(permission["agentId"] as? String, "session-1")
        XCTAssertEqual(permission["line"] as? String, "/permission workspace-write")
        XCTAssertTrue(permission["images"] is [Any])
    }

    func testPageKeepsOfficialAddressAndCursorFields() throws {
        let args = HarnessWire.sessionPageArguments(
            sessionID: "session-1",
            throughSeq: 42,
            beforeSeq: 17,
            maxMessages: 30
        )
        let page = try XCTUnwrap(args["request"] as? [String: Any])
        let address = try XCTUnwrap(page["address"] as? [String: Any])
        XCTAssertEqual(address["kind"] as? String, "session")
        XCTAssertEqual(address["sessionId"] as? String, "session-1")
        XCTAssertEqual((page["throughSeq"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual((page["beforeSeq"] as? NSNumber)?.intValue, 17)
        XCTAssertEqual((page["maxMessages"] as? NSNumber)?.intValue, 30)
    }

    func testFollowPayloadKeepsArgsRequestShape() throws {
        let payload = HarnessWire.sessionFollowPayload(sessionID: "session-1")
        let args = try XCTUnwrap(payload["args"] as? [String: Any])
        let request = try XCTUnwrap(args["request"] as? [String: Any])
        let address = try XCTUnwrap(request["address"] as? [String: Any])
        XCTAssertEqual(address["kind"] as? String, "session")
        XCTAssertEqual(address["sessionId"] as? String, "session-1")
        XCTAssertEqual((request["maxMessages"] as? NSNumber)?.intValue, 50)
    }

    func testDirectoryArgumentsStayTopLevel() throws {
        XCTAssertEqual(HarnessWire.directoryListArguments(path: nil).count, 0)
        XCTAssertEqual(HarnessWire.directoryListArguments(path: "/home/tester")["path"] as? String, "/home/tester")
        let create = HarnessWire.directoryCreateArguments(path: "/home/tester", name: "project")
        XCTAssertEqual(create["path"] as? String, "/home/tester")
        XCTAssertEqual(create["name"] as? String, "project")
    }

    func testRPCParserCorrelatesProductionResponse() throws {
        let object: [String: Any] = [
            "type": "server-response", "rpcId": "rpc-1",
            "result": ["ok": true, "value": ["items": []]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let parsed = try HarnessWire.rpcResponse(data: data, expectedRPCID: "rpc-1")
        XCTAssertTrue(parsed.ok)
        XCTAssertNotNil(parsed.value)
    }

    func testRPCParserPreservesStructuredRemoteError() throws {
        let object: [String: Any] = [
            "type": "server-response", "rpcId": "rpc-2",
            "result": ["ok": false, "error": ["code": "gateway/arguments-invalid", "message": "missing _request"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let parsed = try HarnessWire.rpcResponse(data: data, expectedRPCID: "rpc-2")
        XCTAssertFalse(parsed.ok)
        XCTAssertEqual(parsed.code, "gateway/arguments-invalid")
        XCTAssertEqual(parsed.message, "missing _request")
    }

    func testRPCParserRejectsWrongCorrelation() throws {
        let object: [String: Any] = [
            "type": "server-response", "rpcId": "other",
            "result": ["ok": true, "value": [:]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try HarnessWire.rpcResponse(data: data, expectedRPCID: "expected")) { error in
            XCTAssertEqual(error as? HarnessWire.WireError, .correlation)
        }
    }

    func testRPCParserRejectsUnstructuredFailure() throws {
        let object: [String: Any] = [
            "type": "server-response", "rpcId": "rpc-3",
            "result": ["ok": false, "error": ["code": "gateway/internal"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try HarnessWire.rpcResponse(data: data, expectedRPCID: "rpc-3")) { error in
            XCTAssertEqual(error as? HarnessWire.WireError, .invalidResponse)
        }
    }

    func testMuxParserAcceptsItemEndError() throws {
        let item = try HarnessWire.muxServerFrame(data: json(["type": "item", "streamId": "s-1", "value": ["type": "snapshot"]]))
        XCTAssertEqual(item.type, "item")
        let end = try HarnessWire.muxServerFrame(data: json(["type": "end", "streamId": "s-1"]))
        XCTAssertEqual(end.type, "end")
        let error = try HarnessWire.muxServerFrame(data: json([
            "type": "error",
            "streamId": "s-1",
            "error": ["code": "gateway/internal", "message": "failed", "details": [String: Any]()]
        ]))
        XCTAssertEqual(error.code, "gateway/internal")
        XCTAssertThrowsError(try HarnessWire.muxServerFrame(data: json(["type": "item", "streamId": ""])))
    }

    func testMuxOpenCancelAndEventResultShapes() throws {
        let open = HarnessWire.muxOpen(
            streamID: "s-1",
            endpoint: "session/follow",
            payload: HarnessWire.sessionFollowPayload(sessionID: "session-1")
        )
        XCTAssertEqual(open["type"] as? String, "open")
        XCTAssertEqual(open["streamId"] as? String, "s-1")
        XCTAssertEqual(open["endpoint"] as? String, "session/follow")
        XCTAssertEqual(HarnessWire.muxCancel(streamID: "s-1")["type"] as? String, "cancel")
        let result = HarnessWire.eventResult(clientID: "client-1", eventID: "event-1", outcome: ["kind": "result", "value": "allowed-once"])
        XCTAssertEqual(result["clientId"] as? String, "client-1")
        XCTAssertEqual(result["eventId"] as? String, "event-1")
        XCTAssertEqual((result["outcome"] as? [String: String])?["value"], "allowed-once")
    }

    func testEndpointCanonicalizerRemovesEmptyQueryAndFragments() throws {
        let cases = [
            ("http://host:43127", "http://host:43127"),
            ("http://host:43127?", "http://host:43127"),
            ("http://host:43127/?", "http://host:43127/"),
            ("http://host:43127#fragment", "http://host:43127"),
            ("http://host:43127?foo=bar", "http://host:43127?foo=bar")
        ]
        for (input, expected) in cases {
            let parsed = try XCTUnwrap(HarnessEndpointCanonicalizer.canonicalize(input))
            XCTAssertEqual(parsed.url.absoluteString, expected, input)
            XCTAssertNil(HarnessEndpointCanonicalizer.canonicalize(parsed.url)?.token)
        }
    }

    func testEndpointCanonicalizerExtractsTokenAndPreservesOtherQueries() throws {
        let parsed = try XCTUnwrap(HarnessEndpointCanonicalizer.canonicalize("https://host:49215/?foo=bar&token=secret"))
        XCTAssertEqual(parsed.url.absoluteString, "https://host:49215/?foo=bar")
        XCTAssertEqual(parsed.token, "secret")
        let empty = try XCTUnwrap(HarnessEndpointCanonicalizer.canonicalize("https://host:49215/?token="))
        XCTAssertEqual(empty.url.absoluteString, "https://host:49215/")
        XCTAssertNil(empty.token)
    }

    func testEndpointCanonicalizerIsIdempotent() throws {
        let once = try XCTUnwrap(HarnessEndpointCanonicalizer.canonicalize(" HTTP://host:43127?foo=bar&token=x "))
        let twice = try XCTUnwrap(HarnessEndpointCanonicalizer.canonicalize(once.url))
        XCTAssertEqual(once.url, twice.url)
        XCTAssertNil(twice.token)
    }

    @MainActor
    func testAppStateMigratesLegacyEndpointAndWritesCanonicalValue() throws {
        let suite = "HarnessEndpointTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let legacy = "https://host:49215/?foo=bar&token=secret"
        let canonical = try XCTUnwrap(URL(string: "https://host:49215/?foo=bar"))
        defaults.set(legacy, forKey: "harness.endpoint")
        defer {
            HarnessCredentialStore(baseURL: canonical).remove()
            defaults.removePersistentDomain(forName: suite)
        }
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.endpointString, canonical.absoluteString)
        XCTAssertEqual(state.endpointURL, canonical)
        XCTAssertEqual(defaults.string(forKey: "harness.endpoint"), canonical.absoluteString)
        XCTAssertFalse(state.endpointString.hasSuffix("?"))
    }

    @MainActor
    func testClientRuntimeAndTransportURLsShareCanonicalBase() throws {
        let input = try XCTUnwrap(URL(string: "http://host:43127?foo=bar&token=secret"))
        let client = HarnessClient(baseURL: input)
        defer { HarnessCredentialStore(baseURL: client.baseURL).remove() }
        let expected = try XCTUnwrap(URL(string: "http://host:43127?foo=bar"))
        XCTAssertEqual(client.baseURL, expected)

        let bootstrap = try XCTUnwrap(client.bootstrapURL())
        XCTAssertEqual(bootstrap.absoluteString, "http://host:43127?foo=bar&token=secret")
        let api = try XCTUnwrap(client.apiURL("session/list"))
        XCTAssertEqual(api.absoluteString, "http://host:43127/api/session/list?foo=bar")
        XCTAssertFalse(api.absoluteString.hasSuffix("?"))
        let webSocket = try XCTUnwrap(client.webSocketRequest()?.url)
        XCTAssertEqual(webSocket.absoluteString, "ws://host:43127/api/remote.mux?foo=bar")
        XCTAssertFalse(webSocket.absoluteString.hasSuffix("?"))

        let runtime = HarnessRuntime(baseURL: input)
        XCTAssertEqual(runtime.baseURL, client.baseURL)
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
#endif
