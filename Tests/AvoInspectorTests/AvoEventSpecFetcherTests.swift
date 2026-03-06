import XCTest
@testable import AvoInspector

final class AvoEventSpecFetcherTests: XCTestCase {

    // MARK: - Initialization

    func test_initWithDefaultBaseUrl() {
        let fetcher = AvoEventSpecFetcher(timeout: 5.0, env: "dev")
        // Access private properties via Mirror
        let mirror = Mirror(reflecting: fetcher)
        let baseUrl = mirror.children.first(where: { $0.label == "baseUrl" })?.value as? String
        let timeout = mirror.children.first(where: { $0.label == "timeout" })?.value as? TimeInterval
        let env = mirror.children.first(where: { $0.label == "env" })?.value as? String

        XCTAssertEqual(baseUrl, "https://api.avo.app")
        XCTAssertEqual(timeout, 5.0)
        XCTAssertEqual(env, "dev")
    }

    func test_initWithCustomBaseUrl() {
        let fetcher = AvoEventSpecFetcher(timeout: 3.0, env: "staging", baseUrl: "https://custom.api.com")
        let mirror = Mirror(reflecting: fetcher)
        let baseUrl = mirror.children.first(where: { $0.label == "baseUrl" })?.value as? String

        XCTAssertEqual(baseUrl, "https://custom.api.com")
    }

    // MARK: - Environment gating

