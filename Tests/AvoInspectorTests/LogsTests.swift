import XCTest
@testable import AvoInspector

final class LogsTests: XCTestCase {

    func test_logsEventParameters_doesNotCrash() {
        let initialLoggingState = AvoInspector.isLogging()
        defer { AvoInspector.setLogging(initialLoggingState) }

        let sut = AvoInspector(apiKey: "apiKey", env: .dev)
        AvoInspector.setLogging(true)

        let array: [Any] = ["test", 42]
        let params: [String: Any] = [
            "array key": array,
            "int key": 42
        ]

        // This should not crash, and should produce a non-empty schema
        let schema = sut.trackSchema(fromEvent: "Test Event", eventParams: params)
        XCTAssertFalse(schema.isEmpty)
    }

    func test_loggingCanBeToggled() {
        let initialLoggingState = AvoInspector.isLogging()
        defer { AvoInspector.setLogging(initialLoggingState) }

        AvoInspector.setLogging(true)
        XCTAssertTrue(AvoInspector.isLogging())

        AvoInspector.setLogging(false)
        XCTAssertFalse(AvoInspector.isLogging())
    }
}
