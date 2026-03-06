import XCTest
@testable import AvoInspector

final class AvoDeduplicatorThreadSafetyTests: XCTestCase {

    func test_concurrentShouldRegisterEvent_doesNotCrash() {
        let dedup = AvoDeduplicator.sharedDeduplicator
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            _ = dedup.shouldRegisterEvent("event-\(i)", eventParams: ["key": "value"], fromAvoFunction: false)
        }
    }

    func test_concurrentClearOldEvents_doesNotCrash() {
        let dedup = AvoDeduplicator.sharedDeduplicator
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            if i % 2 == 0 {
                dedup.clear()
            } else {
                _ = dedup.shouldRegisterEvent("event-\(i)", eventParams: ["k": "v"], fromAvoFunction: false)
            }
        }
    }
}
