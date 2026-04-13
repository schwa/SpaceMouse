import Foundation
import Synchronization

/// Connects to the 3Dconnexion 3DxNLServer and streams SpaceMouse events.
///
/// This is the internal connection manager. The public API is ``SpaceMouse``.
final class SpaceMouseConnection: Sendable {
    let configuration: LockedValue<SpaceMouseConfiguration>

    static let host = "127.51.68.120"
    static let httpPort: UInt16 = 8181

    init(configuration: LockedValue<SpaceMouseConfiguration>) {
        self.configuration = configuration
    }

    /// Connect and return an AsyncStream of events.
    func connect() async throws -> AsyncStream<SpaceMouseEvent> {
        let config = self.configuration
        return try await Task.detached {
            try await Self._connect(configuration: config)
        }.value
    }

    private static func _connect(configuration: LockedValue<SpaceMouseConfiguration>) async throws -> AsyncStream<SpaceMouseEvent> {
        let port = try await Self.discoverPort()

        let (stream, continuation) = AsyncStream<SpaceMouseEvent>.makeStream()

        let config = configuration
        let wamp = try await WAMPSession(host: Self.host, port: port) { callID, procedure, args in
            Self.handleCall(procedure: procedure, args: args, configuration: config, continuation: continuation)
        }

        // Start reader loop BEFORE any RPC calls
        Task {
            await wamp.readerLoop()
            continuation.finish()
        }

        // Register CURIE prefixes
        try await wamp.prefix("3dx_rpc", uri: "wss://\(Self.host)/3dconnexion#")
        try await wamp.prefix("3dconnexion", uri: "wss://\(Self.host)/3dconnexion")
        try await wamp.prefix("self", uri: "spacemouse-swift://local")

        // Create 3dmouse connexion
        let mouseResult = try await wamp.call("3dx_rpc:create", args: "3dconnexion:3dmouse", "0.8.1")
        guard let mouseDict = mouseResult as? [String: Any], let connID = mouseDict["connexion"] as? String else {
            throw SpaceMouseError.createFailed("3dmouse")
        }

        // Create 3dcontroller
        let appName = configuration.withLock { $0.appName }
        let rowMajor = configuration.withLock { $0.rowMajorOrder }
        let info: [String: Any] = ["version": 0.8, "name": appName, "rowMajorOrder": rowMajor]
        let ctrlResult = try await wamp.call("3dx_rpc:create", args: "3dconnexion:3dcontroller", connID, info)
        guard let ctrlDict = ctrlResult as? [String: Any], let inst = ctrlDict["instance"] else {
            throw SpaceMouseError.createFailed("3dcontroller")
        }
        let instance = "\(inst)"

        // Subscribe to controller events
        try await wamp.subscribe("3dconnexion:3dcontroller/\(instance)")

        // Set focus
        _ = try await wamp.call("3dx_rpc:update", args: "3dconnexion:3dcontroller/\(instance)", ["focus": true])

        // Set client as frame timing source
        _ = try await wamp.call("3dx_rpc:update", args: "3dconnexion:3dcontroller/\(instance)", ["frame": ["timingSource": 1]])

        // Start animation loop (~60fps)
        Task {
            while !Task.isCancelled {
                let now = Date.now.timeIntervalSince1970 * 1000
                _ = try? await wamp.call("3dx_rpc:update", args: "3dconnexion:3dcontroller/\(instance)", ["frame": ["time": now]])
                try? await Task.sleep(for: .milliseconds(16))
            }
        }

        return stream
    }

    // MARK: - Server→Client property calls

    private static func handleCall(
        procedure: String,
        args: [Any],
        configuration: LockedValue<SpaceMouseConfiguration>,
        continuation: AsyncStream<SpaceMouseEvent>.Continuation
    ) -> Any? {
        guard args.count >= 2, let property = args[1] as? String else {
            return nil
        }

        if procedure == "self:read" {
            return readProperty(property, configuration: configuration)
        } else if procedure == "self:update", args.count >= 3 {
            updateProperty(property, value: args[2], configuration: configuration, continuation: continuation)
            return nil
        }
        return nil
    }

