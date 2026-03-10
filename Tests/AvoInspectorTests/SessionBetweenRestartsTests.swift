import XCTest
@testable import AvoInspector

final class SessionBetweenRestartsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
    }

    override func tearDown() {
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
        super.tearDown()
    }

    func test_eventsPersistedBetweenSessions() {
        let originalBatchSize = AvoInspector.getBatchSize()
        defer { AvoInspector.setBatchSize(originalBatchSize) }
        // Set large batch size to prevent auto-sending during the test
        AvoInspector.setBatchSize(1000)

        let mockHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")

        // Session 1: track events and go to background
        let batcher1 = AvoBatcher(networkCallsHandler: mockHandler)
        batcher1.enterForeground()
        batcher1.handleTrackSchema("Event1", schema: [:], eventId: nil, eventHash: nil)
        batcher1.handleTrackSchema("Event2", schema: [:], eventId: nil, eventHash: nil)
        batcher1.enterBackground()

        // Verify events were saved
        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNotNil(cached, "Events should be persisted to UserDefaults on background")

        // Session 2: new batcher instance enters foreground and should restore events
        let mockHandler2 = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let batcher2 = AvoBatcher(networkCallsHandler: mockHandler2)
        batcher2.enterForeground()

        // The second batcher should have attempted to send the persisted events
        XCTAssertGreaterThanOrEqual(mockHandler2.callInspectorCallCount, 1,
                                     "Should post persisted events when new session starts")
    }

    func test_cacheIsClearedAfterSuccessfulUpload() {
        // Pre-populate cache
        let cacheEntry: [Any] = [["type": "event", "eventName": "persistedEvent"]]
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.set(cacheEntry, forKey: AvoBatcher.cacheKey)

        let mockHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        mockHandler.callInspectorCompletionError = nil

        let batcher = AvoBatcher(networkCallsHandler: mockHandler)
        batcher.enterForeground()

        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNil(cached, "Cache should be cleared after successful upload")
    }

    func test_noCacheWrittenIfNoEvents() {
        let mockHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")

        let batcher = AvoBatcher(networkCallsHandler: mockHandler)
        batcher.enterForeground()
        // Don't track any events
        batcher.enterBackground()

        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNil(cached, "Should not write cache when there are no events")
    }

    func test_eventsPersistAcrossMultipleBackgroundForegroundCycles() {
        // Set large batch size to prevent auto-sending during the test
        AvoInspector.setBatchSize(1000)

        let mockHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        // Simulate failure so events remain
        mockHandler.callInspectorCompletionError = NSError(domain: "test", code: 1)

        let batcher = AvoBatcher(networkCallsHandler: mockHandler)
        batcher.enterForeground()

        batcher.handleTrackSchema("Event1", schema: [:], eventId: nil, eventHash: nil)
        batcher.enterBackground()

        // Events should be in cache after background
        let cached1 = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey) as? [Any]
        XCTAssertNotNil(cached1, "Events should be cached after first background")

        // Enter foreground again (will try to send, fail, put back)
        batcher.enterForeground()

        // Add more events
        batcher.handleTrackSchema("Event2", schema: [:], eventId: nil, eventHash: nil)
        batcher.enterBackground()

        let cached2 = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey) as? [Any]
        XCTAssertNotNil(cached2, "Events should still be cached after second background")
    }
}
