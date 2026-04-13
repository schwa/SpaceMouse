import Foundation
import Synchronization

/// A connection to a 3Dconnexion SpaceMouse device.
///
/// Create an instance, set scene properties, and iterate over ``events`` to receive input.
///
/// ```swift
/// let spaceMouse = SpaceMouse(appName: "MyApp")
/// spaceMouse.isPerspective = true
/// spaceMouse.modelExtents = [-1, -1, -1, 1, 1, 1]
///
/// for await event in spaceMouse.events {
///     switch event {
///     case .viewMatrix(let m):
///         camera.transform = m
///         spaceMouse.viewMatrix = m
///     case .motionStart:
///         renderer.beginContinuousRedraw()
///     case .motionStop:
///         renderer.endContinuousRedraw()
///     default: break
///     }
/// }
/// ```
///
/// Cancelling the iterating task disconnects automatically.
public final class SpaceMouse: Sendable {
    private let configuration: LockedValue<SpaceMouseConfiguration>
    private let connection: SpaceMouseConnection

    // MARK: - Init

    /// Create a SpaceMouse connection.
    /// - Parameter appName: Name shown in the 3Dconnexion driver properties panel.
    public init(appName: String = "SpaceMouse") {
        let config = SpaceMouseConfiguration(appName: appName)
        self.configuration = LockedValue(config)
        self.connection = SpaceMouseConnection(configuration: configuration)
    }

    // MARK: - Events

    /// An `AsyncSequence` of events from the SpaceMouse.
    ///
    /// Accessing this property connects to the driver.
    /// Cancelling the iterating task disconnects.
    /// The sequence ends if the driver disconnects.
    public var events: AsyncStream<SpaceMouseEvent> {
        get async throws {
            try await connection.connect()
        }
    }

    // MARK: - Scene Properties
    //
    // These properties describe your scene to the SpaceMouse driver.
    // The driver reads them each frame to compute navigation.
    // Keep them in sync with your scene — especially viewMatrix,
    // which you should update after each .viewMatrix event.

    /// The current view/camera matrix (column-major 4×4).
    ///
    /// Set this to your camera's world transform. After receiving
    /// a ``SpaceMouseEvent/viewMatrix(_:)`` event, feed the new
    /// matrix back so the driver starts the next frame from the
    /// correct position.
    public var viewMatrix: [Double] {
        get { configuration.withLock { $0.viewMatrix } }
        set { configuration.withLock { $0.viewMatrix = newValue } }
    }

    /// View extents for orthographic projection: `[left, bottom, -far, right, top, -near]`.
    ///
    /// Only used when ``isPerspective`` is `false`.
    public var viewExtents: [Double] {
        get { configuration.withLock { $0.viewExtents } }
        set { configuration.withLock { $0.viewExtents = newValue } }
    }

    /// Vertical field of view in radians.
    ///
    /// Used for zoom in perspective projections. Update after
    /// receiving a ``SpaceMouseEvent/fieldOfView(_:)`` event.
    public var fieldOfView: Double {
        get { configuration.withLock { $0.fieldOfView } }
        set { configuration.withLock { $0.fieldOfView = newValue } }
    }

    /// Whether the projection is perspective (`true`) or orthographic (`false`).
    ///
    /// Determines which navigation and zoom algorithms the driver uses.
    public var isPerspective: Bool {
        get { configuration.withLock { $0.isPerspective } }
        set { configuration.withLock { $0.isPerspective = newValue } }
    }

    /// View frustum: `[left, right, bottom, top, near, far]`.
    ///
    /// Used in perspective projections to calculate field of view
    /// and determine model visibility.
    public var viewFrustum: [Double] {
        get { configuration.withLock { $0.viewFrustum } }
        set { configuration.withLock { $0.viewFrustum = newValue } }
    }

    /// View target position in world coordinates.
    public var viewTarget: [Double] {
        get { configuration.withLock { $0.viewTarget } }
        set { configuration.withLock { $0.viewTarget = newValue } }
    }

    /// Whether the view can be rotated.
    ///
    /// When `false`, the driver treats the view as pan-zoom only
    /// and disables view orientation keys (Front, Top, etc.).
    public var isRotatable: Bool {
        get { configuration.withLock { $0.isRotatable } }
        set { configuration.withLock { $0.isRotatable = newValue } }
    }

    /// Coordinate system matrix (column-major 4×4).
    ///
    /// Describes your world coordinate system relative to the driver's
    /// convention (X right, Y up, Z out of screen). Typically the
    /// inverse of your front view matrix.
    public var coordinateSystem: [Double] {
        get { configuration.withLock { $0.coordinateSystem } }
        set { configuration.withLock { $0.coordinateSystem = newValue } }
    }

    /// Front view matrix (column-major 4×4).
    ///
    /// The camera pose for the "Front" view. Other standard views
    /// (Top, Right, etc.) are derived from this.
    public var frontView: [Double] {
        get { configuration.withLock { $0.frontView } }
        set { configuration.withLock { $0.frontView = newValue } }
    }

    /// Model bounding box: `[minX, minY, minZ, maxX, maxY, maxZ]` in world coordinates.
    ///
    /// Used for zoom-to-fit and pivot calculations.
    public var modelExtents: [Double] {
        get { configuration.withLock { $0.modelExtents } }
        set { configuration.withLock { $0.modelExtents = newValue } }
    }

    /// Floor plane equation `[a, b, c, d]` for walk mode.
    ///
    /// Set to `nil` if there is no floor plane.
    public var floorPlane: [Double]? {
        get { configuration.withLock { $0.floorPlane } }
        set { configuration.withLock { $0.floorPlane = newValue } }
    }

    /// Length of one world unit in meters.
    ///
    /// Used by the walk and first-person motion models to calculate
    /// height above floor and movement speed.
    public var unitsToMeters: Double {
        get { configuration.withLock { $0.unitsToMeters } }
        set { configuration.withLock { $0.unitsToMeters = newValue } }
    }

    /// Rotation pivot position in world coordinates.
    ///
    /// Update after receiving a ``SpaceMouseEvent/pivotPosition(_:)`` event.
    public var pivotPosition: [Double] {
        get { configuration.withLock { $0.pivotPosition } }
        set { configuration.withLock { $0.pivotPosition = newValue } }
    }

    /// Whether the selection set is empty.
    ///
    /// When `false`, the driver may use the selection extents
    /// for zoom-to-selection and pivot calculations.
    public var isSelectionEmpty: Bool {
        get { configuration.withLock { $0.isSelectionEmpty } }
        set { configuration.withLock { $0.isSelectionEmpty = newValue } }
    }

    /// Selection bounding box: `[minX, minY, minZ, maxX, maxY, maxZ]` in world coordinates.
    public var selectionExtents: [Double] {
        get { configuration.withLock { $0.selectionExtents } }
        set { configuration.withLock { $0.selectionExtents = newValue } }
    }

    /// Construction plane equation `[a, b, c, d]` for orthographic projections.
    ///
    /// When the camera looks down the plane normal, the driver
    /// disables rotation (pure pan-zoom). Set to `nil` if there
    /// is no construction plane.
    public var constructionPlane: [Double]? {
        get { configuration.withLock { $0.constructionPlane } }
        set { configuration.withLock { $0.constructionPlane = newValue } }
    }

    /// Mouse pointer position on the projection plane in world coordinates.
    ///
    /// Used for quick-zoom toward the pointer.
    public var pointerPosition: [Double] {
        get { configuration.withLock { $0.pointerPosition } }
        set { configuration.withLock { $0.pointerPosition = newValue } }
    }
}
