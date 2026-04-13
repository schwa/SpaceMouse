# 3Dconnexion NLServer WebSocket Protocol

Reverse-engineered from the 3DconnexionJS SDK (npm `@3dconnexion/3dconnexionjs` v0.8.1), the 3DxWare SDK v4.0.6 documentation (`3DconnexionJS.pdf`), and packet captures.

## Overview

The 3Dconnexion driver (`3DxNLServer`) runs a local WebSocket server that implements the WAMP v1 protocol. Client applications connect to receive SpaceMouse input as computed view matrices — the driver handles all navigation math (orbit, pan, zoom, walk) internally.

The architecture is a property-based RPC model: the driver reads scene properties from the client (view matrix, model extents, etc.), computes new navigation state from SpaceMouse input, and writes updated properties back (new view matrix, pivot position, etc.).

## Connection

### Server Address

The server binds to `127.51.68.120` (a non-standard loopback alias), not `127.0.0.1`.

### Port Discovery

An HTTPS endpoint on port 8181 returns the WebSocket port:

```
GET https://127.51.68.120:8181/3dconnexion/nlproxy
Accept: application/json

Response: { "port": 8182, "version": "1.5.0.21901" }
```

The WSS port changes each time the server restarts (increments from 8182).

### TLS

Both ports use self-signed TLS. The server certificate:
- CN: `3Dconnexion NL Server (auto-generated)`
- SAN: `IP:127.51.68.120`
- RSA 2048, SHA-256, TLSv1.2
- Cipher: `ECDHE-RSA-AES256-GCM-SHA384`

The CA certificate and server key are at:
- `/Applications/3Dconnexion/3DxNLServer/root.crt`
- `/Applications/3Dconnexion/3DxNLServer/server.key`
- `/Applications/3Dconnexion/3DxNLServer/server.crt`

### WebSocket

Connect via WSS with subprotocol `wamp`:

```
wss://127.51.68.120:8182
Sec-WebSocket-Protocol: wamp
```

> **Note:** `NWProtocolWebSocket` (Network.framework) fails to connect to this server — it sends a TLS Alert after the handshake before the certificate validator is called. `URLSessionWebSocketTask` works. See `BugReport/` for details.

## WAMP v1 Protocol

All messages are JSON arrays. The first element is the message type ID.

### Message Types

| ID | Type | Direction |
|----|------|-----------|
| 0 | WELCOME | Server → Client |
| 1 | PREFIX | Client → Server |
| 2 | CALL | Bidirectional |
| 3 | CALL_RESULT | Bidirectional |
| 4 | CALL_ERROR | Bidirectional |
| 5 | SUBSCRIBE | Client → Server |
| 6 | UNSUBSCRIBE | Client → Server |
| 7 | PUBLISH | Client → Server |
| 8 | EVENT | Server → Client |

### Handshake

On connect, the server sends a WELCOME:

```json
[0, "sessionId", 1, "Nl-Proxy v1.5.0.21901 Copyright 2013-2025 3Dconnexion."]
```

### CURIE Prefixes

Register short prefixes for URIs:

```json
[1, "3dx_rpc", "wss://127.51.68.120/3dconnexion#"]
[1, "3dconnexion", "wss://127.51.68.120/3dconnexion"]
[1, "self", "spacemouse://local"]
```

After registration, `3dx_rpc:create` resolves to `wss://127.51.68.120/3dconnexion#create`.

### RPC Calls

Client → Server:

```json
[2, "call-1", "3dx_rpc:create", "3dconnexion:3dmouse", "0.8.1"]
```

Server responds:

```json
[3, "call-1", {"connexion": "abc123"}]
```

Or on error:

```json
[4, "call-1", "errorURI", "error description"]
```

## Connection Sequence

### 1. Create 3dmouse

```json
→ [2, "call-1", "3dx_rpc:create", "3dconnexion:3dmouse", "0.8.1"]
← [3, "call-1", {"connexion": "urdwU74Zg1x1VvOL"}]
```

### 2. Create 3dcontroller

```json
→ [2, "call-2", "3dx_rpc:create", "3dconnexion:3dcontroller", "urdwU74Zg1x1VvOL",
   {"version": 0.8, "name": "MyApp", "rowMajorOrder": false}]
← [3, "call-2", {"instance": 370170960790}]
```

The instance ID can be a string or number.

### 3. Subscribe to controller events

```json
→ [5, "3dconnexion:3dcontroller/370170960790"]
```

### 4. Set focus

```json
→ [2, "call-3", "3dx_rpc:update",
   "3dconnexion:3dcontroller/370170960790", {"focus": true}]
← [3, "call-3", {}]
```

### 5. Set frame timing source

```json
→ [2, "call-4", "3dx_rpc:update",
   "3dconnexion:3dcontroller/370170960790",
   {"frame": {"timingSource": 1}}]
← [3, "call-4", {}]
```

`timingSource: 1` means the client drives the animation loop.

### 6. Animation loop (~60fps)

The client must continuously send frame time updates to trigger the driver to process input:

```json
→ [2, "call-N", "3dx_rpc:update",
   "3dconnexion:3dcontroller/370170960790",
   {"frame": {"time": 1713000000000}}]
← [3, "call-N", {}]
```

The time is in milliseconds (e.g., `Date.now.timeIntervalSince1970 * 1000`).

**Without this animation loop, the driver will not send any motion events.**

## Server → Client Property Calls

The driver communicates with the client by sending RPC calls *inside* EVENT messages. These are WAMP CALL messages embedded in the EVENT payload:

```json
[8, "3dconnexion:3dcontroller/370170960790",
  [2, "serverCallId", "self:read", "", "view.affine"]]
```

