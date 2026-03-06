import XCTest
@testable import AvoInspector

final class SimpleTypeSchemaExtractionTests: XCTestCase {

    private var sut: AvoInspector!

    override func setUp() {
        super.setUp()
        sut = AvoInspector(apiKey: "api key", env: .dev)
    }

    // MARK: - Integer types

    func test_extractInt() {
        let params: [String: Any] = ["int key": NSNumber(value: 1)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["int key"], AvoInt())
    }

    func test_extractLongLong() {
        let longLong: Int64 = 16
        let params: [String: Any] = ["longlong key": NSNumber(value: longLong)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["longlong key"], AvoInt())
    }

    func test_extractLong() {
        let lon: Int = 16
        let params: [String: Any] = ["long key": NSNumber(value: lon)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["long key"], AvoInt())
    }

    func test_extractShort() {
        let shor: Int16 = 16
        let params: [String: Any] = ["short key": NSNumber(value: shor)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["short key"], AvoInt())
    }

    // MARK: - Char type (objCType "c") -> AvoString

    func test_extractChar_producesAvoString() {
        let ch = Int8(65)
        let params: [String: Any] = ["char key": NSNumber(value: ch)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["char key"], AvoString())
    }

    // MARK: - Float / Double types

    func test_extractDoubleZero() {
        let params: [String: Any] = ["float key": NSNumber(value: 0.0)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["float key"], AvoFloat())
    }

    func test_extractDouble() {
        let params: [String: Any] = ["double key": NSNumber(value: 1.4)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["double key"], AvoFloat())
    }

    func test_extractFloat() {
        let params: [String: Any] = ["float key": NSNumber(value: Float(1.4))]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["float key"], AvoFloat())
    }

    // MARK: - Boolean

    func test_extractBoolean() {
        let params: [String: Any] = ["boolean key": NSNumber(value: true)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["boolean key"], AvoBoolean())
    }

    func test_booleanNotConfusedWithInt() {
        // NSNumber(value: true) must produce AvoBoolean, not AvoInt
        let params: [String: Any] = ["bool key": NSNumber(value: true)]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["bool key"], AvoBoolean())
        XCTAssertNotEqual(schema["bool key"], AvoInt())
    }

    // MARK: - Null

    func test_extractNull() {
        let params: [String: Any] = ["null key": NSNull()]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["null key"], AvoNull())
    }

    // MARK: - String

    func test_extractConstantString() {
        let params: [String: Any] = ["const string key": "String"]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["const string key"], AvoString())
    }

    // MARK: - NSConstantIntegerNumber / NSConstantDoubleNumber (single-element collections)

    func test_constantIntegerNumber() {
        // @1 in ObjC can produce NSConstantIntegerNumber at runtime
        let params: [String: Any] = ["key": 1 as NSNumber]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["key"], AvoInt())
    }

    func test_constantDoubleNumber() {
        // @0.0 in ObjC can produce NSConstantDoubleNumber at runtime
        let params: [String: Any] = ["key": 0.0 as NSNumber]
        let schema = sut.extractSchema(params)
        XCTAssertEqual(schema["key"], AvoFloat())
    }
}
