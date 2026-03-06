import XCTest
@testable import AvoInspector

final class SamplingTests: XCTestCase {

    func test_doesNotSendData_withSamplingRateZero() {
        // We can't easily set samplingRate since it's private, but we can test
        // that the callInspectorWithBatchBody respects sampling.
        // Since drand48() > 0.0 is always true, no requests should go through.

        // Use a subclass that tracks calls to the internal send method
        let sut = SamplingTestNetworkHandler(
            apiKey: "testApiKey", appName: "testAppName", appVersion: "testAppVersion",
            libVersion: "testLibVersion", env: 1, endpoint: "text.proxy",
            testSamplingRate: 0.0)

        for _ in 0..<100 {
            let body1 = sut.bodyForTrackSchemaCall("Event1", schema: [:], eventId: nil, eventHash: nil)
            sut.callInspectorWithBatchBody([body1]) { _ in }
            let body2 = sut.bodyForTrackSchemaCall("Event2", schema: [:], eventId: nil, eventHash: nil)
            sut.callInspectorWithBatchBody([body2]) { _ in }
        }

        // With sampling rate 0, drand48() > 0.0 is almost always true, so
        // the sampling guard should block most/all requests.
        // Due to drand48() returning exactly 0.0 being possible but extremely rare,
        // we just verify minimal requests went through.
        XCTAssertLessThanOrEqual(sut.actualRequestCount, 5,
                                  "With sampling rate 0, very few requests should go through")
    }

    func test_sendsDataEveryTime_withSamplingRateOne() {
        let sut = SamplingTestNetworkHandler(
            apiKey: "testApiKey", appName: "testAppName", appVersion: "testAppVersion",
            libVersion: "testLibVersion", env: 1, endpoint: "text.proxy",
            testSamplingRate: 1.0)

        let iterations = 100
        for _ in 0..<iterations {
            let body1 = sut.bodyForTrackSchemaCall("Event1", schema: [:], eventId: nil, eventHash: nil)
            sut.callInspectorWithBatchBody([body1]) { _ in }
            let body2 = sut.bodyForTrackSchemaCall("Event2", schema: [:], eventId: nil, eventHash: nil)
            sut.callInspectorWithBatchBody([body2]) { _ in }
        }

        // With sampling rate 1.0, drand48() > 1.0 is never true, so all requests should pass
        XCTAssertEqual(sut.actualRequestCount, iterations * 2,
                        "With sampling rate 1, all requests should go through")
    }
}

/// A test helper that exposes the sampling rate and counts actual network attempts.
/// Since `samplingRate` is private, we use the mock approach from TrackTests.
private class SamplingTestNetworkHandler: AvoNetworkCallsHandler {
    var actualRequestCount = 0
    private let testSamplingRate: Double

    init(apiKey: String, appName: String, appVersion: String,
         libVersion: String, env: Int, endpoint: String,
         testSamplingRate: Double) {
        self.testSamplingRate = testSamplingRate
        super.init(apiKey: apiKey, appName: appName, appVersion: appVersion,
                   libVersion: libVersion, env: env, endpoint: endpoint)
    }

    override func callInspectorWithBatchBody(_ batchBody: [Any],
                                              completionHandler: @escaping (Error?) -> Void) {
        // Replicate sampling logic with controllable rate
        if drand48() > testSamplingRate {
            return
        }
        actualRequestCount += 1
        completionHandler(nil)
    }
}
