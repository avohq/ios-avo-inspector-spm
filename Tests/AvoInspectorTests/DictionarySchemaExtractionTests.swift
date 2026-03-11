import XCTest
@testable import AvoInspector

final class DictionarySchemaExtractionTests: XCTestCase {

    private var sut: AvoInspector!

    override func setUp() {
        super.setUp()
        sut = AvoInspector(apiKey: "api key", env: .dev)
    }

    func test_extractDictionary() {
        let dict: [String: Any] = ["field0": "test", "field1": 42]
        let params: [String: Any] = ["dict key": dict]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["dict key"] is AvoObject)
    }

    func test_extractMutableDictionary() {
        let mutableDict = NSMutableDictionary()
        mutableDict["field0"] = "test"
        mutableDict["field1"] = 42
        let params: [String: Any] = ["mutable dict key": mutableDict]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["mutable dict key"] is AvoObject)
    }

    func test_extractSingleEntryDictionary() {
        let dict: [String: Any] = ["field0": "test"]
        let params: [String: Any] = ["dict key": dict]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["dict key"] is AvoObject)
    }

    func test_extractSingleEntryMutableDictionary() {
        let mutableDict = NSMutableDictionary()
        mutableDict["field0"] = "test"
        let params: [String: Any] = ["mutable dict key": mutableDict]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["mutable dict key"] is AvoObject)
    }

    func test_extractComplexObject() {
        // Use single-element sub-collections to avoid nondeterministic iteration order
        let mutableDict = NSMutableDictionary()
        mutableDict["strKey"] = "Hello world"
        mutableDict["intKey"] = 42

        let params: [String: Any] = ["complex object key": mutableDict]
        let schema = sut.extractSchema(params)

        guard let avoObj = schema["complex object key"] as? AvoObject else {
            XCTFail("Expected AvoObject")
            return
        }

        // Verify individual fields exist with correct types rather than full JSON string
        // (dictionary iteration order is nondeterministic)
        let name = avoObj.name()
        XCTAssertTrue(name.hasPrefix("{"))
        XCTAssertTrue(name.hasSuffix("}"))
        XCTAssertTrue(name.contains("\"strKey\":\"string\""))
        XCTAssertTrue(name.contains("\"intKey\":\"int\""))
    }

    func test_extractComplexObjectWithAllTypes() {
        // Build a complex object with many field types
        let nestedObj: [String: Any] = ["field0": "some string"]
        let mutableDict = NSMutableDictionary()
        mutableDict["strKey"] = "Hello world"
        mutableDict["nullStrKey"] = NSNull()
        mutableDict["intKey"] = NSNumber(value: 42)
        mutableDict["floatKey"] = NSNumber(value: 42.0 as Double)
        mutableDict["boolKey"] = NSNumber(value: true)
        mutableDict["listKey"] = ["test str"]
        mutableDict["nestedObjKey"] = nestedObj

        let params: [String: Any] = ["complex object key": mutableDict]
        let schema = sut.extractSchema(params)

        guard let avoObj = schema["complex object key"] as? AvoObject else {
            XCTFail("Expected AvoObject")
            return
        }

        let name = avoObj.name()
        // Use set-based assertions for nondeterministic iteration
        XCTAssertTrue(name.contains("\"strKey\":\"string\""))
        XCTAssertTrue(name.contains("\"intKey\":\"int\""))
        XCTAssertTrue(name.contains("\"nullStrKey\":\"null\""))
        XCTAssertTrue(name.contains("\"floatKey\":\"float\""))
        XCTAssertTrue(name.contains("\"boolKey\":\"boolean\""))
        XCTAssertTrue(name.contains("\"listKey\":\"list(string)\""))
        XCTAssertTrue(name.contains("\"nestedObjKey\":{\"field0\":\"string\"}"))
    }

    func test_extractListWithDoubleNestedObjects() {
        // Use single-element nested objects to avoid nondeterministic order
        let array: [[String: Any]] = [
            ["int": 10]
        ]
        let params: [String: Any] = ["nested array": array]
        let schema = sut.extractSchema(params)

        guard let avoList = schema["nested array"] as? AvoList else {
            XCTFail("Expected AvoList")
            return
        }
        XCTAssertEqual(avoList.name(), "list({\"int\":\"int\"})")
    }

    func test_extractEmptyDictionary() {
        // Empty nested dictionaries should produce AvoObject with empty fields
        let params: [String: Any] = ["key": [String: Any]()]
        let schema = sut.extractSchema(params)
        XCTAssertTrue(schema["key"] is AvoObject)
        guard let avoObj = schema["key"] as? AvoObject else {
            XCTFail("Expected AvoObject")
            return
        }
        XCTAssertEqual(avoObj.fields.count, 0)
        XCTAssertEqual(avoObj.name(), "{}")
    }

    // MARK: - AvoObject.name() guard fallback

    func test_avoObjectNameWithNonSchemaTypeValue_skipsGracefully() {
        // If a non-AvoEventSchemaType value is placed in fields, name() should skip it without crash
        let avoObj = AvoObject()
        avoObj.fields["valid"] = AvoInt()
        avoObj.fields["invalid"] = "not a schema type" as NSString
        // Should not crash; the invalid entry is skipped by the guard in name()
        let name = avoObj.name()
        XCTAssertTrue(name.contains("\"valid\":\"int\""))
        // The invalid key should be skipped
        XCTAssertFalse(name.contains("invalid"))
    }
}
