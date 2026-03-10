import Foundation

@objc public class AvoSchemaExtractor: NSObject {

    @objc public func extractSchema(_ eventParams: [String: Any]) -> [String: AvoEventSchemaType] {
        var result = [String: AvoEventSchemaType]()
        for (paramName, paramValue) in eventParams {
            let paramType = objectToAvoSchemaType(paramValue)
            result[paramName] = paramType
        }
        return result
    }

    private func objectToAvoSchemaType(_ obj: Any) -> AvoEventSchemaType {
        // NSNull check
        if obj is NSNull {
            return AvoNull()
        }

        // Boolean check MUST come before NSNumber check.
        // NSNumber(value: true) and NSNumber(value: 1) are indistinguishable via `is Bool` in Swift.
        // Use CFBooleanGetTypeID to reliably detect booleans.
        if CFGetTypeID(obj as CFTypeRef) == CFBooleanGetTypeID() {
            return AvoBoolean()
        }

        // NSNumber check with objCType inspection
        if let number = obj as? NSNumber {
            let objCType = String(cString: number.objCType)
            switch objCType {
            case "c", "i", "s", "l", "q", "C", "I", "S", "L", "Q":
                return AvoInt()
            case "d", "f":
                return AvoFloat()
            default:
                return AvoFloat()
            }
        }

        // String check
        if obj is String || obj is NSString {
            return AvoString()
        }

        // Array / Set check (AvoList)
        if let array = obj as? [Any] {
            let result = AvoList()
            for item in array {
                if item is NSNull {
                    result.subtypes.add(AvoNull())
                } else {
                    result.subtypes.add(objectToAvoSchemaType(item))
                }
            }
            return result
        }

        if let set = obj as? NSSet {
            let result = AvoList()
            for item in set {
                if item is NSNull {
                    result.subtypes.add(AvoNull())
                } else {
                    result.subtypes.add(objectToAvoSchemaType(item))
                }
            }
            return result
        }

        // Dictionary check (AvoObject)
        if let dict = obj as? NSDictionary {
            let result = AvoObject()
            for key in dict.allKeys {
                guard let paramValue = dict[key] else { continue }
                if let stringKey = key as? String {
                    let paramType = self.objectToAvoSchemaType(paramValue)
                    result.fields.setObject(paramType, forKey: stringKey as NSString)
                } else {
                    let descriptionParts = "\(key)".components(separatedBy: ".")
                    let stringParamName: String
                    if descriptionParts.count >= 2 {
                        stringParamName = "\(descriptionParts[descriptionParts.count - 2]).\(descriptionParts[descriptionParts.count - 1])"
                    } else {
                        stringParamName = descriptionParts[0]
                    }
                    let paramType = self.objectToAvoSchemaType(paramValue)
                    result.fields.setObject(paramType, forKey: stringParamName as NSString)
                }
            }
            return result
        }

        return AvoUnknownType()
    }

    @objc public func printAvoParsingError(_ error: Any) {
        NSLog("[avo]        !!!!!!!!! Avo Inspector Parsing Error !!!!!!!!!")
        NSLog("[avo]        Please report the following error to support@avo.app")
        NSLog("[avo]        CRASH: %@", "\(error)")
        if let exception = error as? NSException {
            NSLog("[avo]        Stack Trace: %@", exception.callStackSymbols.description)
        }
    }
}