    private static func readProperty(_ property: String, configuration: LockedValue<SpaceMouseConfiguration>) -> Any? {
        let c = configuration.withLock { $0 }
        switch property {
        case "view.affine": return c.viewMatrix
        case "view.extents": return c.viewExtents
        case "view.fov": return c.fieldOfView
        case "view.perspective": return c.isPerspective
        case "view.frustum": return c.viewFrustum
        case "view.target": return c.viewTarget
        case "view.rotatable": return c.isRotatable
        case "view.constructionPlane": return c.constructionPlane
        case "model.extents": return c.modelExtents
        case "model.floorPlane": return c.floorPlane
        case "model.unitsToMeters": return c.unitsToMeters
        case "pivot.position": return c.pivotPosition
        case "selection.empty": return c.isSelectionEmpty
        case "selection.extents": return c.selectionExtents
        case "selection.affine": return c.selectionAffine
        case "pointer.position": return c.pointerPosition
        case "coordinateSystem": return c.coordinateSystem
        case "views.front": return c.frontView
        case "hit.lookat": return c.hitLookAt
        case "frame.timingSource": return c.frameTimingSource
        case "frame.time": return c.frameTime
        default:
            print("[SpaceMouse] unhandled read: \(property)")
            return nil
        }
    }

    private static func updateProperty(
        _ property: String,
        value: Any,
        configuration: LockedValue<SpaceMouseConfiguration>,
        continuation: AsyncStream<SpaceMouseEvent>.Continuation
    ) {
        func doubles(_ v: Any) -> [Double]? { (v as? [NSNumber])?.map(\.doubleValue) }

        switch property {
        case "motion":
            if let n = value as? NSNumber { continuation.yield(n.boolValue ? .motionStart : .motionStop) }
        case "view.affine":
            if let m = doubles(value) { configuration.withLock { $0.viewMatrix = m }; continuation.yield(.viewMatrix(m)) }
        case "view.extents":
            if let e = doubles(value) { configuration.withLock { $0.viewExtents = e }; continuation.yield(.viewExtents(e)) }
        case "view.fov":
            if let f = (value as? NSNumber)?.doubleValue { configuration.withLock { $0.fieldOfView = f }; continuation.yield(.fieldOfView(f)) }
        case "view.target":
            if let t = doubles(value) { configuration.withLock { $0.viewTarget = t }; continuation.yield(.viewTarget(t)) }
        case "pivot.position":
            if let p = doubles(value) { configuration.withLock { $0.pivotPosition = p }; continuation.yield(.pivotPosition(p)) }
        case "pivot.visible":
            if let n = value as? NSNumber { continuation.yield(.pivotVisible(n.boolValue)) }
        case "commands.activeCommand":
            if let cmd = value as? String { continuation.yield(.command(cmd)) }
        case "events.keyPress":
            if let k = (value as? NSNumber)?.intValue { continuation.yield(.keyPress(k)) }
        case "events.keyRelease":
            if let k = (value as? NSNumber)?.intValue { continuation.yield(.keyRelease(k)) }
        case "transaction":
            if let n = (value as? NSNumber)?.intValue { continuation.yield(.transaction(n != 0)) }
        case "selection.affine":
            if let m = doubles(value) { configuration.withLock { $0.selectionAffine = m }; continuation.yield(.selectionAffine(m)) }
        case "settings.changed":
            print("[SpaceMouse] settings.changed = \(value)")
            continuation.yield(.settingsChanged)
        case "hit.selectionOnly", "hit.lookfrom", "hit.direction", "hit.aperture":
            break
        default:
            print("[SpaceMouse] unhandled update: \(property) = \(value)")
        }
    }

    // MARK: - Port Discovery

    static func discoverPort() async throws -> UInt16 {
        let delegate = _DiscoveryDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        guard let url = URL(string: "https://\(host):\(httpPort)/3dconnexion/nlproxy") else {
            throw SpaceMouseError.discoveryFailed("Invalid URL")
        }
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["port"] as? Int else {
            throw SpaceMouseError.discoveryFailed("Invalid response")
        }
        return UInt16(port)
    }
}

private final class _DiscoveryDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
