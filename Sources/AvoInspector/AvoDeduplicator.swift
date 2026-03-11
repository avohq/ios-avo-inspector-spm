import Foundation

@objc public class AvoDeduplicator: NSObject {

    @objc public static let sharedDeduplicator = AvoDeduplicator()

    private let queue = DispatchQueue(label: "com.avo.deduplicator")
    private var avoFunctionsEvents = [NSNumber: String]()
    private var manualEvents = [NSNumber: String]()
    private var avoFunctionsEventsParams = [String: [String: Any]]()
    private var manualEventsParams = [String: [String: Any]]()
    private var avoSchemaExtractor = AvoSchemaExtractor()

    override init() {
        super.init()
    }

    @objc public func clear() {
        queue.sync {
            self.avoFunctionsEvents = [:]
            self.manualEvents = [:]
            self.avoFunctionsEventsParams = [:]
            self.manualEventsParams = [:]
            self.avoSchemaExtractor = AvoSchemaExtractor()
        }
    }

    @objc public func shouldRegisterEvent(_ eventName: String, eventParams params: [String: Any], fromAvoFunction: Bool) -> Bool {
        clearOldEvents()

        queue.sync {
            let timestamp = NSNumber(value: Date().timeIntervalSince1970)
            if fromAvoFunction {
                self.avoFunctionsEvents[timestamp] = eventName
                self.avoFunctionsEventsParams[eventName] = params
            } else {
                self.manualEvents[timestamp] = eventName
                self.manualEventsParams[eventName] = params
            }
        }

        let checkInAvoFunctions = !fromAvoFunction

        return !hasSameEvent(as: eventName, eventParams: params, checkInAvoFunctions: checkInAvoFunctions)
    }

    @objc public func hasSeenEventParams(_ params: [String: Any], checkInAvoFunctions: Bool) -> Bool {
        var hasSeen = false
        if checkInAvoFunctions {
            if lookForEventParams(params, in: avoFunctionsEventsParams) {
                hasSeen = true
            }
        } else {
            if lookForEventParams(params, in: manualEventsParams) {
                hasSeen = true
            }
        }
        return hasSeen
    }

    private func lookForEventParams(_ params: [String: Any], in eventsStorage: [String: [String: Any]]) -> Bool {
        var result = false
        queue.sync {
            for (_, otherEventParams) in eventsStorage {
                if NSDictionary(dictionary: params).isEqual(to: otherEventParams) {
                    result = true
                    break
                }
            }
        }
        return result
    }

    private func hasSameEvent(as eventName: String, eventParams params: [String: Any], checkInAvoFunctions: Bool) -> Bool {
        var hasSameEvents = false
        if checkInAvoFunctions {
            if lookForEventName(eventName, withParams: params, in: avoFunctionsEventsParams) {
                hasSameEvents = true
            }
        } else {
            if lookForEventName(eventName, withParams: params, in: manualEventsParams) {
                hasSameEvents = true
            }
        }

        if hasSameEvents {
            queue.sync {
                self.avoFunctionsEventsParams.removeValue(forKey: eventName)
                self.manualEventsParams.removeValue(forKey: eventName)
            }
        }

        return hasSameEvents
    }

    private func lookForEventName(_ eventName: String, withParams params: [String: Any], in eventsStorage: [String: [String: Any]]) -> Bool {
        var result = false
        queue.sync {
            for (otherEventName, otherEventParams) in eventsStorage {
                if otherEventName == eventName && NSDictionary(dictionary: params).isEqual(to: otherEventParams) {
                    result = true
                    break
                }
            }
        }
        return result
    }

    @objc public func shouldRegisterSchemaFromManually(_ eventName: String, schema: [String: AvoEventSchemaType]) -> Bool {
        clearOldEvents()

        var shouldRegisterSchema = true

        if lookForEventName(eventName, withSchema: schema, in: avoFunctionsEventsParams) {
            shouldRegisterSchema = false
        }

        if !shouldRegisterSchema {
            queue.sync {
                self.avoFunctionsEventsParams.removeValue(forKey: eventName)
            }
        }

        return shouldRegisterSchema
    }

    private func lookForEventName(_ eventName: String, withSchema schema: [String: AvoEventSchemaType], in eventsStorage: [String: [String: Any]]) -> Bool {
        var result = false
        queue.sync {
            for (otherEventName, otherEventParams) in eventsStorage {
                let otherSchema = self.avoSchemaExtractor.extractSchema(otherEventParams)
                if otherEventName == eventName && NSDictionary(dictionary: schema).isEqual(to: otherSchema) {
                    result = true
                    break
                }
            }
        }
        return result
    }

    private func clearOldEvents() {
        queue.sync {
            let now = Date().timeIntervalSince1970
            let secondsToConsiderOld: Double = 0.3

            var newAvoFunctionsEvents = [NSNumber: String]()
            var newAvoFunctionsEventsParams = [String: [String: Any]]()

            for (timestamp, eventName) in self.avoFunctionsEvents {
                if now - timestamp.doubleValue <= secondsToConsiderOld {
                    if let eventParams = self.avoFunctionsEventsParams[eventName] {
                        newAvoFunctionsEventsParams[eventName] = eventParams
                        newAvoFunctionsEvents[timestamp] = eventName
                    }
                }
            }

            self.avoFunctionsEvents = newAvoFunctionsEvents
            self.avoFunctionsEventsParams = newAvoFunctionsEventsParams

            var newManualEvents = [NSNumber: String]()
            var newManualEventsParams = [String: [String: Any]]()

            for (timestamp, eventName) in self.manualEvents {
                if now - timestamp.doubleValue <= secondsToConsiderOld {
                    if let eventParams = self.manualEventsParams[eventName] {
                        newManualEventsParams[eventName] = eventParams
                        newManualEvents[timestamp] = eventName
                    }
                }
            }

            self.manualEvents = newManualEvents
            self.manualEventsParams = newManualEventsParams
        }
    }
}
