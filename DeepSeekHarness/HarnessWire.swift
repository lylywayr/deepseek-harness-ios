import Foundation

/// Pure Foundation wire helpers shared by the production transport and tests.
/// The methods deliberately mirror the Gateway's exact-key envelopes.
enum HarnessWire {
    enum WireError: LocalizedError, Equatable {
        case invalidResponse
        case correlation

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Harness 返回了无效响应。"
            case .correlation: return "Harness 响应关联失败。"
            }
        }
    }

    struct RPCResponse {
        let ok: Bool
        let value: Any?
        let code: String?
        let message: String?
    }

    struct MuxServerFrame {
        let type: String
        let streamID: String
        let value: Any?
        let code: String?
        let message: String?
    }

    static func rpcRequest(endpoint: String, args: [String: Any], rpcID: String) -> [String: Any] {
        [
            "type": "client-request",
            "rpcId": rpcID,
            "method": endpoint,
            "payload": ["args": args]
        ]
    }

    /// The Gateway keeps the session/list request wrapper even when it has no fields.
    static func sessionListArguments() -> [String: Any] {
        ["_request": [String: Any]()]
    }

    /// Official request-bearing Remotes put the request object under args.request.
    static func requestArguments(_ request: [String: Any]) -> [String: Any] {
        ["request": request]
    }

    static func sessionPageArguments(
        sessionID: String,
        throughSeq: Int,
        beforeSeq: Int? = nil,
        maxMessages: Int? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "address": ["kind": "session", "sessionId": sessionID],
            "throughSeq": throughSeq
        ]
        if let beforeSeq { request["beforeSeq"] = beforeSeq }
        if let maxMessages { request["maxMessages"] = maxMessages }
        return requestArguments(request)
    }

    static func sessionFollowPayload(sessionID: String, maxMessages: Int = 50) -> [String: Any] {
        let request: [String: Any] = [
            "address": ["kind": "session", "sessionId": sessionID],
            "maxMessages": maxMessages
        ]
        return ["args": requestArguments(request)]
    }

    static func directoryListArguments(path: String?) -> [String: Any] {
        guard let path else { return [:] }
        return ["path": path]
    }

    static func directoryCreateArguments(path: String, name: String) -> [String: Any] {
        ["path": path, "name": name]
    }

    static func rpcResponse(data: Data, expectedRPCID: String) throws -> RPCResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "server-response",
              let receivedID = object["rpcId"] as? String,
              receivedID == expectedRPCID,
              let result = object["result"] as? [String: Any],
              let ok = result["ok"] as? Bool else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let receivedID = object["rpcId"] as? String,
               receivedID != expectedRPCID {
                throw WireError.correlation
            }
            throw WireError.invalidResponse
        }
        if ok {
            return RPCResponse(ok: true, value: result["value"] ?? NSNull(), code: nil, message: nil)
        }
        guard let error = result["error"] as? [String: Any],
              let code = error["code"] as? String,
              let message = error["message"] as? String else {
            throw WireError.invalidResponse
        }
        return RPCResponse(ok: false, value: nil, code: code, message: message)
    }

    static func muxOpen(streamID: String, endpoint: String, payload: [String: Any]) -> [String: Any] {
        ["type": "open", "streamId": streamID, "endpoint": endpoint, "payload": payload]
    }

    static func muxCancel(streamID: String) -> [String: Any] {
        ["type": "cancel", "streamId": streamID]
    }

    static func muxServerFrame(data: Data) throws -> MuxServerFrame {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              let streamID = object["streamId"] as? String,
              !streamID.isEmpty else {
            throw WireError.invalidResponse
        }
        switch type {
        case "item":
            guard object.keys.allSatisfy({ ["type", "streamId", "value"].contains($0) }) else {
                throw WireError.invalidResponse
            }
            return MuxServerFrame(type: type, streamID: streamID, value: object["value"], code: nil, message: nil)
        case "end":
            guard object.keys.allSatisfy({ ["type", "streamId"].contains($0) }) else {
                throw WireError.invalidResponse
            }
            return MuxServerFrame(type: type, streamID: streamID, value: nil, code: nil, message: nil)
        case "error":
            guard let error = object["error"] as? [String: Any],
                  let code = error["code"] as? String,
                  let message = error["message"] as? String,
                  error["details"] is [String: Any] else {
                throw WireError.invalidResponse
            }
            return MuxServerFrame(type: type, streamID: streamID, value: nil, code: code, message: message)
        default:
            throw WireError.invalidResponse
        }
    }

    static func eventResult(clientID: String, eventID: String, outcome: [String: Any]) -> [String: Any] {
        ["clientId": clientID, "eventId": eventID, "outcome": outcome]
    }
}
