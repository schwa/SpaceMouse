import Foundation

/// Errors that can occur during SpaceMouse connection and communication.
public enum SpaceMouseError: Error {
    /// Could not discover the WebSocket port from the 3DxNLServer.
    case discoveryFailed(String)
    /// WebSocket connection failed.
    case connectionFailed(String)
    /// Did not receive a WAMP WELCOME message.
    case noWelcome
    /// An RPC call to the server failed.
    case rpcError(String)
    /// An RPC call timed out.
    case rpcTimeout
    /// Failed to create 3dmouse or 3dcontroller.
    case createFailed(String)
    /// Unexpected message format.
    case protocolError(String)
}
