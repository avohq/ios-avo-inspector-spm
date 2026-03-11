import XCTest
@testable import AvoInspector

final class ListSchemaExtractionTests: XCTestCase {

    private var sut: AvoInspector!

    override func setUp() {
        super.setUp()
        sut = AvoInspector(apiKey: "api key", env: .dev)
    }

    func test_extractArray() {
        let params: [String: Any] = ["array key": ["test", 42] as [Any]]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["array key"] is AvoList)
    }

    func test_extractSingleObjectArray() {
        let params: [String: Any] = ["array key": ["test"]]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["array key"] is AvoList)
    }

    func test_extractSingleObjectSet() {
        let set = NSSet(array: [""])
        let params: [String: Any] = ["set key": set]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["set key"] is AvoList)
    }

    func test_extractMultipleObjectSet() {
        let set = NSSet(objects: "1", NSNumber(value: 42))
        let params: [String: Any] = ["set key": set]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["set key"] is AvoList)
    }

    func test_extractMutableArray() {
        let mutableArray = NSMutableArray()
        mutableArray.add("test")
        mutableArray.add(42)
        let params: [String: Any] = ["mutable array key": mutableArray]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["mutable array key"] is AvoList)
    }

    func test_extractMutableSingleObjectArray() {
        let mutableArray = NSMutableArray()
        mutableArray.add("test")
        let params: [String: Any] = ["mutable array key": mutableArray]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["mutable array key"] is AvoList)
    }

    func test_extractStringSubtypeArray() {
        let params: [String: Any] = ["string array key": ["Hello world"]]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["string array key"]?.name(), "list(string)")
    }

    func test_doNotDuplicateTypesInName() {
        let params: [String: Any] = ["string array key": [["Hello world"], ["Give me a sign"]]]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["string array key"]?.name(), "list(list(string))")
    }

    func test_extractNullableStringSubtypeArray() {
        let array: [Any] = ["Hello world", NSNull()]
        let params: [String: Any] = ["string array key": array]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["string array key"]?.name(), "list(string|null)")
    }

    func test_extractNullableStringIntFloatBooleanSubtypeArray() {
        // Nondeterministic iteration order in NSMutableSet means we use set-based assertions
        let array: [Any] = ["Hello world", NSNull(), NSNumber(value: 42),
                            NSNumber(value: Float(41.1)), NSNumber(value: true)]
        let params: [String: Any] = ["string array key": array]
        let schema = sut.extractSchema(params)

        let propertyType = schema["string array key"]?.name() ?? ""
        XCTAssertTrue(propertyType.hasPrefix("list("))
        XCTAssertTrue(propertyType.contains("int"))
        XCTAssertTrue(propertyType.contains("float"))
        XCTAssertTrue(propertyType.contains("boolean"))
        XCTAssertTrue(propertyType.contains("string"))
        XCTAssertTrue(propertyType.contains("null"))
    }

    func test_extractDoubleSubtypeArray() {
        let array: [Any] = [NSNumber(value: 41.1 as Double)]
        let params: [String: Any] = ["string array key": array]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["string array key"]?.name(), "list(float)")
    }

    // MARK: - Single-element collection (private NSArray subclass)

    func test_singleElementArrayProducesAvoList() {
        // Single-element NSArray may use a private __NSSingleObjectArrayI subclass
        let params: [String: Any] = ["key": [42]]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["key"] is AvoList)
        XCTAssertEqual(schema["key"]?.name(), "list(int)")
    }
}
