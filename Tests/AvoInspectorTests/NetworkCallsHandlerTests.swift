import XCTest
@testable import AvoInspector

final class NetworkCallsHandlerTests: XCTestCase {

    // MARK: - Initialization

    func test_savesValuesWhenInit() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName", appVersion: "testAppVersion",
            libVersion: "testLibVersion", env: 1, endpoint: "test.proxy")

        XCTAssertEqual(sut.apiKey, "testApiKey")
        XCTAssertEqual(sut.appVersion, "testAppVersion")
        XCTAssertEqual(sut.libVersion, "testLibVersion")
        XCTAssertEqual(sut.appName, "testAppName")
    }

    // MARK: - Body Construction

    func test_buildsProperBodyForSchemaTracking() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName", appVersion: "testAppVersion",
            libVersion: "testLibVersion", env: 0, endpoint: "text.proxy")

        var schema = [String: AvoEventSchemaType]()
        let list = AvoList()
        list.subtypes = NSMutableSet(array: [AvoInt(), AvoFloat(), AvoBoolean(), AvoString(), AvoNull(), AvoUnknownType(), AvoList()])
        schema["list key"] = list
        schema["int key"] = AvoInt()
        schema["float key"] = AvoFloat()
        schema["boolean key"] = AvoBoolean()
        schema["string key"] = AvoString()
        schema["null key"] = AvoNull()
        schema["unknown type key"] = AvoUnknownType()

        let body = sut.bodyForTrackSchemaCall("Test Event Name", schema: schema, eventId: nil, eventHash: nil)

        XCTAssertEqual(body["type"] as? String, "event")
        XCTAssertEqual(body["eventName"] as? String, "Test Event Name")
        XCTAssertEqual(body["apiKey"] as? String, "testApiKey")
        XCTAssertEqual(body["appVersion"] as? String, "testAppVersion")
        XCTAssertEqual(body["libVersion"] as? String, "testLibVersion")
        XCTAssertEqual(body["libPlatform"] as? String, "ios")
        XCTAssertEqual(body["appName"] as? String, "testAppName")
        XCTAssertNotNil(body["createdAt"])
        XCTAssertNotNil(body["messageId"])
        XCTAssertEqual(body["sessionId"] as? String, "")
        XCTAssertEqual(body["trackingId"] as? String, "")
        XCTAssertNotNil(body["anonymousId"])
        XCTAssertEqual(body["avoFunction"] as? Bool, false)

        let eventProperties = body["eventProperties"] as? NSMutableArray
        XCTAssertNotNil(eventProperties)
        XCTAssertEqual(eventProperties?.count, 7)

        // Verify each property type
        if let props = eventProperties {
            for case let childProp as NSDictionary in props {
                let key = childProp["propertyName"] as? String ?? ""
                let propType = childProp["propertyType"] as? String ?? ""

                switch key {
                case "list key":
                    XCTAssertTrue(propType.hasPrefix("list("), "List type should start with 'list('")
                    XCTAssertTrue(propType.contains("int"))
                    XCTAssertTrue(propType.contains("float"))
                    XCTAssertTrue(propType.contains("boolean"))
                    XCTAssertTrue(propType.contains("string"))
                    XCTAssertTrue(propType.contains("null"))
                    XCTAssertTrue(propType.contains("unknown"))
                case "int key":
                    XCTAssertEqual(propType, "int")
                case "float key":
                    XCTAssertEqual(propType, "float")
                case "boolean key":
                    XCTAssertEqual(propType, "boolean")
                case "string key":
                    XCTAssertEqual(propType, "string")
                case "null key":
                    XCTAssertEqual(propType, "null")
                case "unknown type key":
                    XCTAssertEqual(propType, "unknown")
                default:
                    XCTFail("Unexpected property key: \(key)")
                }
            }
        }
    }

    func test_buildsProperBodyForObjectSchemaTracking() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName", appVersion: "testAppVersion",
            libVersion: "testLibVersion", env: 1, endpoint: "text.proxy")

        var schema = [String: AvoEventSchemaType]()
        let object = AvoObject()
        object.fields.setObject(AvoString(), forKey: "key1" as NSString)
        object.fields.setObject(AvoInt(), forKey: "key2" as NSString)

        let list = AvoList()
        list.subtypes = NSMutableSet(array: [AvoInt(), AvoFloat(), AvoBoolean(), AvoString(), AvoNull(), AvoUnknownType(), AvoList()])
        object.fields.setObject(list, forKey: "key3" as NSString)

        let nestedObject = AvoObject()
        nestedObject.fields.setObject(AvoString(), forKey: "nestedKey1" as NSString)
        nestedObject.fields.setObject(AvoInt(), forKey: "nestedKey2" as NSString)
        nestedObject.fields.setObject(list, forKey: "nestedKey3" as NSString)
        object.fields.setObject(nestedObject, forKey: "key4" as NSString)

        schema["obj key"] = object

        let body = sut.bodyForTrackSchemaCall("Test Event Name", schema: schema, eventId: nil, eventHash: nil)

        XCTAssertEqual(body["type"] as? String, "event")
        XCTAssertEqual(body["eventName"] as? String, "Test Event Name")

        let eventProperties = body["eventProperties"] as? NSMutableArray
        XCTAssertNotNil(eventProperties)
        XCTAssertEqual(eventProperties?.count, 1)

        if let props = eventProperties, let firstProp = props[0] as? NSDictionary {
            XCTAssertEqual(firstProp["propertyName"] as? String, "obj key")
            XCTAssertEqual(firstProp["propertyType"] as? String, "object")

            if let children = firstProp["children"] as? NSMutableArray {
                for case let childProp as NSDictionary in children {
                    let key = childProp["propertyName"] as? String ?? ""
                    let propType = childProp["propertyType"] as? String ?? ""

                    switch key {
                    case "key1":
                        XCTAssertEqual(propType, "string")
                    case "key2":
                        XCTAssertEqual(propType, "int")
                    case "key3":
                        XCTAssertTrue(propType.hasPrefix("list("))
                    case "key4":
                        XCTAssertEqual(propType, "object")
                        // Check nested children
                        if let nestedChildren = childProp["children"] as? NSMutableArray {
                            for case let nestedChild as NSDictionary in nestedChildren {
                                let nestedKey = nestedChild["propertyName"] as? String ?? ""
                                let nestedType = nestedChild["propertyType"] as? String ?? ""
                                switch nestedKey {
                                case "nestedKey1":
                                    XCTAssertEqual(nestedType, "string")
                                case "nestedKey2":
                                    XCTAssertEqual(nestedType, "int")
                                case "nestedKey3":
                                    XCTAssertTrue(nestedType.hasPrefix("list("))
                                default:
                                    break
                                }
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }

        XCTAssertEqual(body["apiKey"] as? String, "testApiKey")
        XCTAssertEqual(body["appVersion"] as? String, "testAppVersion")
        XCTAssertEqual(body["libVersion"] as? String, "testLibVersion")
        XCTAssertEqual(body["libPlatform"] as? String, "ios")
        XCTAssertEqual(body["appName"] as? String, "testAppName")
        XCTAssertNotNil(body["createdAt"])
        XCTAssertNotNil(body["messageId"])
        XCTAssertEqual(body["avoFunction"] as? Bool, false)
    }

    func test_buildsProperBodyForAvoFunctionSchemaTracking() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName", appVersion: "testAppVersion",
            libVersion: "testLibVersion", env: 0, endpoint: "text.proxy")

        let body = sut.bodyForTrackSchemaCall("Test Event Name", schema: [:], eventId: "event id", eventHash: "event hash")

        XCTAssertEqual(body["eventId"] as? String, "event id")
        XCTAssertEqual(body["eventHash"] as? String, "event hash")
        XCTAssertEqual(body["avoFunction"] as? Bool, true)
    }

    func test_formatTypeToString_dev() {
        XCTAssertEqual(AvoNetworkCallsHandler.formatTypeToString(1), "dev")
    }

    func test_formatTypeToString_prod() {
        XCTAssertEqual(AvoNetworkCallsHandler.formatTypeToString(0), "prod")
    }

    func test_formatTypeToString_staging() {
        XCTAssertEqual(AvoNetworkCallsHandler.formatTypeToString(2), "staging")
    }
}
