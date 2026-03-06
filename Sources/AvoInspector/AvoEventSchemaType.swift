import Foundation

@objc public class AvoEventSchemaType: NSObject {
    @objc public func name() -> String {
        return "base"
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AvoEventSchemaType,
              type(of: self) == type(of: other) else { return false }
        return self.name() == other.name()
    }

    public override var hash: Int {
        return name().hash
    }

    public override var description: String {
        return name()
    }
}
