import XCTest
@testable import AvoInspector

final class AvoAnonymousIdThreadSafetyTests: XCTestCase {

    func test_concurrentAnonymousIdAccess_returnsConsistentValue() {
        var results = [String](repeating: "", count: 100)
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            results[i] = AvoAnonymousId.anonymousId()
        }
        let uniqueValues = Set(results)
        XCTAssertEqual(uniqueValues.count, 1, "All concurrent calls should return the same value")
    }

    func test_concurrentSetAndGet_doesNotCrash() {
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            if i % 2 == 0 {
                AvoAnonymousId.setAnonymousId("test-\(i)")
            } else {
                _ = AvoAnonymousId.anonymousId()
            }
        }
        // If we reach here without crashing, the test passes
    }

    func test_concurrentClearAndGet_doesNotCrash() {
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            if i % 2 == 0 {
                AvoAnonymousId.clearCache()
            } else {
                _ = AvoAnonymousId.anonymousId()
            }
        }
    }
}
