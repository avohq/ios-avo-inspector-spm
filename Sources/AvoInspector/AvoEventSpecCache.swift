import Foundation

@objc public class AvoEventSpecCache: NSObject {

    private static let ttlMs: Int64 = 60_000
    private static let maxEventCount = 50

    private var cache = [String: AvoEventSpecCacheEntry]()
    private var globalEventCount: Int32 = 0
    private let lock = NSLock()

    public override init() {
        super.init()
    }

    private func currentTimeMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    @objc public func get(_ key: String) -> AvoEventSpecResponse? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return nil }

        let now = currentTimeMillis()
        if shouldEvict(entry, now: now) {
            cache.removeValue(forKey: key)
            return nil
        }

        entry.lastAccessed = now
        return entry.spec
    }

    @objc public func set(_ key: String, spec: AvoEventSpecResponse?) {
        lock.lock()
        defer { lock.unlock() }

        let now = currentTimeMillis()
        let isUpdate = cache[key] != nil

        globalEventCount += 1
        if !isUpdate && cache.count >= AvoEventSpecCache.maxEventCount {
            evictOldest()
        }

        let entry = AvoEventSpecCacheEntry(spec: spec, timestamp: now)
        entry.eventCount = globalEventCount
        cache[key] = entry
    }

    @objc public func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return false }

        let now = currentTimeMillis()
        if shouldEvict(entry, now: now) {
            cache.removeValue(forKey: key)
            return false
        }

        return true
    }

    @objc public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    @objc public func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    private func shouldEvict(_ entry: AvoEventSpecCacheEntry, now: Int64) -> Bool {
        let age = now - entry.timestamp
        return age > AvoEventSpecCache.ttlMs
    }

    private func evictOldest() {
        var oldestKey: String?
        var oldestAccess: Int64 = Int64.max

        for (key, entry) in cache {
            if entry.lastAccessed < oldestAccess {
                oldestAccess = entry.lastAccessed
                oldestKey = key
            }
        }

        if let key = oldestKey {
            cache.removeValue(forKey: key)
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Evicted oldest cache entry: %@", key)
            }
        }
    }

    @objc public class func generateKey(_ apiKey: String, streamId: String, eventName: String) -> String {
        return "\(apiKey):\(streamId):\(eventName)"
    }
}
