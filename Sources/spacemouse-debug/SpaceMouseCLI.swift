#if os(macOS)
import SpaceMouse
import Foundation


@main
struct SpaceMouseCLI {

    static func main() async {
        setbuf(stdout, nil)

        let spaceMouse = SpaceMouse(appName: "SpaceMouseDebug")

        print("🎮 Connecting to 3DxNLServer...")

        do {
            let events = try await spaceMouse.events
            print("✓ Connected. Listening for events... (Ctrl+C to quit)\n")

            for await event in events {
                switch event {
                case .motionStart:
                    print("🎮 Motion START")
                case .motionStop:
                    print("🎮 Motion STOP")
                case .viewMatrix(let m):
                    if m.count >= 16 {
                        let tx = m[12].formatted(.number.precision(.fractionLength(3)))
                        let ty = m[13].formatted(.number.precision(.fractionLength(3)))
                        let tz = m[14].formatted(.number.precision(.fractionLength(3)))
                        print("📐 View  tx=\(tx) ty=\(ty) tz=\(tz)")
                    }
                    spaceMouse.viewMatrix = m
                case .fieldOfView(let fov):
                    print("🔭 FOV: \(fov.formatted(.number.precision(.fractionLength(3))))")
                    spaceMouse.fieldOfView = fov
                case .pivotPosition(let p):
                    if p.count >= 3 {
                        print("📍 Pivot: \(p[0].formatted(.number.precision(.fractionLength(3)))) \(p[1].formatted(.number.precision(.fractionLength(3)))) \(p[2].formatted(.number.precision(.fractionLength(3))))")
                    }
                case .pivotVisible(let visible):
                    print("👁  Pivot visible: \(visible)")
                case .command(let cmd):
                    print("⌨️  Command: \(cmd)")
                case .keyPress(let key):
                    print("🔑 Key press: \(key)")
                case .keyRelease(let key):
                    print("🔑 Key release: \(key)")
                case .transaction:
                    break
                case .settingsChanged:
                    print("⚙️  Settings changed")
                case .viewTarget(let t):
                    print("🎯 Target: \(t)")
                case .viewExtents:
                    break
                case .selectionAffine(let m):
                    print("✅ Selection: \(m.prefix(4))...")
                }
            }
            print("Connection closed.")
        } catch {
            print("✗ Error: \(error)")
        }

    }

}
#endif


