import Foundation

@objc public class AvoObject: AvoEventSchemaType {
    @objc public var fields: NSMutableDictionary = NSMutableDictionary()

    @objc public override func name() -> String {
        var objectSchema = "{"
        let allKeys = fields.allKeys as? [String] ?? []
        for fieldKey in allKeys {
            guard let value = fields[fieldKey], let schemaType = value as? AvoEventSchemaType else {
                continue
            }
            objectSchema += "\"\(fieldKey)\":"
            if value is AvoObject {
                objectSchema += "\(schemaType.name()),"
            } else {
                objectSchema += "\"\(schemaType.name())\","
            }
        }
        if fields.count > 0 {
            objectSchema = String(objectSchema.dropLast())
        }
        objectSchema += "}"
        return objectSchema
    }
}
