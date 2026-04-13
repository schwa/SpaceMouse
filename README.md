# SpaceMouseWS

Swift library and CLI for reading 3Dconnexion SpaceMouse input via the 3DxNLServer WebSocket interface.

## How it works

The 3Dconnexion driver (`3DxNLServer`) exposes a local WebSocket server on `127.51.68.120` using the WAMP v1 protocol over WSS. This is the same interface used by web apps like Onshape.

The library:
1. Discovers the WSS port via HTTPS (`https://127.51.68.120:8181/3dconnexion/nlproxy`)
2. Connects over WSS with the `wamp` subprotocol
3. Creates a 3dmouse connexion and 3dcontroller
4. Drives a 60fps animation loop (frame timing source)
5. Responds to navlib property queries (view matrix, extents, frustum, etc.)
6. Streams events back to the caller via `AsyncStream<SpaceMouseEvent>`

## Requirements

- macOS 14+
- 3Dconnexion 3DxWare driver installed and running
- `3DconnexionHelper` must be running (provides HID → driver bridge)

## Usage

### Swift Library

```swift
import SpaceMouse

let connection = SpaceMouseConnection(
    configuration: SpaceMouseConfiguration(appName: "MyApp")
)

let events = try await connection.connect()
for await event in events {
    switch event {
    case .motionStart: print("Moving!")
    case .viewMatrix(let m): print("View: \(m[12]), \(m[13]), \(m[14])")
    case .keyPress(let k): print("Button: \(k)")
    default: break
    }
}
```

### Debug CLI

```
swift run spacemouse-debug
```

### Python (standalone)

```
uv run --with websockets spacemouse_ws.py
```

## Events

| Event | Description |
|-------|-------------|
| `motionStart` / `motionStop` | SpaceMouse is being moved |
| `viewMatrix([Double])` | Updated 4×4 camera matrix (column-major) |
| `viewExtents([Double])` | Orthographic view extents |
| `fieldOfView(Double)` | FOV in radians |
| `pivotPosition([Double])` | Rotation pivot (world coords) |
| `pivotVisible(Bool)` | Pivot visibility |
| `command(String)` | Button command activated |
| `keyPress(Int)` / `keyRelease(Int)` | Button press/release |
| `transaction(Bool)` | Frame boundary (begin/end) |
| `settingsChanged` | Driver settings changed |

## Protocol Notes

- **WAMP v1** over WSS with self-signed TLS certificate
- Server listens on `127.51.68.120` (not `127.0.0.1`)
- HTTP discovery on port 8181, WSS on the port returned by discovery
- The navlib queries the client for scene properties and sends back computed view matrices
- Requires an animation loop (`frame.timingSource = 1` + periodic `frame.time` updates)

## Troubleshooting

- **No events:** Make sure `3DconnexionHelper` is running: `launchctl kickstart gui/$(id -u)/com.3dconnexion.helper`
- **Connection refused:** Restart `3DxNLServer`: `killall 3DxNLServer && open /Applications/3Dconnexion/3DxNLServer/3DxNLServer.app`
- **Port 8181 not responding:** The NLServer may have dropped its HTTP listener after too many connections. Restart it.