The inner array is a CALL with:
- `self:read` — driver wants to read a property
- `self:update` — driver wants to write a property
- Third element is always `""` (empty string)
- Fourth element is the property name
- Fifth element (update only) is the new value

The client must respond with CALL_RESULT or CALL_ERROR using the `serverCallId`.

### Read Properties

The driver reads these from the client:

| Property | Type | Description |
|----------|------|-------------|
| `view.affine` | `[Double] (16)` | View/camera matrix, column-major 4×4 |
| `view.extents` | `[Double] (6)` | Orthographic view box `[left, bottom, -far, right, top, -near]` |
| `view.fov` | `Double` | Vertical field of view in radians |
| `view.perspective` | `Bool` | `true` for perspective, `false` for orthographic |
| `view.frustum` | `[Double] (6)` | Perspective frustum `[left, right, bottom, top, near, far]` |
| `view.target` | `[Double] (3)` | Camera target position (world coords) |
| `view.rotatable` | `Bool` | Whether the view can be rotated |
| `view.constructionPlane` | `[Double] (4)` | Plane equation `[a, b, c, d]`, or `null` |
| `model.extents` | `[Double] (6)` | Model bounding box `[minX, minY, minZ, maxX, maxY, maxZ]` |
| `model.floorPlane` | `[Double] (4)` | Floor plane equation, or `null` |
| `model.unitsToMeters` | `Double` | World unit size in meters |
| `pivot.position` | `[Double] (3)` | Rotation pivot (world coords) |
| `selection.empty` | `Bool` | Whether anything is selected |
| `selection.extents` | `[Double] (6)` | Selection bounding box |
| `selection.affine` | `[Double] (16)` | Selection transform matrix |
| `pointer.position` | `[Double] (3)` | Mouse pointer position on near plane |
| `coordinateSystem` | `[Double] (16)` | World coordinate system matrix |
| `views.front` | `[Double] (16)` | Front view camera matrix |
| `hit.lookat` | `[Double] (3)` or `null` | Nearest hit-test intersection, or `null` for no hit |
| `frame.timingSource` | `Int` | `0` = server-driven, `1` = client-driven |
| `frame.time` | `Double` | Current frame time (ms) |

### Write Properties

The driver writes these to the client:

| Property | Type | Description |
|----------|------|-------------|
| `motion` | `Bool` | `true` = motion started, `false` = motion stopped |
| `view.affine` | `[Double] (16)` | New view/camera matrix |
| `view.extents` | `[Double] (6)` | New orthographic extents |
| `view.fov` | `Double` | New field of view (radians) |
| `view.target` | `[Double] (3)` | New camera target |
| `pivot.position` | `[Double] (3)` | New pivot position |
| `pivot.visible` | `Bool` | Show/hide the pivot indicator |
| `commands.activeCommand` | `String` | Custom command activated by button press |
| `events.keyPress` | `Int` | SpaceMouse button pressed |
| `events.keyRelease` | `Int` | SpaceMouse button released |
| `transaction` | `Int` | `>0` = frame begin, `0` = frame end |
| `selection.affine` | `[Double] (16)` | Updated selection transform |
| `settings.changed` | `Int` | Driver settings changed (value is a counter) |

### Hit-Testing

The driver performs hit-testing by writing ray parameters, then reading the result:

1. `update hit.selectionOnly` — `Bool`, test selection only
2. `update hit.aperture` — `Double`, ray diameter
3. `update hit.direction` — `[Double] (3)`, ray direction
4. `update hit.lookfrom` — `[Double] (3)`, ray origin
5. `read hit.lookat` — client returns `[x, y, z]` or `null`

This cycle may repeat twice (once for center, once for pointer position).

## Event Flow

A typical motion sequence:

```
← read  selection.empty
← read  view.target
← read  view.affine
← read  view.perspective
← read  view.frustum
← update hit.selectionOnly = false
← update motion = true           → .motionStart
← update pivot.visible = true     → .pivotVisible(true)
← update transaction = 1          → .transaction(true)
← update view.affine = [...]      → .viewMatrix([...])
← update transaction = 0          → .transaction(false)
  ... (repeats per frame while mouse is moving) ...
← update pivot.visible = false    → .pivotVisible(false)
← update motion = false           → .motionStop
← read  selection.empty
← read  model.extents
← read  view.affine
← update hit.aperture, hit.direction, hit.lookfrom
← read  hit.lookat
← update pivot.position = [...]   → .pivotPosition([...])
```

## Built-in vs Custom Commands

Built-in SpaceMouse buttons (Fit, Front, Top, rotation lock, etc.) are handled entirely by the driver. The client never sees a button press — it only sees the resulting view matrix changes.

Custom commands require registering an action tree via `3dx_rpc:update` with a `commands` property containing `activeSet` and `tree` objects. When the user presses a button mapped to a custom command, the driver sends `update commands.activeCommand = "commandId"`.

## Matrix Convention

By default, matrices are **column-major** (matching OpenGL/WebGL). Elements `[12]`, `[13]`, `[14]` are the translation (tx, ty, tz).

Pass `rowMajorOrder: true` in the `create 3dcontroller` info to use row-major matrices instead.

## Required Processes

- **`3DxNLServer`** — the WebSocket server (launched automatically by the driver)
- **`3DconnexionHelper`** — bridges HID device input to the NLServer
- **`com.3dconnexion.driver.dext`** — DriverKit extension for USB HID

If `3DconnexionHelper` is not running, the NLServer accepts connections but never sends motion events. Restart with:

```
launchctl kickstart gui/$(id -u)/com.3dconnexion.helper
```
