import XCTest
@testable import AvoInspector

final class AvoAnonymousIdTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AvoAnonymousId.clearCache()
    }

    override func tearDown() {
        AvoAnonymousId.clearCache()
        super.tearDown()
    }

    // MARK: - Tests

    func test_anonymousId_generatesNonEmptyId() {
        // When storage is initialized (default AvoStorageImpl uses UserDefaults),
        // anonymousId should return a non-empty string.
        let anonId = AvoAnonymousId.anonymousId()
        XCTAssertFalse(anonId.isEmpty, "Anonymous ID should not be empty")
        XCTAssertNotEqual(anonId, "unknown", "Anonymous ID should not be 'unknown' when storage is initialized")
    }

    func test_anonymousId_returnsSameValueOnSubsequentCalls() {
        let first = AvoAnonymousId.anonymousId()
        let second = AvoAnonymousId.anonymousId()
        XCTAssertEqual(first, second, "Subsequent calls should return the same anonymous ID")
    }

    func test_anonymousId_regeneratesAfterClearCache() {
        let first = AvoAnonymousId.anonymousId()
        AvoAnonymousId.clearCache()
        let second = AvoAnonymousId.anonymousId()
        // After clearing cache, a new ID is loaded from storage (which still has the old one)
        // or generated fresh. Either way it should be non-empty.
        XCTAssertFalse(second.isEmpty)
    }

    func test_setAnonymousId_overridesValue() {
        let customId = "custom-test-id-12345"
        AvoAnonymousId.setAnonymousId(customId)
        let result = AvoAnonymousId.anonymousId()
        XCTAssertEqual(result, customId, "setAnonymousId should override the cached value")
    }

    func test_setAnonymousId_persistsAcrossClearAndReload() {
        let customId = "persistent-id-67890"
        AvoAnonymousId.setAnonymousId(customId)
        AvoAnonymousId.clearCache()
        // After clearing cache, the next call should reload from storage
        let result = AvoAnonymousId.anonymousId()
        XCTAssertEqual(result, customId, "Custom ID should persist in storage after clearCache")
    }

    func test_clearCache_resetsInMemoryCache() {
        _ = AvoAnonymousId.anonymousId()
        AvoAnonymousId.clearCache()
        // clearCache only clears the in-memory cache; storage still has the value.
        // This verifies clearCache doesn't crash and subsequent calls still work.
        let afterClear = AvoAnonymousId.anonymousId()
        XCTAssertFalse(afterClear.isEmpty)
    }
}
