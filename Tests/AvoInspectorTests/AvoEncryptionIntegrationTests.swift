import XCTest
import Security
@testable import AvoInspector

// MARK: - Test Helpers

private func generateTestPrivateKey() -> SecKey? {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    return SecKeyCreateRandomKey(attributes as CFDictionary, &error)
}

private func publicKeyHexFromPrivateKey(_ privateKey: SecKey) -> String? {
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
    var error: Unmanaged<CFError>?
    guard let pubData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { return nil }
    return pubData.map { String(format: "%02x", $0) }.joined()
}

// MARK: - AvoEncryptionIntegrationTests

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
final class AvoEncryptionIntegrationTests: XCTestCase {

    private var testPrivateKey: SecKey!
    private var testPublicKeyHex: String!

    override func setUp() {
        super.setUp()
        testPrivateKey = generateTestPrivateKey()
        XCTAssertNotNil(testPrivateKey)
        testPublicKeyHex = publicKeyHexFromPrivateKey(testPrivateKey)
        XCTAssertNotNil(testPublicKeyHex)
    }

    // MARK: - Batched Event Encryption

    func test_includesEncryptedValuesInDevMode() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)

        var schema = [String: AvoEventSchemaType]()
        schema["userId"] = AvoString()
        schema["count"] = AvoInt()

        let eventProperties: [String: Any] = ["userId": "user123", "count": 42]

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: schema, eventId: nil, eventHash: nil,
            eventProperties: eventProperties)

        let properties = body["eventProperties"] as? NSArray
        XCTAssertNotNil(properties)

        var foundEncryptedUserId = false
        var foundEncryptedCount = false
        for case let prop as NSDictionary in properties! {
            if prop["propertyName"] as? String == "userId" {
                XCTAssertNotNil(prop["encryptedPropertyValue"])
                foundEncryptedUserId = true
            }
            if prop["propertyName"] as? String == "count" {
                XCTAssertNotNil(prop["encryptedPropertyValue"])
                foundEncryptedCount = true
            }
        }
        XCTAssertTrue(foundEncryptedUserId)
        XCTAssertTrue(foundEncryptedCount)
    }

    func test_includesEncryptedValuesInStagingMode() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 2, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)

        var schema = [String: AvoEventSchemaType]()
        schema["name"] = AvoString()

        let eventProperties: [String: Any] = ["name": "test"]

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: schema, eventId: nil, eventHash: nil,
            eventProperties: eventProperties)

        let properties = body["eventProperties"] as? NSArray
        XCTAssertNotNil(properties)
        let prop = properties![0] as! NSDictionary
        XCTAssertNotNil(prop["encryptedPropertyValue"])
    }

    func test_noEncryptionInProdEvenWithKey() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 0, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)

        var schema = [String: AvoEventSchemaType]()
        schema["userId"] = AvoString()

        let eventProperties: [String: Any] = ["userId": "user123"]

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: schema, eventId: nil, eventHash: nil,
            eventProperties: eventProperties)

        let properties = body["eventProperties"] as? NSArray
        XCTAssertNotNil(properties)
        for case let prop as NSDictionary in properties! {
            XCTAssertNil(prop["encryptedPropertyValue"])
        }
    }

    func test_noEncryptionWhenKeyIsNil() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: nil)

        var schema = [String: AvoEventSchemaType]()
        schema["userId"] = AvoString()

        let eventProperties: [String: Any] = ["userId": "user123"]

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: schema, eventId: nil, eventHash: nil,
            eventProperties: eventProperties)

        let properties = body["eventProperties"] as? NSArray
        XCTAssertNotNil(properties)
        for case let prop as NSDictionary in properties! {
            XCTAssertNil(prop["encryptedPropertyValue"])
        }
    }

    // MARK: - publicEncryptionKey in Base Body

    func test_includesPublicEncryptionKeyWhenPresent() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: [String: AvoEventSchemaType](),
            eventId: nil, eventHash: nil, eventProperties: nil)

        XCTAssertEqual(body["publicEncryptionKey"] as? String, testPublicKeyHex)
    }

    func test_doesNotIncludePublicEncryptionKeyWhenNil() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: nil)

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: [String: AvoEventSchemaType](),
            eventId: nil, eventHash: nil, eventProperties: nil)

        XCTAssertNil(body["publicEncryptionKey"])
    }

    // MARK: - Nested Objects and Lists

    func test_nestedObjectChildrenAreEncrypted() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)

        let addressObj = AvoObject()
        addressObj.fields["street"] = AvoString()
        addressObj.fields["zip"] = AvoInt()

        var schema = [String: AvoEventSchemaType]()
        schema["address"] = addressObj

        let innerProps: [String: Any] = ["street": "123 Main St", "zip": 90210]
        let eventProperties: [String: Any] = ["address": innerProps]

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: schema, eventId: nil, eventHash: nil,
            eventProperties: eventProperties)

        let properties = body["eventProperties"] as? NSArray
        XCTAssertNotNil(properties)

        var addressProp: NSDictionary?
        for case let p as NSDictionary in properties! {
            if p["propertyName"] as? String == "address" {
                addressProp = p
                break
            }
        }
        XCTAssertNotNil(addressProp)
        XCTAssertNil(addressProp!["encryptedPropertyValue"])

        let children = addressProp!["children"] as? NSArray
        XCTAssertNotNil(children)

        var foundEncryptedStreet = false
        var foundEncryptedZip = false
        for case let child as NSDictionary in children! {
            if child["propertyName"] as? String == "street" {
                XCTAssertNotNil(child["encryptedPropertyValue"])
                foundEncryptedStreet = true
            }
            if child["propertyName"] as? String == "zip" {
                XCTAssertNotNil(child["encryptedPropertyValue"])
                foundEncryptedZip = true
            }
        }
        XCTAssertTrue(foundEncryptedStreet)
        XCTAssertTrue(foundEncryptedZip)
    }

    func test_listValuesAreNotEncrypted() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testApp", appVersion: "1.0.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)

        let list = AvoList()
        list.subtypes = NSMutableSet(array: [AvoString()])

        var schema = [String: AvoEventSchemaType]()
        schema["tags"] = list

        let eventProperties: [String: Any] = ["tags": ["a", "b", "c"]]

        let body = handler.bodyForTrackSchemaCall(
            "TestEvent", schema: schema, eventId: nil, eventHash: nil,
            eventProperties: eventProperties)

        let properties = body["eventProperties"] as? NSArray
        XCTAssertNotNil(properties)
        for case let prop as NSDictionary in properties! {
            if prop["propertyName"] as? String == "tags" {
                XCTAssertNil(prop["encryptedPropertyValue"])
            }
        }
    }

    // MARK: - shouldEncrypt

    func test_shouldEncryptReturnsTrueForDevWithKey() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "key", appName: "app", appVersion: "1.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)
        XCTAssertTrue(handler.shouldEncrypt())
    }

    func test_shouldEncryptReturnsTrueForStagingWithKey() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "key", appName: "app", appVersion: "1.0",
            libVersion: "7", env: 2, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)
        XCTAssertTrue(handler.shouldEncrypt())
    }

    func test_shouldEncryptReturnsFalseForProd() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "key", appName: "app", appVersion: "1.0",
            libVersion: "7", env: 0, endpoint: "test",
            publicEncryptionKey: testPublicKeyHex)
        XCTAssertFalse(handler.shouldEncrypt())
    }

    func test_shouldEncryptReturnsFalseForNilKey() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "key", appName: "app", appVersion: "1.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: nil)
        XCTAssertFalse(handler.shouldEncrypt())
    }

    func test_shouldEncryptReturnsFalseForEmptyKey() {
        let handler = AvoNetworkCallsHandler(
            apiKey: "key", appName: "app", appVersion: "1.0",
            libVersion: "7", env: 1, endpoint: "test",
            publicEncryptionKey: "")
        XCTAssertFalse(handler.shouldEncrypt())
    }

    // MARK: - jsonStringifyValue

    func test_jsonStringifyValueStringifiesAString() {
        XCTAssertEqual(AvoNetworkCallsHandler.jsonStringifyValue("hello"), "\"hello\"")
    }

    func test_jsonStringifyValueStringifiesAnInteger() {
        XCTAssertEqual(AvoNetworkCallsHandler.jsonStringifyValue(42), "42")
    }

    func test_jsonStringifyValueStringifiesADouble() {
        let result = AvoNetworkCallsHandler.jsonStringifyValue(3.14)
        XCTAssertNotNil(result)
        // NSJSONSerialization may produce "3.14" or "3.1400000000000001" depending on precision
        XCTAssertTrue(result!.hasPrefix("3.14"))
    }

    func test_jsonStringifyValueStringifiesBooleanTrue() {
        XCTAssertEqual(AvoNetworkCallsHandler.jsonStringifyValue(true), "true")
    }

    func test_jsonStringifyValueStringifiesBooleanFalse() {
        XCTAssertEqual(AvoNetworkCallsHandler.jsonStringifyValue(false), "false")
    }
}
