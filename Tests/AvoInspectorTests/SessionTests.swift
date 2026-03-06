import XCTest
@testable import AvoInspector

final class SessionTests: XCTestCase {

    func test_enterForeground_triggersPostEvents() {
        let mockHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let sut = AvoBatcher(networkCallsHandler: mockHandler)

        // Pre-populate cache with events
        let cacheEntry: [Any] = [["type": "event", "eventName": "cachedEvent"]]
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.set(cacheEntry, forKey: AvoBatcher.cacheKey)

        sut.enterForeground()

        // Should attempt to post the cached events
        XCTAssertGreaterThanOrEqual(mockHandler.callInspectorCallCount, 1,
                                     "Should post cached events on foreground")

        // Cleanup
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
    }

    func test_enterBackground_savesEventsToCache() {
        // Set large batch size to prevent auto-sending during the test
        AvoInspector.setBatchSize(1000)

        let mockHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let sut = AvoBatcher(networkCallsHandler: mockHandler)
        sut.enterForeground()

        // Track some events (large batch size prevents auto-sending)
        sut.handleTrackSchema("Event1", schema: [:], eventId: nil, eventHash: nil)
        sut.handleTrackSchema("Event2", schema: [:], eventId: nil, eventHash: nil)

        sut.enterBackground()

        // Verify events were saved to cache
        let cached = UserDefaults(suiteName: AvoBatcher.suiteKey)?.value(forKey: AvoBatcher.cacheKey)
        XCTAssertNotNil(cached, "Events should be saved to cache on background")

        // Cleanup
        UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
    }

    func test_inspectorEnterForeground_doesNotCrash() {
        let sut = AvoInspector(apiKey: "testApiKey", env: .prod)
        sut.enterForeground()
        // No crash = pass
    }

    func test_inspectorEnterBackground_doesNotCrash() {
        let sut = AvoInspector(apiKey: "testApiKey", env: .prod)
        sut.enterBackground()
        // No crash = pass
    }

    func test_foregroundBackgroundCycle_doesNotCrash() {
        let sut = AvoInspector(apiKey: "testApiKey", env: .prod)
        sut.enterForeground()
        _ = sut.trackSchema(fromEvent: "Test", eventParams: ["key": "value"])
        sut.enterBackground()
        sut.enterForeground()
        _ = sut.trackSchema(fromEvent: "Test2", eventParams: ["key": "value"])
        sut.enterBackground()
        // No crash = pass
    }
}
