import Foundation

/// Events emitted by the SpaceMouse navigation library.
public enum SpaceMouseEvent: Sendable {
    /// Motion started — the user is actively moving the SpaceMouse.
    case motionStart
    /// Motion stopped.
    case motionStop

    /// Updated view/camera matrix (column-major 4×4).
    case viewMatrix([Double])
    /// Updated view extents (orthographic: [left, bottom, -far, right, top, -near]).
    case viewExtents([Double])
    /// Updated field of view (radians).
    case fieldOfView(Double)

    /// Pivot position changed (world coordinates [x, y, z]).
    case pivotPosition([Double])
    /// Pivot visibility changed.
    case pivotVisible(Bool)

    /// Button/command activated by the user.
    case command(String)
    /// Key pressed on the SpaceMouse.
    case keyPress(Int)
    /// Key released on the SpaceMouse.
    case keyRelease(Int)

    /// Transaction boundary. `true` = begin, `false` = end.
    /// View updates between begin/end form a single frame.
    case transaction(Bool)

    /// Settings changed in the 3Dconnexion driver UI.
    case settingsChanged

    /// View target position changed.
    case viewTarget([Double])

    /// Selection affine matrix changed.
    case selectionAffine([Double])
}
