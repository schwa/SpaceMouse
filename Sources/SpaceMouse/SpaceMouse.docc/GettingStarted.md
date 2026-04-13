# Getting Started

Connect to a SpaceMouse and handle events.

## Overview

### Create a SpaceMouse

```swift
let spaceMouse = SpaceMouse(appName: "MyCADApp")
```

The `appName` is shown in the 3Dconnexion driver's properties panel to identify your app.

### Configure Scene Properties

Tell the driver about your scene so it can compute correct navigation:

```swift
// Coordinate system: X right, Y up, Z out of screen (default)
spaceMouse.coordinateSystem = .identity

// Camera
spaceMouse.viewMatrix = camera.worldTransform
spaceMouse.fieldOfView = camera.fov
spaceMouse.isPerspective = true

// Scene
spaceMouse.modelExtents = scene.boundingBox
```

### Read Events

Events arrive as an `AsyncSequence`. Iterate over `events` in a task:

```swift
Task {
    for await event in spaceMouse.events {
        switch event {
        case .viewMatrix(let matrix):
            camera.worldTransform = matrix
            spaceMouse.viewMatrix = matrix

        case .fieldOfView(let fov):
            camera.fov = fov
            spaceMouse.fieldOfView = fov

        case .pivotPosition(let position):
            scene.pivotIndicator.position = position

        case .pivotVisible(let visible):
            scene.pivotIndicator.isVisible = visible

        case .motionStart:
            renderer.beginContinuousRedraw()

        case .motionStop:
            renderer.endContinuousRedraw()

        case .command(let id):
            handleCommand(id)

        case .keyPress(let key):
            handleButton(key, pressed: true)

        case .keyRelease(let key):
            handleButton(key, pressed: false)

        default:
            break
        }
    }
}
```

### Disconnect

Cancel the task to disconnect:

```swift
let task = Task {
    for await event in spaceMouse.events { ... }
}

// Later:
task.cancel() // disconnects cleanly
```

### Updating State During Navigation

The driver asks your app for the current view matrix, model extents, etc. on every frame. Keep the `SpaceMouse` properties in sync with your scene:

```swift
case .viewMatrix(let matrix):
    camera.worldTransform = matrix
    spaceMouse.viewMatrix = matrix  // feed it back
```

If you don't feed the matrix back, the driver will keep reading the stale initial value and navigation will feel wrong.
