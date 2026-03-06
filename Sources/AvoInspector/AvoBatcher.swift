import Foundation

@objc public class AvoBatcher: NSObject {

    @objc public let networkCallsHandler: AvoNetworkCallsHandler

    private var events = [Any]()
    private var batchFlushAttemptTime: TimeInterval = Date().timeIntervalSince1970
    private let lock = NSLock()

    static let suiteKey = "AvoBatcherSuiteKey"
    static let cacheKey = "AvoBatcherCacheKey"

    @objc public init(networkCallsHandler: AvoNetworkCallsHandler) {
        self.networkCallsHandler = networkCallsHandler
        super.init()
    }

    // MARK: - Public API

    @objc public func handleTrackSchema(_ eventName: String,
                                         schema: [String: AvoEventSchemaType],
                                         eventId: String?,
                                         eventHash: String?) {
        let trackSchemaBody = networkCallsHandler.bodyForTrackSchemaCall(
            eventName, schema: schema, eventId: eventId, eventHash: eventHash)
        saveAndLogEvent(trackSchemaBody, schema: schema, eventName: eventName)
    }

    @objc public func handleTrackSchema(_ eventName: String,
                                         schema: [String: AvoEventSchemaType],
                                         eventId: String?,
                                         eventHash: String?,
                                         eventProperties: [String: Any]?) {
        let trackSchemaBody = networkCallsHandler.bodyForTrackSchemaCall(
            eventName, schema: schema, eventId: eventId, eventHash: eventHash,
            eventProperties: eventProperties)
        saveAndLogEvent(trackSchemaBody, schema: schema, eventName: eventName)
    }

    @objc public func enterBackground() {
        lock.lock()
        let count = events.count
        lock.unlock()

        if count == 0 { return }

        removeExtraElements()

        lock.lock()
        let eventsCopy = events
        lock.unlock()

        UserDefaults(suiteName: AvoBatcher.suiteKey)?.set(eventsCopy, forKey: AvoBatcher.cacheKey)
    }

    @objc public func enterForeground() {
        let memoryEvents = UserDefaults(suiteName: AvoBatcher.suiteKey)?.object(forKey: AvoBatcher.cacheKey) as? [Any]

        lock.lock()
        if let memoryEvents = memoryEvents {
            events = memoryEvents
        } else {
            events = [Any]()
        }
        lock.unlock()

        postAllAvailableEventsAndClearCache(true)
    }

    // MARK: - Private

    private func saveAndLogEvent(_ trackSchemaBody: NSMutableDictionary,
                                  schema: [String: AvoEventSchemaType],
                                  eventName: String) {
        saveEvent(trackSchemaBody)

        if AvoInspector.isLogging() {
            var schemaString = ""
            for (key, value) in schema {
                schemaString += "\t\"\(key)\": \"\(value.name())\";\n"
            }
            NSLog("[avo] Avo Inspector: Saved event %@ with schema {\n%@}", eventName, schemaString)
        }

        checkIfBatchNeedsToBeSent()
    }

    private func saveEvent(_ trackSchemaBody: NSMutableDictionary) {
        lock.lock()
        events.append(trackSchemaBody)
        lock.unlock()

        removeExtraElements()
    }

    private func removeExtraElements() {
        lock.lock()
        if events.count > 1000 {
            let extraElements = events.count - 1000
            if extraElements > 0 {
                events.removeFirst(extraElements)
            }
        }
        lock.unlock()
    }

    private func checkIfBatchNeedsToBeSent() {
        lock.lock()
        let batchSize = events.count
        lock.unlock()

        let now = Date().timeIntervalSince1970
        let timeSinceLastFlushAttempt = now - batchFlushAttemptTime

        let sendBySize = batchSize % Int(AvoInspector.getBatchSize()) == 0
        let sendByTime = timeSinceLastFlushAttempt >= Double(AvoInspector.getBatchFlushSeconds())

        if sendBySize || sendByTime {
            postAllAvailableEventsAndClearCache(false)
        }
    }

    private func postAllAvailableEventsAndClearCache(_ shouldClearCache: Bool) {
        filterEvents()

        lock.lock()
        let count = events.count
        lock.unlock()

        if count == 0 {
            if shouldClearCache {
                UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
            }
            return
        }

        batchFlushAttemptTime = Date().timeIntervalSince1970

        lock.lock()
        let sendingEvents = events
        events = [Any]()
        lock.unlock()

        networkCallsHandler.callInspectorWithBatchBody(sendingEvents) { [weak self] error in
            if shouldClearCache {
                UserDefaults(suiteName: AvoBatcher.suiteKey)?.removeObject(forKey: AvoBatcher.cacheKey)
            }

            if error != nil {
                self?.lock.lock()
                self?.events.insert(contentsOf: sendingEvents, at: 0)
                self?.lock.unlock()
            }
        }
    }

    private func filterEvents() {
        lock.lock()
        events = events.filter { event in
            guard let dict = event as? NSDictionary else { return false }
            return dict["type"] != nil
        }
        lock.unlock()
    }
}
