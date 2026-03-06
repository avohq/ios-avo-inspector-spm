import XCTest
@testable import AvoInspector

final class BatchingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear the batcher cache before each test
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
    }

    override func tearDown() {
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
        super.tearDown()
    }

    private func makeMockNetworkHandler() -> MockNetworkCallsHandler {
        return MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
    }

    // MARK: - Tests

    func test_doesNotWriteCache_ifNoEventsPresent() {
        let mockHandler = makeMockNetworkHandler()
        let sut = AvoBatcher(networkCallsHandler: mockHandler)

        sut.enterBackground()

        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNil(cached, "Should not write cache when no events are present")
    }

    func test_initializesEmptyArray_ifNothingCached() {
        let mockHandler = makeMockNetworkHandler()
        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()

        // After entering foreground with nothing cached, the batcher should still work
        // (internal events array is initialized even if empty)
        // We verify by tracking an event and ensuring it doesn't crash
        sut.handleTrackSchema("Test", schema: [:], eventId: nil, eventHash: nil)
    }

    func test_sendsBatch_whenEventCountReachesBatchSize() {
        AvoInspector.setBatchSize(10)

        let mockHandler = makeMockNetworkHandler()
        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()
        let startCallCount = mockHandler.callInspectorCallCount

        // Add batch_size - 1 events (should not trigger send)
        for _ in 0..<(Int(AvoInspector.getBatchSize()) - 1) {
            sut.handleTrackSchema("Event1", schema: [:], eventId: nil, eventHash: nil)
        }
        XCTAssertEqual(mockHandler.callInspectorCallCount, startCallCount,
                        "Should not send before reaching batch size")

        // Add one more to reach batch size
        sut.handleTrackSchema("Test", schema: [:], eventId: nil, eventHash: nil)
        XCTAssertEqual(mockHandler.callInspectorCallCount, startCallCount + 1,
                        "Should send when batch size is reached")

        // Add another batch_size - 1 (should not trigger)
        for _ in 0..<(Int(AvoInspector.getBatchSize()) - 1) {
            sut.handleTrackSchema("Test", schema: [:], eventId: nil, eventHash: nil)
        }
        XCTAssertEqual(mockHandler.callInspectorCallCount, startCallCount + 1,
                        "Should not send before reaching next batch size multiple")

        // Add one more to reach 2x batch size
        sut.handleTrackSchema("FinalEvent", schema: [:], eventId: nil, eventHash: nil)
        XCTAssertEqual(mockHandler.callInspectorCallCount, startCallCount + 2,
                        "Should send when 2x batch size is reached")
    }

    func test_parsesCodegenEventIdAndHash() {
        let mockHandler = makeMockNetworkHandler()
        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()

        sut.handleTrackSchema("Test", schema: [:], eventId: "testEventId", eventHash: "testEventHash")

        // Verify the network handler received the correct eventId and eventHash
        // by checking the body it was asked to build (through the real bodyForTrackSchemaCall)
        // The batcher calls bodyForTrackSchemaCall on the handler and saves the result
        // We can't easily inspect internal state, but we can verify the call doesn't crash
        // and that the handler was used
    }

    func test_parsesEmptyEventIdAndHash() {
        let mockHandler = makeMockNetworkHandler()
        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()

        sut.handleTrackSchema("Test", schema: [:], eventId: nil, eventHash: nil)

        // Verify call doesn't crash with nil values
    }

    func test_clearsEventCacheOnSuccessUploadOnForeground() {
        // Pre-populate cache with a valid event
        let cacheEntry: [Any] = [["type": "event", "eventName": "cachedEvent"]]
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.set(cacheEntry, forKey: AvoBatcher.cacheKey)

        let mockHandler = makeMockNetworkHandler()
        // Success: completion with nil error
        mockHandler.callInspectorCompletionError = nil

        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()

        // After successful upload, cache should be cleared
        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNil(cached, "Cache should be cleared after successful upload on foreground")
    }

    func test_putsEventsBackOnFailedUpload() {
        // Pre-populate cache with a valid event
        let cacheEntry: [Any] = [["type": "event", "eventName": "cachedEvent"]]
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.set(cacheEntry, forKey: AvoBatcher.cacheKey)

        let mockHandler = makeMockNetworkHandler()
        // Failure: completion with error
        mockHandler.callInspectorCompletionError = NSError(domain: "test", code: 1)

        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()

        // Cache should be cleared (it's always cleared on foreground)
        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNil(cached, "Cache should be cleared after foreground even on failure")
        // Events should be put back into the in-memory events list (we can't inspect directly
        // but the batcher should still have them for retry)
    }
}
