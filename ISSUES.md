# ISSUES.md

---

## 1: Refactor: isolate WAMP protocol from SpaceMouse logic
status: new
priority: high
kind: task
labels: refactor
created: 2026-04-12T22:31:30Z

WAMPSession currently mixes WAMP v1 protocol handling with 3Dconnexion-specific logic. Split into layers: WebSocketTransport, WAMPSession (generic WAMP v1), and SpaceMouseConnection (3Dconnexion navlib on top).

---

## 2: Refactor: clean public API surface
status: new
priority: high
kind: task
labels: refactor
created: 2026-04-12T22:31:42Z

App-facing API should be just SpaceMouseConnection, SpaceMouseEvent, and SpaceMouseConfiguration. No WAMP, WebSocket, or protocol details visible.

---

## 3: Replace posix_spawn/curl with Network framework
status: new
priority: high
kind: task
labels: cleanup
created: 2026-04-12T22:31:42Z
updated: 2026-04-12T22:32:53Z

Port discovery currently shells out to curl via posix_spawn. Use Network framework for both HTTPS discovery and WebSocket transport. No shelling out to curl. The previous NWConnection attempts failed due to debugging mistakes, not framework issues.

---

## 4: Port discovery is fragile — hardcoded to port 8181
status: new
priority: medium
kind: bug
labels: robustness
created: 2026-04-12T22:31:42Z

The HTTPS discovery endpoint is hardcoded to 127.51.68.120:8181. If the NLServer restarts or the HTTP listener drops, discovery fails. Consider scanning for listening ports on 127.51.68.120, trying WSS ports directly, or reading the port from config.

---

## 5: Add disconnect/cleanup support
status: new
priority: medium
kind: feature
created: 2026-04-12T22:31:42Z

SpaceMouseConnection has no way to cleanly disconnect. Should send 3dx_rpc:delete, cancel animation/reader threads, close WebSocket, and finish the AsyncStream.

---

## 6: Handle NLServer restart gracefully
status: new
priority: low
kind: feature
labels: robustness
created: 2026-04-12T22:31:42Z

If 3DxNLServer restarts while connected, the WebSocket drops. The library should detect this and either auto-reconnect or surface a clear error/event.

---

## 7: Use Network framework structured concurrency API
status: new
priority: high
kind: task
labels: refactor
created: 2026-04-12T22:31:42Z

WWDC 2025 session 250 introduces NetworkConnection with native async/await support. Replace the current URLSession WebSocket + semaphore threading with NetworkConnection. This should eliminate the Thread.detachNewThread/semaphore hacks.

---

## 8: Research: multiple SpaceMouse devices
status: new
priority: low
kind: task
labels: research
created: 2026-04-12T22:44:46Z

Unknown what happens with multiple devices connected. The WAMP create call doesn't include device selection. Does the driver merge inputs? Can you address individual devices? Test if possible.

---

