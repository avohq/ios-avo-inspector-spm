import Foundation

@objc public class AvoGuid: NSObject {
    @objc public class func newGuid() -> String {
        return UUID().uuidString
    }
}
