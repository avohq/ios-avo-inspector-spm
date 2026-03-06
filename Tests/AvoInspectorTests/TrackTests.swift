import XCTest
@testable import AvoInspector

// MARK: - Test Doubles

class MockNetworkCallsHandler: AvoNetworkCallsHandler {
    var callInspectorCallCount = 0
    var lastBatchBody: [Any]?
    var callInspectorCompletionError: Error? = nil

    var reportValidatedEventCallCount = 0
    var lastReportedValidatedEventBody: [String: Any]?

    override func callInspectorWithBatchBody(_ batchBody: [Any],
                                              completionHandler: @escaping (Error?) -> Void) {
        callInspectorCallCount += 1
        lastBatchBody = batchBody
        completionHandler(callInspectorCompletionError)
    }

    override func reportValidatedEvent(_ body: [String: Any]) {
        reportValidatedEventCallCount += 1
        lastReportedValidatedEventBody = body
    }
}

class MockBatcher: AvoBatcher {
    var handleTrackSchemaCallCount = 0
    var lastEventName: String?
    var lastSchema: [String: AvoEventSchemaType]?
    var lastEventId: String?
    var lastEventHash: String?

    var handleTrackSchemaWithPropsCallCount = 0
    var lastEventProperties: [String: Any]?

    override func handleTrackSchema(_ eventName: String,
                                     schema: [String: AvoEventSchemaType],
                                     eventId: String?,
                                     eventHash: String?) {
        handleTrackSchemaCallCount += 1
        lastEventName = eventName
        lastSchema = schema
        lastEventId = eventId
        lastEventHash = eventHash
    }

    override func handleTrackSchema(_ eventName: String,
                                     schema: [String: AvoEventSchemaType],
                                     eventId: String?,
                                     eventHash: String?,
                                     eventProperties: [String: Any]?) {
        handleTrackSchemaWithPropsCallCount += 1
        lastEventName = eventName
        lastSchema = schema
        lastEventId = eventId
        lastEventHash = eventHash
        lastEventProperties = eventProperties
    }
}

class BranchChangingFetcher: AvoEventSpecFetcher {
    var currentResponse: AvoEventSpecResponse?
    var fetchCallCount = 0

    init(firstResponse: AvoEventSpecResponse?) {
        self.currentResponse = firstResponse
        super.init(timeout: 5.0, env: "dev")
    }

    override func fetchEventSpec(_ params: AvoFetchEventSpecParams,
                                  completion: @escaping AvoEventSpecFetchCompletion) {
        fetchCallCount += 1
        completion(currentResponse)
    }
}

class MockEventSpecFetcher: AvoEventSpecFetcher {
    var stubbedResponse: AvoEventSpecResponse?
    var fetchCallCount = 0

    init(stubbedResponse: AvoEventSpecResponse?) {
        self.stubbedResponse = stubbedResponse
        super.init(timeout: 5.0, env: "dev")
    }

    override func fetchEventSpec(_ params: AvoFetchEventSpecParams,
                                  completion: @escaping AvoEventSpecFetchCompletion) {
        fetchCallCount += 1
        completion(stubbedResponse)
    }
}

class MockEventSpecCache: AvoEventSpecCache {
    private var store = [String: AvoEventSpecResponse?]()
    var setCallCount = 0
    var clearCallCount = 0

    func prePopulate(_ key: String, spec: AvoEventSpecResponse?) {
        store[key] = spec
    }

    override func contains(_ key: String) -> Bool {
        return store.keys.contains(key)
    }

    override func get(_ key: String) -> AvoEventSpecResponse? {
        guard let entry = store[key] else { return nil }
        return entry
    }

    override func set(_ key: String, spec: AvoEventSpecResponse?) {
        setCallCount += 1
        store[key] = spec
    }

    override func clear() {
        clearCallCount += 1
        store.removeAll()
    }

    override func size() -> Int {
        return store.count
    }
}

// MARK: - Helpers

private class MockStorage: NSObject, AvoStorage {
    func isInitialized() -> Bool { return true }
    func getItem(_ key: String) -> String? { return nil }
    func setItem(_ key: String, _ value: String) {}
}

