import Foundation
import Synchronization

/// A WAMP v1 session over a WebSocket connection.
///
/// All I/O is async. No semaphores, no dispatch, no threads.
///
/// > Note: Uses URLSessionWebSocketTask because NWProtocolWebSocket has a bug
/// > with self-signed TLS certificates (see BugReport/).
final class WAMPSession: Sendable {
    let sessionID: String?

    let onCall: @Sendable (_ callID: String, _ procedure: String, _ args: [Any]) throws -> Any?

    private let wsTask: URLSessionWebSocketTask
    private let urlSession: URLSession
    private let callCounter = Mutex<Int>(0)
    private let pendingCalls = Mutex<[String: CheckedContinuation<AnySendable, any Error>]>([:])

    // MARK: - Init

    init(
        host: String,
        port: UInt16,
        onCall: @escaping @Sendable (_ callID: String, _ procedure: String, _ args: [Any]) throws -> Any?
    ) async throws {
        guard let url = URL(string: "wss://\(host):\(port)") else {
            throw WAMPError.connectionFailed("Invalid URL")
        }

        self.onCall = onCall
        let delegate = _TLSDelegate()
        self.urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.wsTask = urlSession.webSocketTask(with: url, protocols: ["wamp"])
        self.sessionID = nil

        wsTask.resume()

        let welcome = try await receiveJSON()
        guard let arr = welcome as? [Any],
              arr.count >= 2,
              let typeID = arr[0] as? Int,
              typeID == WAMPMessageType.welcome.rawValue else {
            throw WAMPError.handshakeFailed("Expected WELCOME message")
        }
    }

    // MARK: - Prefixes

    func prefix(_ prefix: String, uri: String) async throws {
        try await sendJSON([WAMPMessageType.prefix.rawValue, prefix, uri])
    }

    // MARK: - RPC

    @discardableResult
    func call(_ procedure: String, args: Any...) async throws -> Any {
        try await call(procedure, args: args)
    }

    @discardableResult
    func call(_ procedure: String, args: [Any]) async throws -> Any {
        let id = callCounter.withLock { counter -> String in
            counter += 1
            return "call-\(counter)"
        }
        var msg: [Any] = [WAMPMessageType.call.rawValue, id, procedure]
        msg.append(contentsOf: args)

        let jsonString = try encodeJSON(msg)

        let box: AnySendable = try await withCheckedThrowingContinuation { continuation in
            pendingCalls.withLock { $0[id] = continuation }
            Task { [wsTask] in
                try await wsTask.send(.string(jsonString))
            }
        }
        return box.value
    }

    // MARK: - Subscriptions

    func subscribe(_ topic: String) async throws {
        try await sendJSON([WAMPMessageType.subscribe.rawValue, topic])
    }

    // MARK: - Reader Loop

    func readerLoop() async {
        do {
            while true {
                let parsed = try await receiveJSON()
                await handleMessage(parsed)
            }
        } catch {
            // Connection closed
        }
    }

    private func handleMessage(_ parsed: Any) async {
        guard let arr = parsed as? [Any], let typeRaw = arr.first as? Int else {
            return
        }

        switch typeRaw {
        case WAMPMessageType.callResult.rawValue:
            guard arr.count >= 3, let callID = arr[1] as? String else {
                return
            }
            let continuation = pendingCalls.withLock { $0.removeValue(forKey: callID) }
            // swiftlint:disable:next force_cast
            continuation?.resume(returning: AnySendable(arr[2] as! any Sendable))

        case WAMPMessageType.callError.rawValue:
            guard arr.count >= 4, let callID = arr[1] as? String else {
                return
            }
            let desc = arr.count > 3 ? "\(arr[3])" : "RPC error"
            let continuation = pendingCalls.withLock { $0.removeValue(forKey: callID) }
            continuation?.resume(throwing: WAMPError.callFailed(desc))

        case WAMPMessageType.event.rawValue:
            guard arr.count >= 3 else {
                return
            }
            if let callArr = arr[2] as? [Any],
               callArr.count >= 3,
               let callType = callArr[0] as? Int,
               callType == WAMPMessageType.call.rawValue,
               let callID = callArr[1] as? String,
               let procedure = callArr[2] as? String {
                let args = Array(callArr.dropFirst(3))
                await handleServerCall(callID: callID, procedure: procedure, args: args)
            }

        default:
            break
        }
    }

    private func handleServerCall(callID: String, procedure: String, args: [Any]) async {
        do {
            let result = try onCall(callID, procedure, args)
            try await sendJSON([WAMPMessageType.callResult.rawValue, callID, result ?? NSNull()])
        } catch {
            try? await sendJSON([WAMPMessageType.callError.rawValue, callID, procedure + "#generic", "\(error)"])
        }
    }

    // MARK: - Transport

    private func encodeJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WAMPError.encodingFailed
        }
        return string
    }

    private func sendJSON(_ value: Any) async throws {
        let string = try encodeJSON(value)
        try await wsTask.send(.string(string))
    }

    private func receiveJSON() async throws -> Any {
        let message = try await wsTask.receive()
        switch message {
        case .string(let text):
            return try JSONSerialization.jsonObject(with: Data(text.utf8))
        case .data(let data):
            return try JSONSerialization.jsonObject(with: data)
        @unknown default:
            throw WAMPError.connectionFailed("Unknown message type")
        }
    }
}

// MARK: - Errors

enum WAMPError: Error {
    case connectionFailed(String)
    case handshakeFailed(String)
    case callFailed(String)
    case encodingFailed
}

// MARK: - TLS Delegate

private final class _TLSDelegate: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