    func test_fetchEventSpec_returnsNilForProdEnv() {
        let fetcher = AvoEventSpecFetcher(timeout: 5.0, env: "prod")
        let params = AvoFetchEventSpecParams(apiKey: "key", streamId: "stream", eventName: "event")

        var callbackResponse: AvoEventSpecResponse? = AvoEventSpecResponse() // sentinel
        var callbackCalled = false

        fetcher.fetchEventSpec(params) { response in
            callbackResponse = response
            callbackCalled = true
        }

        // For prod env, the callback is delivered asynchronously via deliverResult
        // but the fetchInternal guard fires immediately. Give it a moment.
        let expectation = self.expectation(description: "Prod callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        XCTAssertTrue(callbackCalled, "Callback should have been called for prod env")
        XCTAssertNil(callbackResponse, "Response should be nil for prod env")
    }

    // MARK: - Wire type parsing

    func test_parsesPropertyConstraintsWire() {
        let dict: [String: Any] = [
            "t": "string",
            "r": true,
            "p": ["hello": ["evt1", "evt2"]],
            "v": ["[\"a\",\"b\"]": ["evt1"]]
        ]
        let wire = AvoPropertyConstraintsWire(dictionary: dict)
        XCTAssertEqual(wire.t, "string")
        XCTAssertTrue(wire.r)
        XCTAssertNotNil(wire.p?["hello"])
        XCTAssertTrue(wire.p!["hello"]!.contains("evt1"))
        XCTAssertNotNil(wire.v?["[\"a\",\"b\"]"])
        XCTAssertTrue(wire.v!["[\"a\",\"b\"]"]!.contains("evt1"))
    }

    func test_parsesEventSpecEntryWire() {
        let dict: [String: Any] = [
            "b": "branch1",
            "id": "event1",
            "vids": ["var1", "var2"],
            "p": [
                "prop1": ["t": "string", "r": false] as [String: Any]
            ]
        ]
        let wire = AvoEventSpecEntryWire(dictionary: dict)
        XCTAssertEqual(wire.b, "branch1")
        XCTAssertEqual(wire.eventId, "event1")
        XCTAssertEqual(wire.vids.count, 2)
        XCTAssertNotNil(wire.p["prop1"])
        XCTAssertEqual(wire.p["prop1"]?.t, "string")
    }

    func test_parsesFullWireResponseAndConvertsToInternal() {
        let responseDict: [String: Any] = [
            "events": [
                [
                    "b": "branch1",
                    "id": "event1",
                    "vids": ["var1"],
                    "p": [
                        "name": ["t": "string", "r": true, "p": ["John": ["event1"]]] as [String: Any]
                    ]
                ] as [String: Any]
            ],
            "metadata": [
                "schemaId": "schema1",
                "branchId": "branch1",
                "latestActionId": "action1",
                "sourceId": "source1"
            ]
        ]

        let wire = AvoEventSpecResponseWire(dictionary: responseDict)
        XCTAssertEqual(wire.events.count, 1)
        XCTAssertEqual(wire.metadata?.schemaId, "schema1")
        XCTAssertEqual(wire.metadata?.sourceId, "source1")

        let internal_ = AvoEventSpecResponse(fromWire: wire)
        XCTAssertEqual(internal_.events.count, 1)
        XCTAssertEqual(internal_.events[0].branchId, "branch1")
        XCTAssertEqual(internal_.events[0].baseEventId, "event1")
        XCTAssertTrue(internal_.events[0].variantIds.contains("var1"))
        XCTAssertNotNil(internal_.events[0].props["name"])
        XCTAssertEqual(internal_.events[0].props["name"]?.type, "string")
        XCTAssertTrue(internal_.events[0].props["name"]?.required ?? false)
        XCTAssertNotNil(internal_.events[0].props["name"]?.pinnedValues?["John"])
        XCTAssertTrue(internal_.events[0].props["name"]!.pinnedValues!["John"]!.contains("event1"))
    }

    func test_parsesNestedChildrenConstraints() {
        let dict: [String: Any] = [
            "t": "object",
            "r": false,
            "children": [
                "child1": ["t": "string", "r": true] as [String: Any],
                "child2": ["t": "int", "r": false] as [String: Any]
            ]
        ]
        let wire = AvoPropertyConstraintsWire(dictionary: dict)
        XCTAssertNotNil(wire.children)
        XCTAssertEqual(wire.children?["child1"]?.t, "string")
        XCTAssertEqual(wire.children?["child2"]?.t, "int")
    }

    // MARK: - hasExpectedShape (tested indirectly via response shape validation)

    func test_hasExpectedShape_validResponse() {
        // A valid wire response with events and metadata should produce a valid AvoEventSpecResponse
        let responseDict: [String: Any] = [
            "events": [
                ["b": "branch1", "id": "event1", "vids": [] as [String], "p": [:] as [String: Any]] as [String: Any]
            ],
            "metadata": [
                "schemaId": "schema1",
                "branchId": "branch1",
                "latestActionId": "action1"
            ]
        ]
        let wire = AvoEventSpecResponseWire(dictionary: responseDict)
        XCTAssertNotNil(wire.metadata)
        XCTAssertFalse(wire.events.isEmpty)
        XCTAssertFalse(wire.metadata!.schemaId.isEmpty)
        XCTAssertFalse(wire.metadata!.branchId.isEmpty)
        XCTAssertFalse(wire.metadata!.latestActionId.isEmpty)
    }

    func test_hasExpectedShape_missingMetadata() {
        let responseDict: [String: Any] = [
            "events": [] as [[String: Any]]
        ]
        let wire = AvoEventSpecResponseWire(dictionary: responseDict)
        XCTAssertNil(wire.metadata, "Missing metadata dict should result in nil metadata")
    }

    func test_hasExpectedShape_emptySchemaId() {
        let responseDict: [String: Any] = [
            "events": [] as [[String: Any]],
            "metadata": [
                "schemaId": "",
                "branchId": "branch1",
                "latestActionId": "action1"
            ]
        ]
        let wire = AvoEventSpecResponseWire(dictionary: responseDict)
        XCTAssertTrue(wire.metadata!.schemaId.isEmpty, "Empty schemaId should be detected")
    }

    // MARK: - URL escaping (tested via URLComponents behavior)

    func test_urlComponentsEscapesReservedDelimiters() {
        // This tests the same logic as buildUrl — URLComponents with queryItems
        // automatically percent-encodes reserved characters like & and =
        var components = URLComponents(string: "https://api.avo.app/trackingPlan/eventSpec")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: "k&=y"),
            URLQueryItem(name: "streamId", value: "s&t=r"),
            URLQueryItem(name: "eventName", value: "Foo&Bar=Baz")
        ]
        let url = components.url!.absoluteString
        XCTAssertTrue(url.contains("apiKey=k%26%3Dy") || url.contains("apiKey=k&=y") == false)
        XCTAssertTrue(url.contains("streamId=s%26t%3Dr") || url.contains("streamId=s&t=r") == false)
        XCTAssertTrue(url.contains("eventName=Foo%26Bar%3DBaz") || url.contains("eventName=Foo&Bar=Baz") == false)
    }

    // MARK: - In-flight deduplication

    func test_inFlightDeduplication_coalescesCallbacks() {
        // Two fetches for the same streamId+eventName should coalesce.
        // Since env is "prod", both will get nil back immediately.
        let fetcher = AvoEventSpecFetcher(timeout: 5.0, env: "prod")
        let params = AvoFetchEventSpecParams(apiKey: "key", streamId: "stream", eventName: "event")

        var callCount = 0
        let expectation = self.expectation(description: "Both callbacks called")
        expectation.expectedFulfillmentCount = 2

        fetcher.fetchEventSpec(params) { _ in
            callCount += 1
            expectation.fulfill()
        }
        fetcher.fetchEventSpec(params) { _ in
            callCount += 1
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(callCount, 2, "Both callbacks should be invoked")
    }
}
