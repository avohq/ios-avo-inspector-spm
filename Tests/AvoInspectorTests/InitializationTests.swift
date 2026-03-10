import XCTest
@testable import AvoInspector

final class InitializationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AvoInspector.setLogging(false)
        AvoInspector.setBatchSize(30)
        AvoInspector.setBatchFlushSeconds(30)
    }

    func test_initializesWithAppVersion() {
        let sut = AvoInspector(apiKey: "apiKey", env: .prod)
        let appVersion = sut.appVersion
        // In test environment, appVersion comes from Bundle.main which may be empty or a test runner version
        XCTAssertNotNil(appVersion)
    }

    func test_initializesWithLibVersion() {
        let sut = AvoInspector(apiKey: "apiKey", env: .prod)
        let libVersion = sut.libVersion
        XCTAssertNotNil(libVersion)
        XCTAssertFalse(libVersion.isEmpty)
    }

    func test_initializesWithDevEnv() {
        let sut = AvoInspector(apiKey: "apiKey", env: .dev)
        // Dev env should set logging to true
        XCTAssertTrue(AvoInspector.isLogging())
    }

    func test_initializesWithProdEnv() {
        let sut = AvoInspector(apiKey: "apiKey", env: .prod)
        // Prod env should set logging to false
        XCTAssertFalse(AvoInspector.isLogging())
        _ = sut
    }

    func test_initializesWithStagingEnv() {
        let sut = AvoInspector(apiKey: "apiKey", env: .staging)
        // Staging env should set logging to false (non-dev)
        XCTAssertFalse(AvoInspector.isLogging())
        _ = sut
    }

    func test_initWithEnvInt_mapsToCorrectEnv_dev() {
        // NSNumber(value: 1) -> .dev
        let sut = AvoInspector(apiKey: "apiKey", envInt: NSNumber(value: 1))
        // Dev env sets logging to true
        XCTAssertTrue(AvoInspector.isLogging())
        _ = sut
    }

    func test_initWithEnvInt_mapsToCorrectEnv_prod() {
        // NSNumber(value: 0) -> .prod
        let sut = AvoInspector(apiKey: "apiKey", envInt: NSNumber(value: 0))
        // Prod env sets logging to false
        XCTAssertFalse(AvoInspector.isLogging())
        _ = sut
    }

    func test_initWithEnvInt_staging() {
        let sut = AvoInspector(apiKey: "apiKey", envInt: NSNumber(value: 2))
        // Staging is non-dev, so logging off
        XCTAssertFalse(AvoInspector.isLogging())
        _ = sut
    }

    func test_initWithEnvInt_unknownFallsToDev() {
        let sut = AvoInspector(apiKey: "apiKey", envInt: NSNumber(value: 3))
        // Unknown env falls back to .dev -> logging true
        XCTAssertTrue(AvoInspector.isLogging())
        _ = sut
    }

    func test_initializesWithApiKey() {
        let sut = AvoInspector(apiKey: "apiKey", env: .prod)
        XCTAssertEqual(sut.apiKey, "apiKey")
    }

    func test_devInitSetsBatchSizeTo1() {
        AvoInspector.setBatchSize(30)
        let _ = AvoInspector(apiKey: "apiKey", env: .dev)
        XCTAssertEqual(AvoInspector.getBatchSize(), 1)
    }

    func test_prodInitSetsBatchSizeTo30() {
        AvoInspector.setBatchSize(1)
        let _ = AvoInspector(apiKey: "apiKey", env: .prod)
        XCTAssertEqual(AvoInspector.getBatchSize(), 30)
    }

    func test_prodInitSetsBatchFlushTo30() {
        AvoInspector.setBatchFlushSeconds(1)
        let _ = AvoInspector(apiKey: "apiKey", env: .prod)
        XCTAssertEqual(AvoInspector.getBatchFlushSeconds(), 30)
    }

    func test_devInitSetsLoggingOn() {
        AvoInspector.setLogging(false)
        let _ = AvoInspector(apiKey: "apiKey", env: .dev)
        XCTAssertTrue(AvoInspector.isLogging())
    }

    func test_prodInitSetsLoggingOff() {
        AvoInspector.setLogging(true)
        let _ = AvoInspector(apiKey: "apiKey", env: .prod)
        XCTAssertFalse(AvoInspector.isLogging())
    }
}
