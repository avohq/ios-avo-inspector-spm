import XCTest
@testable import AvoInspector

final class EnvironmentMappingTests: XCTestCase {

    func test_devEnvMapping() {
        let devMap = AvoNetworkCallsHandler.formatTypeToString(Int32(AvoInspectorEnv.dev.rawValue))
        XCTAssertEqual(devMap, "dev")
    }

    func test_prodEnvMapping() {
        let prodMap = AvoNetworkCallsHandler.formatTypeToString(Int32(AvoInspectorEnv.prod.rawValue))
        XCTAssertEqual(prodMap, "prod")
    }

    func test_stagingEnvMapping() {
        let stageMap = AvoNetworkCallsHandler.formatTypeToString(Int32(AvoInspectorEnv.staging.rawValue))
        XCTAssertEqual(stageMap, "staging")
    }

    func test_networkCallsHandlerSendsProdEnv() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName",
            appVersion: "testAppVersion", libVersion: "testLibVersion",
            env: 0, endpoint: "text.proxy")

        let body = sut.bodyForTrackSchemaCall("testEvent", schema: [:],
                                               eventId: nil, eventHash: nil)
        XCTAssertEqual(body["env"] as? String, "prod")
    }

    func test_networkCallsHandlerSendsDevEnv() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName",
            appVersion: "testAppVersion", libVersion: "testLibVersion",
            env: 1, endpoint: "text.proxy")

        let body = sut.bodyForTrackSchemaCall("testEvent", schema: [:],
                                               eventId: nil, eventHash: nil)
        XCTAssertEqual(body["env"] as? String, "dev")
    }

    func test_networkCallsHandlerSendsStagingEnv() {
        let sut = AvoNetworkCallsHandler(
            apiKey: "testApiKey", appName: "testAppName",
            appVersion: "testAppVersion", libVersion: "testLibVersion",
            env: 2, endpoint: "text.proxy")

        let body = sut.bodyForTrackSchemaCall("testEvent", schema: [:],
                                               eventId: nil, eventHash: nil)
        XCTAssertEqual(body["env"] as? String, "staging")
    }
}
