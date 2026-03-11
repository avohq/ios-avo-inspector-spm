import Foundation

@objc public class AvoList: AvoEventSchemaType {
    @objc public var subtypes: NSMutableSet = NSMutableSet()

    @objc public override func name() -> String {
        var listTypes = ""
        var first = true
        for subtype in subtypes {
            guard let schemaType = subtype as? AvoEventSchemaType else { continue }
            if !first { listTypes += "|" }
            listTypes += schemaType.name()
            first = false
        }
        return "list(\(listTypes))"
    }
}
