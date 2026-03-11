import XCTest
@testable import AvoInspector

final class DeduplicatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AvoDeduplicator.sharedDeduplicator.clear()
    }

    private func makeTestParams() -> [String: Any] {
        let array: [Any] = ["Hello world", NSNull(), NSNumber(value: 42),
                            NSNumber(value: Float(41.1)), NSNumber(value: true)]
        return ["string array key": array]
    }

    // MARK: - shouldRegisterEvent tests

    func test_detectsDuplication_avoFunctionThenManual() {
        let params = makeTestParams()
        let sut = AvoDeduplicator.sharedDeduplicator

        let avoFunctionTrack = sut.shouldRegisterEvent("Test 0", eventParams: params, fromAvoFunction: true)
        let manualTrack = sut.shouldRegisterEvent("Test 0", eventParams: params, fromAvoFunction: false)

        XCTAssertTrue(avoFunctionTrack)
        XCTAssertFalse(manualTrack)
    }

    func test_detectsDuplication_avoFunctionThenSchemaManually() {
        let params = makeTestParams()

        let avoList = AvoList()
        avoList.subtypes.add(AvoString())
        avoList.subtypes.add(AvoNull())
        avoList.subtypes.add(AvoFloat())
        avoList.subtypes.add(AvoInt())
        avoList.subtypes.add(AvoBoolean())

        let testSchema: [String: AvoEventSchemaType] = ["string array key": avoList]

        let sut = AvoDeduplicator.sharedDeduplicator

        let avoFunctionTrack = sut.shouldRegisterEvent("Test 0", eventParams: params, fromAvoFunction: true)
        let manualSchemaTrack = sut.shouldRegisterSchemaFromManually("Test 0", schema: testSchema)

        XCTAssertTrue(avoFunctionTrack)
        XCTAssertFalse(manualSchemaTrack)
    }

    func test_inspectorDeduplicates_avoFunctionThenManual_firstAvoFunction() {
        let params = makeTestParams()
        let sut = AvoInspector(apiKey: "apiKey", env: .dev)

        let avoFunctionTrack = sut.avoFunctionTrackSchemaFromEvent("Test 0", eventParams: NSMutableDictionary(dictionary: params))
        let manualTrack = sut.trackSchema(fromEvent: "Test 0", eventParams: params)
        let avoFunctionTrackAgain = sut.avoFunctionTrackSchemaFromEvent("Test 0", eventParams: NSMutableDictionary(dictionary: params))

        XCTAssertFalse(avoFunctionTrack.isEmpty)
        XCTAssertTrue(manualTrack.isEmpty)
        XCTAssertFalse(avoFunctionTrackAgain.isEmpty)
    }

    func test_inspectorDeduplicates_manualThenAvoFunction_firstManual() {
        let params = makeTestParams()
        let sut = AvoInspector(apiKey: "apiKey", env: .dev)

        let manualTrack = sut.trackSchema(fromEvent: "Test 0", eventParams: params)
        let avoFunctionTrack = sut.avoFunctionTrackSchemaFromEvent("Test 0", eventParams: NSMutableDictionary(dictionary: params))
        let manualTrackAgain = sut.trackSchema(fromEvent: "Test 0", eventParams: params)

        XCTAssertFalse(manualTrack.isEmpty)
        XCTAssertTrue(avoFunctionTrack.isEmpty)
        XCTAssertFalse(manualTrackAgain.isEmpty)
    }

    func test_allowsManualTrack2SameEvents() {
        let params = makeTestParams()
        let sut = AvoDeduplicator.sharedDeduplicator

        let manualTrack = sut.shouldRegisterEvent("Test 2", eventParams: params, fromAvoFunction: false)
        let avoFunctionTrack = sut.shouldRegisterEvent("Test 2", eventParams: params, fromAvoFunction: true)
        let manualTrackAgain = sut.shouldRegisterEvent("Test 2", eventParams: params, fromAvoFunction: false)

        XCTAssertTrue(manualTrack)
        XCTAssertFalse(avoFunctionTrack)
        XCTAssertTrue(manualTrackAgain)
    }

    func test_detectsDuplication_manualThenAvoFunction() {
        let params = makeTestParams()
        let sut = AvoDeduplicator.sharedDeduplicator

        let manualTrack = sut.shouldRegisterEvent("Test 1", eventParams: params, fromAvoFunction: false)
        let avoFunctionTrack = sut.shouldRegisterEvent("Test 1", eventParams: params, fromAvoFunction: true)

        XCTAssertTrue(manualTrack)
        XCTAssertFalse(avoFunctionTrack)
    }

    func test_doesNotDeduplicateAfter300ms() {
        let params = makeTestParams()
        let sut = AvoDeduplicator.sharedDeduplicator

        let avoFunctionTrack = sut.shouldRegisterEvent("Test 1", eventParams: params, fromAvoFunction: true)

        Thread.sleep(forTimeInterval: 0.35)

        let manualTrack = sut.shouldRegisterEvent("Test 1", eventParams: params, fromAvoFunction: false)

        Thread.sleep(forTimeInterval: 0.35)

        let avoFunctionTrackAgain = sut.shouldRegisterEvent("Test 1", eventParams: params, fromAvoFunction: true)

        XCTAssertTrue(avoFunctionTrack)
        XCTAssertTrue(manualTrack)
        XCTAssertTrue(avoFunctionTrackAgain)
    }
}
