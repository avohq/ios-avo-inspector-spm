import Foundation

@objc public protocol AvoStorage: NSObjectProtocol {
    func isInitialized() -> Bool
    func getItem(_ key: String) -> String?
    @objc(setItem::) func setItem(_ key: String, _ value: String)
}