private func makeTestInspector(env: AvoInspectorEnv = .prod,
                                mockBatcher: MockBatcher? = nil,
                                mockNetworkHandler: MockNetworkCallsHandler? = nil,
                                mockFetcher: MockEventSpecFetcher? = nil,
                                mockCache: MockEventSpecCache? = nil) -> (AvoInspector, MockBatcher, MockNetworkCallsHandler) {
    let networkHandler = mockNetworkHandler ?? MockNetworkCallsHandler(
        apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
        libVersion: "4.0.0", env: Int(env.rawValue), endpoint: "https://test.proxy")
    let batcher = mockBatcher ?? MockBatcher(networkCallsHandler: networkHandler)
    let deduplicator = AvoDeduplicator()
    deduplicator.clear()

    let sut = AvoInspector(
        apiKey: "testApiKey", env: env, storage: MockStorage(),
        networkCallsHandler: networkHandler,
        batcher: batcher,
        deduplicator: deduplicator,
        eventSpecFetcher: mockFetcher,
        eventSpecCache: mockCache)
    return (sut, batcher, networkHandler)
}

// MARK: - TrackTests

final class TrackTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AvoDeduplicator.sharedDeduplicator.clear()
    }

    // MARK: - Basic tracking tests (ported from ObjC)

    func test_batcherInvoked_whenTrackSchemaFromEvent() {
        let (sut, batcher, _) = makeTestInspector()

        _ = sut.trackSchema(fromEvent: "Event name", eventParams: [:])

        // In prod mode with no fetcher, falls through to batcher
        XCTAssertEqual(batcher.handleTrackSchemaCallCount, 1)
        XCTAssertEqual(batcher.lastEventName, "Event name")
    }

    func test_batcherInvoked_whenTrackSchema() {
        let (sut, batcher, _) = makeTestInspector()

        sut.trackSchema("Event name", eventSchema: [:])

        XCTAssertEqual(batcher.handleTrackSchemaCallCount, 1)
        XCTAssertEqual(batcher.lastEventName, "Event name")
        XCTAssertNil(batcher.lastEventId)
        XCTAssertNil(batcher.lastEventHash)
    }

    func test_avoFunctionTrackSchemaFromEvent_extractsEventIdAndHash() {
        let (sut, batcher, _) = makeTestInspector(env: .dev)

        let params = NSMutableDictionary()
        params["avoFunctionEventId"] = "testEventId"
        params["avoFunctionEventHash"] = "testEventHash"
        params["normalParam"] = "value"

        _ = sut.avoFunctionTrackSchemaFromEvent("Event name", eventParams: params)

        // The batcher should have been called (falls through to batcher in prod-like path)
        // Check that eventId and eventHash were extracted and forwarded
        let totalCalls = batcher.handleTrackSchemaCallCount + batcher.handleTrackSchemaWithPropsCallCount
        XCTAssertGreaterThan(totalCalls, 0, "Batcher should have been called")

        // Check that the event ID and hash were extracted
        XCTAssertEqual(batcher.lastEventId, "testEventId")
        XCTAssertEqual(batcher.lastEventHash, "testEventHash")
    }

    // MARK: - Validation flow tests

    func test_fetchAndValidate_cacheHit_validSpec_sendsValidatedEvent() {
        let mockCache = MockEventSpecCache()
        let mockNetworkHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let mockBatcher = MockBatcher(networkCallsHandler: mockNetworkHandler)
        let mockFetcher = MockEventSpecFetcher(stubbedResponse: nil)

        // Create a valid spec response
        let specResponse = makeValidSpecResponse(eventName: "TestEvent")

        // Generate the cache key that the inspector will use
        let streamId = AvoAnonymousId.anonymousId()
        let cacheKey = AvoEventSpecCache.generateKey("testApiKey", streamId: streamId, eventName: "TestEvent")
        mockCache.prePopulate(cacheKey, spec: specResponse)

        let deduplicator = AvoDeduplicator()
        deduplicator.clear()

        let sut = AvoInspector(
            apiKey: "testApiKey", env: .dev, storage: MockStorage(),
            networkCallsHandler: mockNetworkHandler,
            batcher: mockBatcher,
            deduplicator: deduplicator,
            eventSpecFetcher: mockFetcher,
            eventSpecCache: mockCache)

        _ = sut.trackSchema(fromEvent: "TestEvent", eventParams: ["prop": "value"])

        // Should have sent via reportValidatedEvent, not through the batcher
        XCTAssertEqual(mockNetworkHandler.reportValidatedEventCallCount, 1)
        XCTAssertEqual(mockBatcher.handleTrackSchemaCallCount, 0)
        XCTAssertEqual(mockBatcher.handleTrackSchemaWithPropsCallCount, 0)
    }

    func test_fetchAndValidate_cacheHit_nilSpec_fallsThroughToBatcher() {
        let mockCache = MockEventSpecCache()
        let mockNetworkHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let mockBatcher = MockBatcher(networkCallsHandler: mockNetworkHandler)
        let mockFetcher = MockEventSpecFetcher(stubbedResponse: nil)

        // Pre-populate cache with nil spec
        let streamId = AvoAnonymousId.anonymousId()
        let cacheKey = AvoEventSpecCache.generateKey("testApiKey", streamId: streamId, eventName: "TestEvent")
        mockCache.prePopulate(cacheKey, spec: nil)

        let deduplicator = AvoDeduplicator()
        deduplicator.clear()

        let sut = AvoInspector(
            apiKey: "testApiKey", env: .dev, storage: MockStorage(),
            networkCallsHandler: mockNetworkHandler,
            batcher: mockBatcher,
            deduplicator: deduplicator,
            eventSpecFetcher: mockFetcher,
            eventSpecCache: mockCache)

        _ = sut.trackSchema(fromEvent: "TestEvent", eventParams: ["prop": "value"])

        // Should fall through to batcher
        let batcherCalls = mockBatcher.handleTrackSchemaCallCount + mockBatcher.handleTrackSchemaWithPropsCallCount
        XCTAssertGreaterThan(batcherCalls, 0, "Should fall through to batcher when cache has nil spec")
        XCTAssertEqual(mockNetworkHandler.reportValidatedEventCallCount, 0)
    }

    func test_fetchAndValidate_cacheMiss_fetchSuccess_sendsValidatedEvent() {
        let mockCache = MockEventSpecCache()
        let specResponse = makeValidSpecResponse(eventName: "TestEvent")
        let mockNetworkHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let mockBatcher = MockBatcher(networkCallsHandler: mockNetworkHandler)
        let mockFetcher = MockEventSpecFetcher(stubbedResponse: specResponse)

        let deduplicator = AvoDeduplicator()
        deduplicator.clear()

        let sut = AvoInspector(
            apiKey: "testApiKey", env: .dev, storage: MockStorage(),
            networkCallsHandler: mockNetworkHandler,
            batcher: mockBatcher,
            deduplicator: deduplicator,
            eventSpecFetcher: mockFetcher,
            eventSpecCache: mockCache)

        _ = sut.trackSchema(fromEvent: "TestEvent", eventParams: ["prop": "value"])

        // Fetcher should have been called
        XCTAssertEqual(mockFetcher.fetchCallCount, 1)
        // Spec should have been cached
        XCTAssertGreaterThan(mockCache.setCallCount, 0)
        // Should have sent validated event
        XCTAssertEqual(mockNetworkHandler.reportValidatedEventCallCount, 1)
    }

    func test_fetchAndValidate_cacheMiss_fetchFailure_fallsThroughToBatcher() {
        let mockCache = MockEventSpecCache()
        let mockNetworkHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let mockBatcher = MockBatcher(networkCallsHandler: mockNetworkHandler)
        // Fetcher returns nil (failure)
        let mockFetcher = MockEventSpecFetcher(stubbedResponse: nil)

        let deduplicator = AvoDeduplicator()
        deduplicator.clear()

        let sut = AvoInspector(
            apiKey: "testApiKey", env: .dev, storage: MockStorage(),
            networkCallsHandler: mockNetworkHandler,
            batcher: mockBatcher,
            deduplicator: deduplicator,
            eventSpecFetcher: mockFetcher,
            eventSpecCache: mockCache)

        _ = sut.trackSchema(fromEvent: "TestEvent", eventParams: ["prop": "value"])

        // Fetcher should have been called
        XCTAssertEqual(mockFetcher.fetchCallCount, 1)
        // Nil should have been cached
        XCTAssertGreaterThan(mockCache.setCallCount, 0)
        // Should fall through to batcher
        let batcherCalls = mockBatcher.handleTrackSchemaCallCount + mockBatcher.handleTrackSchemaWithPropsCallCount
        XCTAssertGreaterThan(batcherCalls, 0, "Should fall through to batcher on fetch failure")
        XCTAssertEqual(mockNetworkHandler.reportValidatedEventCallCount, 0)
    }

    func test_fetchAndValidate_branchChange_clearsCache() {
        let mockCache = MockEventSpecCache()

        // Fetcher will return specs - first call gets branchA, second gets branchB
        let specA = makeValidSpecResponse(eventName: "Event1", branchId: "branchA")
        let mockNetworkHandler = MockNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0",
            libVersion: "4.0.0", env: 1, endpoint: "https://test.proxy")
        let mockBatcher = MockBatcher(networkCallsHandler: mockNetworkHandler)

        // Use a fetcher that changes response between calls
        let mockFetcher = BranchChangingFetcher(firstResponse: specA)

        let deduplicator = AvoDeduplicator()
        deduplicator.clear()

        let sut = AvoInspector(
            apiKey: "testApiKey", env: .dev, storage: MockStorage(),
            networkCallsHandler: mockNetworkHandler,
            batcher: mockBatcher,
            deduplicator: deduplicator,
            eventSpecFetcher: mockFetcher,
            eventSpecCache: mockCache)

        // First call: cache miss -> fetch returns branchA -> sets currentBranchId
        _ = sut.trackSchema(fromEvent: "Event1", eventParams: ["prop": "value"])

        XCTAssertEqual(mockFetcher.fetchCallCount, 1)

        // Now change the fetcher's response to branchB
        let specB = makeValidSpecResponse(eventName: "Event2", branchId: "branchB")
        mockFetcher.currentResponse = specB

        let clearCountBefore = mockCache.clearCallCount

        // Second call: cache miss -> fetch returns branchB -> detects branch change -> clears cache
        _ = sut.trackSchema(fromEvent: "Event2", eventParams: ["prop": "value"])

        XCTAssertEqual(mockFetcher.fetchCallCount, 2)
        // Cache should have been cleared due to branch change
        XCTAssertGreaterThan(mockCache.clearCallCount, clearCountBefore,
                             "Cache should be cleared when branch changes")
    }

    func test_fetchAndValidate_noFetcher_fallsThroughToBatcher() {
        // Prod env does not create a fetcher
        let (sut, batcher, networkHandler) = makeTestInspector(env: .prod)

        _ = sut.trackSchema(fromEvent: "TestEvent", eventParams: ["prop": "value"])

        // Should go directly to batcher
        let batcherCalls = batcher.handleTrackSchemaCallCount + batcher.handleTrackSchemaWithPropsCallCount
        XCTAssertGreaterThan(batcherCalls, 0, "Should fall through to batcher when no fetcher")
        XCTAssertEqual(networkHandler.reportValidatedEventCallCount, 0)
    }

    // MARK: - Helpers

    private func makeValidSpecResponse(eventName: String, branchId: String = "testBranch") -> AvoEventSpecResponse {
        let wireDict: [String: Any] = [
            "events": [
                [
                    "b": branchId,
                    "id": "event123",
                    "vids": ["v1", "v2"],
                    "p": [
                        "prop": [
                            "t": "string",
                            "r": true
                        ]
                    ]
                ]
            ],
            "metadata": [
                "schemaId": "schema123",
                "branchId": branchId,
                "latestActionId": "action123"
            ]
        ]
        let wire = AvoEventSpecResponseWire(dictionary: wireDict)
        return AvoEventSpecResponse(fromWire: wire)
    }
}
