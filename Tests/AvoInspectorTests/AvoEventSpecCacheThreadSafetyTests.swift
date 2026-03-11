import XCTest
@testable import AvoInspector

final class AvoEventSpecCacheThreadSafetyTests: XCTestCase {

    func test_concurrentGetAndSet_doesNotCrash() {
        let cache = AvoEventSpecCache()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            let key = "key-\(i % 10)"
            if i % 3 == 0 {
                cache.set(key, spec: nil)
            } else if i % 3 == 1 {
                _ = cache.get(key)
            } else {
                _ = cache.contains(key)
            }
        }
    }

    func test_concurrentClearAndSet_doesNotCrash() {
        let cache = AvoEventSpecCache()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            if i % 2 == 0 {
                cache.clear()
            } else {
                cache.set("key-\(i)", spec: nil)
            }
        }
    }
}
