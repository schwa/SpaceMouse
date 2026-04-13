# NWProtocolWebSocket sends TLS Alert immediately after successful handshake with self-signed cert server

## Summary

`NWProtocolWebSocket` (both legacy `NWConnection` and new `NetworkConnection<WebSocket>`) fails to connect to a WebSocket server that uses a self-signed TLS certificate. The TLS handshake completes successfully, but the client immediately sends an Encrypted Alert and closes the connection — before the WebSocket upgrade occurs and before the `certificateValidator` callback is invoked.

`URLSessionWebSocketTask` connects to the same server without issue.

## Environment

- macOS 26.0 beta (Xcode 26.4)
- Network.framework (both new `NetworkConnection<WebSocket>` and legacy `NWConnection` + `NWProtocolWebSocket`)
- Server: 3Dconnexion 3DxNLServer v1.5.0.21901 (boost.beast WebSocket, self-signed TLS, TLSv1.2, RSA 2048)
- Server address: `127.51.68.120:8182` (loopback)

## Steps to Reproduce

### 1. NWConnection WebSocket (FAILS)

```swift
import Network

let conn = NetworkConnection(to: .hostPort(host: "127.51.68.120", port: 8182)) {
    WebSocket {
        TLS()
            .certificateValidator { _, _ in true }
    }
    .subprotocols(["wamp"])
}
conn.onStateUpdate { _, state in print("state: \(state)") }
let msg = try await conn.receive()
// Error: POSIXErrorCode(rawValue: 53): Software caused connection abort
// certificateValidator is NEVER called
```

### 2. Legacy NWConnection (ALSO FAILS)

```swift
import Network

let tlsOpts = NWProtocolTLS.Options()
sec_protocol_options_set_verify_block(
    tlsOpts.securityProtocolOptions,
    { _, _, cb in cb(true) },
    .global()
)
let wsOpts = NWProtocolWebSocket.Options()
wsOpts.setSubprotocols(["wamp"])
let params = NWParameters(tls: tlsOpts)
params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)
let conn = NWConnection(to: .hostPort(host: "127.51.68.120", port: 8182), using: params)
// Same error: ECONNABORTED
```

### 3. URLSessionWebSocketTask (WORKS)

```swift
import Foundation

class D: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: t))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
let d = D()
let s = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
let task = s.webSocketTask(with: URL(string: "wss://127.51.68.120:8182")!, protocols: ["wamp"])
task.resume()
// Works: receives WAMP WELCOME message
```

### 4. Raw TLS + manual WebSocket upgrade (WORKS)

```swift
import Foundation
import Network

let conn = NetworkConnection(to: .hostPort(host: "127.51.68.120", port: 8182)) {
    TLS()
        .certificateValidator { _, _ in true }
}
let upgrade = "GET / HTTP/1.1\r\nHost: 127.51.68.120:8182\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: wamp\r\n\r\n"
try await conn.send(Data(upgrade.utf8), endOfStream: false)
let resp = try await conn.receive(atLeast: 1, atMost: 8192)
// Works: receives HTTP 101 Switching Protocols + WAMP WELCOME
```

### 5. External WebSocket server (WORKS with NWConnection)

```swift
let conn = NetworkConnection(to: .hostPort(host: "echo.websocket.org", port: 443)) {
    WebSocket { TLS() }
}
try await conn.send("hello")
let msg = try await conn.receive()
// Works fine
```

## Packet Captures

Two captures are included:

- **`ws_urlsession.pcapng`** — URLSession WebSocket (successful)
  - TCP handshake → TLS handshake → Application Data (WebSocket upgrade) → Application Data (101 + WELCOME)

- **`ws_nwconn.pcapng`** — NWConnection WebSocket (failure)
  - TCP handshake → TLS handshake → **Encrypted Alert (client)** → Encrypted Alert (server) → FIN → RST

Both TLS handshakes complete. The NWConnection client sends a TLS Alert immediately after the handshake, before any WebSocket upgrade request is sent.

## Key Observations

1. The TLS handshake succeeds in both cases (Server Hello, Certificate, Key Exchange, Change Cipher Spec all complete).
2. NWProtocolWebSocket sends a TLS Alert **after** the handshake but **before** calling `certificateValidator`. The validator callback is never invoked.
3. Raw `TLS()` without WebSocket works fine — `certificateValidator` is called and the connection proceeds normally.
4. URLSessionWebSocketTask works with the same server and same self-signed cert.
5. NWProtocolWebSocket works with public servers (e.g., echo.websocket.org).
6. The issue reproduces with both the new `NetworkConnection<WebSocket>` API and the legacy `NWConnection` + `NWProtocolWebSocket.Options` API.

## Expected Behavior

`certificateValidator` should be called before the WebSocket layer rejects the connection, allowing the app to accept self-signed certificates.

## Server Details

The server is 3Dconnexion's 3DxNLServer (boost.beast C++ WebSocket server):
- Self-signed cert: CN=3Dconnexion NL Server, RSA 2048, SHA-256
- SAN: IP:127.51.68.120
- TLSv1.2 only
- Cipher: ECDHE-RSA-AES256-GCM-SHA384
- WebSocket subprotocol: `wamp`
- Listens on `127.51.68.120` (non-standard loopback alias)
