#if os(macOS)
import Synchronization

/// Thread-safe mutable value. A `Sendable` class wrapper around `Mutex`.
public final class LockedValue<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    public init(_ value: Value) {
        self.mutex = Mutex(value)
    }

    public func withLock<R: Sendable>(_ body: @Sendable (inout sending Value) -> sending R) -> R {
        mutex.withLock(body)
    }

}
#endif
