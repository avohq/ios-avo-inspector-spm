import Foundation

@objc public class AvoAnonymousId: NSObject {
    private static let lock = NSLock()
    private static var _anonymousId: String?
    private static let storageKey = "AvoInspectorAnonymousId"

    @objc public class func anonymousId() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = _anonymousId, !cached.isEmpty {
            return cached
        }

        if !AvoInspector.avoStorage().isInitialized() {
            return "unknown"
        }

        let stored = AvoInspector.avoStorage().getItem(storageKey)

        if let stored = stored, !stored.isEmpty {
            _anonymousId = stored
        } else {
            _anonymousId = AvoGuid.newGuid()
            AvoInspector.avoStorage().setItem(storageKey, _anonymousId!)
        }

        return _anonymousId!
    }

    @objc public class func setAnonymousId(_ id: String) {
        lock.lock()
        defer { lock.unlock() }

        _anonymousId = id
        AvoInspector.avoStorage().setItem(storageKey, _anonymousId!)
    }

    @objc public class func clearCache() {
        lock.lock()
        defer { lock.unlock() }

        _anonymousId = nil
    }
}
