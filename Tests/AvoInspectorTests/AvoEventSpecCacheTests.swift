import XCTest
@testable import AvoInspector

final class AvoEventSpecCacheTests: XCTestCase {

    private var cache: AvoEventSpecCache!

    override func setUp() {
        super.setUp()
        cache = AvoEventSpecCache()
    }

    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    // MARK: - Basic operations

    func test_startsEmpty() {
        XCTAssertEqual(cache.size(), 0)
        XCTAssertFalse(cache.contains("key"))
        XCTAssertNil(cache.get("key"))
    }

    func test_storesAndRetrievesSpec() {
        let spec = AvoEventSpecResponse()
        cache.set("key1", spec: spec)

        XCTAssertEqual(cache.size(), 1)
        XCTAssertTrue(cache.contains("key1"))
        XCTAssertTrue(cache.get("key1") === spec)
    }

    func test_storesNilSpec_asCacheMissMarker() {
        cache.set("key1", spec: nil)

        XCTAssertEqual(cache.size(), 1)
        XCTAssertTrue(cache.contains("key1"))
        XCTAssertNil(cache.get("key1"))
    }

    func test_clearsAllEntries() {
        let spec = AvoEventSpecResponse()
        cache.set("key1", spec: spec)
        cache.set("key2", spec: spec)

        XCTAssertEqual(cache.size(), 2)

        cache.clear()

        XCTAssertEqual(cache.size(), 0)
        XCTAssertFalse(cache.contains("key1"))
        XCTAssertFalse(cache.contains("key2"))
    }

    func test_overwritesExistingKey() {
        let spec1 = AvoEventSpecResponse()
        let spec2 = AvoEventSpecResponse()

        cache.set("key1", spec: spec1)
        cache.set("key1", spec: spec2)

        XCTAssertEqual(cache.size(), 1)
        XCTAssertTrue(cache.get("key1") === spec2)
    }

    // MARK: - generateKey

    func test_generateKey_createsCorrectFormat() {
        let key = AvoEventSpecCache.generateKey("apiKey", streamId: "stream1", eventName: "Event Name")
        XCTAssertEqual(key, "apiKey:stream1:Event Name")
    }

    // MARK: - TTL expiry

    func test_expiresEntriesAfterTTL() {
        let spec = AvoEventSpecResponse()
        cache.set("key1", spec: spec)

        // Access the internal cache entry and backdate its timestamp by 61 seconds
        // to simulate TTL expiry (TTL is 60s).
        // We use KVC-like access via the cache's internal dictionary.
        // Since cache property is private, we test expiry indirectly by waiting
        // or by using a workaround.
        // The ObjC test backdated entry.timestamp by 61000ms.
        // We'll use reflection to access the private cache dict.
        let mirror = Mirror(reflecting: cache!)
        for child in mirror.children {
            if child.label == "cache",
               let internalCache = child.value as? [String: AvoEventSpecCacheEntry] {
                if let entry = internalCache["key1"] {
                    entry.timestamp = entry.timestamp - 61_000
                }
            }
        }

        XCTAssertFalse(cache.contains("key1"), "Entry should be expired after TTL")
        XCTAssertNil(cache.get("key1"), "Expired entry should return nil")
        XCTAssertEqual(cache.size(), 0, "Expired entry should be removed on access")
    }

    // MARK: - Max entries eviction

    func test_evictsOldestEntry_whenMaxCacheSizeExceeded() {
        let spec = AvoEventSpecResponse()

        // Fill cache to max size (50)
        for i in 0..<50 {
            cache.set("key\(i)", spec: spec)
        }
        XCTAssertEqual(cache.size(), 50)

        // Backdate key0 to make it the oldest via lastAccessed
        let mirror = Mirror(reflecting: cache!)
        for child in mirror.children {
            if child.label == "cache",
               let internalCache = child.value as? [String: AvoEventSpecCacheEntry] {
                if let entry = internalCache["key0"] {
                    entry.lastAccessed = entry.lastAccessed - 10_000
                }
            }
        }

        // Add one more entry to trigger eviction
        cache.set("key50", spec: spec)

        XCTAssertFalse(cache.contains("key0"), "Oldest entry (key0) should have been evicted")
        XCTAssertTrue(cache.contains("key1"), "key1 should still exist")
        XCTAssertTrue(cache.contains("key50"), "Newly added key50 should exist")
        XCTAssertEqual(cache.size(), 50)
    }
}
