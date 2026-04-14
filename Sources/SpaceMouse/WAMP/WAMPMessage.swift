#if os(macOS)
import Foundation

/// WAMP v1 message type identifiers.
enum WAMPMessageType: Int, Sendable {
    case welcome = 0
    case prefix = 1
    case call = 2
    case callResult = 3
    case callError = 4
    case subscribe = 5
    case unsubscribe = 6
    case publish = 7
    case event = 8
}

/// A parsed WAMP v1 message.
enum WAMPMessage: Sendable {
    /// Server greeting: [WELCOME, sessionId, protocolVersion, serverIdent]
    case welcome(sessionID: String, protocolVersion: Int, serverIdent: String)

    /// RPC result: [CALL_RESULT, callID, result]
    case callResult(callID: String, result: AnySendable)

    /// RPC error: [CALL_ERROR, callID, errorURI, errorDesc, ...]
    case callError(callID: String, errorURI: String, description: String)

    /// Event published to a topic: [EVENT, topicURI, event]
    case event(topic: String, payload: AnySendable)
}

/// Wrapper for untyped JSON values crossing concurrency boundaries.
struct AnySendable: Sendable {
    let value: any Sendable

    init(_ value: any Sendable) {
        self.value = value
    }
}
#endif
