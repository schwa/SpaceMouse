# ``SpaceMouse``

Read 3Dconnexion SpaceMouse input in your app.

## Overview

SpaceMouse provides a simple async interface to 3Dconnexion SpaceMouse devices. It connects to the 3DxWare driver over its local WebSocket interface — the same protocol used by web apps like Onshape — and delivers events as an `AsyncSequence`.

Your app doesn't need to know anything about WebSockets, WAMP, or the 3Dconnexion SDK. Just create a `SpaceMouse`, read `.events`, and update your scene.

### Basic Usage

```swift
let spaceMouse = SpaceMouse(appName: "MyApp")

for await event in spaceMouse.events {
    switch event {
    case .viewMatrix(let matrix):
        camera.transform = matrix
        spaceMouse.viewMatrix = matrix
    case .motionStart:
        renderer.beginContinuousRedraw()
    case .motionStop:
        renderer.endContinuousRedraw()
    default:
        break
    }
}
```

Cancelling the task disconnects automatically.

### Feeding State Back

The 3Dconnexion navigation library computes view transforms based on your scene state. Set properties on the `SpaceMouse` instance so it can respond accurately:

```swift
spaceMouse.viewMatrix = camera.matrix
spaceMouse.modelExtents = scene.boundingBox
spaceMouse.fieldOfView = camera.fov
spaceMouse.isPerspective = true
```

When the driver sends a new `viewMatrix`, update both your camera and the `SpaceMouse` instance so the next frame starts from the correct position.

### Requirements

- macOS 14+
- 3Dconnexion 3DxWare driver installed and running
- A physical SpaceMouse device connected

## Topics

### Essentials

- ``SpaceMouse``
- ``SpaceMouseEvent``
