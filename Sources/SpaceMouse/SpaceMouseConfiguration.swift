import Foundation

/// Scene properties read by the SpaceMouse driver to compute navigation.
public struct SpaceMouseConfiguration: Sendable {
    /// Application name shown in the 3Dconnexion properties panel.
    public var appName: String

    /// Coordinate system matrix (column-major 4×4).
    /// Describes the client's world coordinate system relative to the driver's
    /// convention (X right, Y up, Z out of screen).
    public var coordinateSystem: [Double]

    /// Front view matrix (column-major 4×4).
    public var frontView: [Double]

    /// Current view/camera matrix (column-major 4×4).
    public var viewMatrix: [Double]

    /// View extents for orthographic projection [left, bottom, -far, right, top, -near].
    public var viewExtents: [Double]

    /// Vertical field of view in radians.
    public var fieldOfView: Double

    /// Whether the projection is perspective (true) or orthographic (false).
    public var isPerspective: Bool

    /// View frustum [left, right, bottom, top, near, far].
    public var viewFrustum: [Double]

    /// View target position in world coordinates.
    public var viewTarget: [Double]

    /// Whether the view can be rotated.
    public var isRotatable: Bool

    /// Construction plane equation [a, b, c, d] for orthographic projections.
    /// Return nil if there is no construction plane.
    public var constructionPlane: [Double]?

    /// Model bounding box [minX, minY, minZ, maxX, maxY, maxZ] in world coordinates.
    public var modelExtents: [Double]

    /// Floor plane equation [a, b, c, d] for walk mode.
    /// Return nil if there is no floor plane.
    public var floorPlane: [Double]?

    /// Conversion factor: length of one world unit in meters.
    public var unitsToMeters: Double

    /// Current pivot position in world coordinates.
    public var pivotPosition: [Double]

    /// Whether the selection set is empty.
    public var isSelectionEmpty: Bool

    /// Selection bounding box [minX, minY, minZ, maxX, maxY, maxZ] in world coordinates.
    public var selectionExtents: [Double]

    /// Selection affine matrix (column-major 4×4).
    public var selectionAffine: [Double]

    /// Mouse pointer position on the near/projection plane in world coordinates.
    public var pointerPosition: [Double]

    /// Hit test result: nearest intersection point, or nil for no hit.
    public var hitLookAt: [Double]?

    /// Frame timing source: 0 = server-driven, 1 = client-driven.
    public var frameTimingSource: Int

    /// Current frame time (milliseconds, used when client-driven).
    public var frameTime: Double

    /// Use row-major matrix order (column vectors, left-multiply: v' = T * v).
    /// Default is false (column-major, matching OpenGL/WebGL convention).
    public var rowMajorOrder: Bool

    public init(
        appName: String = "SpaceMouse",
        coordinateSystem: [Double]? = nil,
        frontView: [Double]? = nil,
        viewMatrix: [Double]? = nil,
        viewExtents: [Double] = [-1, -1, -10, 1, 1, 10],
        fieldOfView: Double = 1.0,
        isPerspective: Bool = true,
        viewFrustum: [Double] = [-1, 1, -1, 1, 0.1, 100],
        viewTarget: [Double] = [0, 0, 0],
        isRotatable: Bool = true,
        constructionPlane: [Double]? = [0, 1, 0, 0],
        modelExtents: [Double] = [-1, -1, -1, 1, 1, 1],
        floorPlane: [Double]? = [0, 1, 0, 0],
        unitsToMeters: Double = 1.0,
        pivotPosition: [Double] = [0, 0, 0],
        isSelectionEmpty: Bool = true,
        selectionExtents: [Double] = [-1, -1, -1, 1, 1, 1],
        selectionAffine: [Double]? = nil,
        pointerPosition: [Double] = [0, 0, 0],
        hitLookAt: [Double]? = nil,
        frameTimingSource: Int = 0,
        frameTime: Double = 0,
        rowMajorOrder: Bool = false
    ) {
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        self.appName = appName
        self.coordinateSystem = coordinateSystem ?? identity
        self.frontView = frontView ?? identity
        self.viewMatrix = viewMatrix ?? identity
        self.viewExtents = viewExtents
        self.fieldOfView = fieldOfView
        self.isPerspective = isPerspective
        self.viewFrustum = viewFrustum
        self.viewTarget = viewTarget
        self.isRotatable = isRotatable
        self.constructionPlane = constructionPlane
        self.modelExtents = modelExtents
        self.floorPlane = floorPlane
        self.unitsToMeters = unitsToMeters
        self.pivotPosition = pivotPosition
        self.isSelectionEmpty = isSelectionEmpty
        self.selectionExtents = selectionExtents
        self.selectionAffine = selectionAffine ?? identity
        self.pointerPosition = pointerPosition
        self.hitLookAt = hitLookAt
        self.frameTimingSource = frameTimingSource
        self.frameTime = frameTime
        self.rowMajorOrder = rowMajorOrder
    }
}
