import Foundation

@objc public class AvoNetworkCallsHandler: NSObject {

    @objc public let apiKey: String
    @objc public let appName: String
    @objc public let appVersion: String
    @objc public let libVersion: String

    private var env: Int
    private var endpoint: String
    private var publicEncryptionKey: String?
    private var samplingRate: Double = 1.0
    private let samplingRateLock = NSLock()
    private var urlSession: URLSession

    @objc public init(apiKey: String, appName: String, appVersion: String,
                      libVersion: String, env: Int, endpoint: String) {
        self.apiKey = apiKey
        self.appName = appName
        self.appVersion = appVersion
        self.libVersion = libVersion
        self.env = env
        self.endpoint = endpoint
        self.publicEncryptionKey = nil
        self.samplingRate = 1.0
        self.urlSession = URLSession.shared
        super.init()
    }

    @objc public init(apiKey: String, appName: String, appVersion: String,
                      libVersion: String, env: Int, endpoint: String,
                      publicEncryptionKey: String?) {
        self.apiKey = apiKey
        self.appName = appName
        self.appVersion = appVersion
        self.libVersion = libVersion
        self.env = env
        self.endpoint = endpoint
        self.publicEncryptionKey = publicEncryptionKey
        self.samplingRate = 1.0
        self.urlSession = URLSession.shared
        super.init()
    }

    // MARK: - Body Building

    @objc public func bodyForTrackSchemaCall(_ eventName: String,
                                              schema: [String: AvoEventSchemaType],
                                              eventId: String?,
                                              eventHash: String?) -> NSMutableDictionary {
        return bodyForTrackSchemaCall(eventName, schema: schema, eventId: eventId,
                                      eventHash: eventHash, eventProperties: nil)
    }

    @objc public func bodyForTrackSchemaCall(_ eventName: String,
                                              schema: [String: AvoEventSchemaType],
                                              eventId: String?,
                                              eventHash: String?,
                                              eventProperties: [String: Any]?) -> NSMutableDictionary {
        let propsSchema = NSMutableArray()

        for (key, schemaType) in schema {
            let value = schemaType.name()
            let prop = NSMutableDictionary()
            prop["propertyName"] = key

            if schemaType is AvoObject {
                if let data = value.data(using: .utf8),
                   let nestedSchema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    prop["propertyType"] = "object"
                    prop["children"] = bodyFromJson(nestedSchema)
                }
            } else {
                prop["propertyType"] = value
            }
            propsSchema.add(prop)
        }

        if shouldEncrypt(), let eventProperties = eventProperties {
            AvoNetworkCallsHandler.addEncryptedValues(propsSchema, eventProperties: eventProperties,
                                                       publicEncryptionKey: publicEncryptionKey!)
        }

        let baseBody = createBaseCallBody()

        if let eventId = eventId {
            baseBody["avoFunction"] = true
            baseBody["eventId"] = eventId
            baseBody["eventHash"] = eventHash
        } else {
            baseBody["avoFunction"] = false
        }

        baseBody["type"] = "event"
        baseBody["eventName"] = eventName
        baseBody["eventProperties"] = propsSchema

        return baseBody
    }

    @objc public func bodyForValidatedEventSchemaCall(_ eventName: String,
                                                       schema: [String: AvoEventSchemaType],
                                                       eventId: String?,
                                                       eventHash: String?,
                                                       validationResult: AvoValidationResult,
                                                       streamId: String) -> NSMutableDictionary {
        return bodyForValidatedEventSchemaCall(eventName, schema: schema, eventId: eventId,
                                                eventHash: eventHash, validationResult: validationResult,
                                                streamId: streamId, eventProperties: nil)
    }

    @objc public func bodyForValidatedEventSchemaCall(_ eventName: String,
                                                       schema: [String: AvoEventSchemaType],
                                                       eventId: String?,
                                                       eventHash: String?,
                                                       validationResult: AvoValidationResult,
                                                       streamId: String,
                                                       eventProperties: [String: Any]?) -> NSMutableDictionary {
        let propsSchema = NSMutableArray()

        for (key, schemaType) in schema {
            let value = schemaType.name()
            let prop = NSMutableDictionary()
            prop["propertyName"] = key

            if schemaType is AvoObject {
                if let data = value.data(using: .utf8),
                   let nestedSchema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    prop["propertyType"] = "object"
                    prop["children"] = bodyFromJson(nestedSchema)
                }
            } else {
                prop["propertyType"] = value
            }

            // Add validation results for this property
            if let propResult = validationResult.propertyResults[key] {
                addValidation(to: prop, result: propResult)
            }

            propsSchema.add(prop)
        }

        if shouldEncrypt(), let eventProperties = eventProperties {
            AvoNetworkCallsHandler.addEncryptedValues(propsSchema, eventProperties: eventProperties,
                                                       publicEncryptionKey: publicEncryptionKey!)
        }

        let baseBody = createBaseCallBody()

        if let eventId = eventId {
            baseBody["avoFunction"] = true
            baseBody["eventId"] = eventId
            baseBody["eventHash"] = eventHash
        } else {
            baseBody["avoFunction"] = false
        }

        baseBody["type"] = "event"
        baseBody["eventName"] = eventName
        baseBody["eventProperties"] = propsSchema
        baseBody["streamId"] = streamId

        // Add event spec metadata
        if let metadata = validationResult.metadata {
            let metadataDict = NSMutableDictionary()
            if !metadata.schemaId.isEmpty {
                metadataDict["schemaId"] = metadata.schemaId
            }
            if !metadata.branchId.isEmpty {
                metadataDict["branchId"] = metadata.branchId
            }
            if !metadata.latestActionId.isEmpty {
                metadataDict["latestActionId"] = metadata.latestActionId
            }
            if let sourceId = metadata.sourceId {
                metadataDict["sourceId"] = sourceId
            }
            baseBody["eventSpecMetadata"] = metadataDict
        }

        return baseBody
    }

    private func bodyFromJson(_ schema: [String: Any]) -> NSMutableArray {
        let propsSchema = NSMutableArray()

        for (key, value) in schema {
            let prop = NSMutableDictionary()
            prop["propertyName"] = key

            if let dictValue = value as? [String: Any] {
                prop["propertyType"] = "object"
                prop["children"] = bodyFromJson(dictValue)
            } else {
                prop["propertyType"] = value
            }
            propsSchema.add(prop)
        }

        return propsSchema
    }

    private func addValidation(to prop: NSMutableDictionary, result: AvoPropertyValidationResult) {
        if let failedIds = result.failedEventIds {
            prop["failedEventIds"] = failedIds
        }
        if let passedIds = result.passedEventIds {
            prop["passedEventIds"] = passedIds
        }
        if let children = result.children {
            if let existingChildren = prop["children"] as? NSMutableArray {
                for case let childProp as NSMutableDictionary in existingChildren {
                    if let childName = childProp["propertyName"] as? String,
                       let childResult = children[childName] {
                        addValidation(to: childProp, result: childResult)
                    }
                }
            }
        }
    }

    // MARK: - Base Body

    private func createBaseCallBody() -> NSMutableDictionary {
        let body = NSMutableDictionary()
        body["apiKey"] = apiKey
        body["appName"] = appName
        body["appVersion"] = appVersion
        body["libVersion"] = libVersion
        samplingRateLock.lock()
        let currentRate = samplingRate
        samplingRateLock.unlock()
        body["samplingRate"] = NSNumber(value: currentRate)
        body["sessionId"] = ""
        body["trackingId"] = ""
        body["anonymousId"] = AvoAnonymousId.anonymousId()
        body["env"] = AvoNetworkCallsHandler.formatTypeToString(Int32(env))
        body["libPlatform"] = "ios"
        body["messageId"] = UUID().uuidString
        body["createdAt"] = AvoUtils.currentTimeAsISO8601UTCString()

        if let key = publicEncryptionKey, !key.isEmpty {
            body["publicEncryptionKey"] = key
        }

        return body
    }

    // MARK: - Network Calls

    @objc public func callInspectorWithBatchBody(_ batchBody: [Any],
                                                  completionHandler: @escaping (Error?) -> Void) {
        samplingRateLock.lock()
        let currentSamplingRate = samplingRate
        samplingRateLock.unlock()

        if drand48() > currentSamplingRate {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Last event schema dropped due to sampling rate")
            }
            completionHandler(nil)
            return
        }

        if AvoInspector.isLogging() {
            for case let batchItem as [String: Any] in batchBody {
                if let type = batchItem["type"] as? String {
                    if type == "event" {
                        let eventName = batchItem["eventName"] ?? ""
                        let eventProps = batchItem["eventProperties"] ?? ""
                        NSLog("[avo] Avo Inspector: Sending event %@ with schema {\n%@\n}\n",
                              "\(eventName)", "\(eventProps)")
                    } else {
                        NSLog("[avo] Avo Inspector: Error! Unknown event type.")
                    }
                }
            }
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: batchBody, options: .prettyPrinted) else {
            completionHandler(nil)
            return
        }

        guard let url = URL(string: endpoint) else {
            NSLog("[avo] Avo Inspector: Invalid endpoint URL: %@", endpoint)
            completionHandler(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        writeCallHeader(&request)
        request.httpBody = bodyData

        sendHttpRequest(request, completionHandler: completionHandler)
    }

    private func sendHttpRequest(_ request: URLRequest,
                                  completionHandler: @escaping (Error?) -> Void) {
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            if error == nil {
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    if AvoInspector.isLogging() {
                        NSLog("[avo] Avo Inspector: Failed sending events. HTTP status: %d", http.statusCode)
                    }
                    let httpError = NSError(domain: "AvoInspector.Network", code: http.statusCode,
                                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                    completionHandler(httpError)
                    return
                }

                if let data = data,
                   let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rate = responseJSON["samplingRate"] as? Double {
                    self?.samplingRateLock.lock()
                    self?.samplingRate = rate
                    self?.samplingRateLock.unlock()
                }

                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Successfully sent events.")
                }
            } else if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Failed sending events. Will retry later.")
            }

            completionHandler(error)
        }
        task.resume()
    }

    private func writeCallHeader(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    // MARK: - Validated Event Reporting

    @objc public func reportValidatedEvent(_ body: [String: Any]) {
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: [body], options: [])

            guard let url = URL(string: endpoint) else {
                NSLog("[avo] Avo Inspector: Invalid endpoint URL: %@", endpoint)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5.0
            writeCallHeader(&request)
            request.httpBody = bodyData

            let task = urlSession.dataTask(with: request) { _, response, taskError in
                if let taskError = taskError {
                    if AvoInspector.isLogging() {
                        NSLog("[avo] Avo Inspector: Failed to send validated event: %@", taskError.localizedDescription)
                    }
                } else if let http = response as? HTTPURLResponse,
                          !(200...299).contains(http.statusCode) {
                    if AvoInspector.isLogging() {
                        NSLog("[avo] Avo Inspector: Failed to send validated event. HTTP status: %d", http.statusCode)
                    }
                } else if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Successfully sent validated event.")
                }
            }
            task.resume()
        } catch {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Failed to serialize validated event body: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    @objc public class func formatTypeToString(_ formatType: Int32) -> String {
        switch formatType {
        case 0: return "prod"
        case 1: return "dev"
        case 2: return "staging"
        default:
            NSLog("[avo] Avo Inspector: WARNING - Unexpected FormatType %d, defaulting to dev", formatType)
            return "dev"
        }
    }

    // MARK: - Encryption

    @objc public func shouldEncrypt() -> Bool {
        guard let key = publicEncryptionKey, !key.isEmpty else { return false }
        return env == 1 || env == 2 // dev = 1, staging = 2
    }

    @objc public class func jsonStringifyValue(_ value: Any) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [value], options: []) else {
            return nil
        }
        guard let json = String(data: jsonData, encoding: .utf8), json.count >= 2 else {
            return nil
        }
        // Strip surrounding brackets: [value] -> value
        let startIndex = json.index(after: json.startIndex)
        let endIndex = json.index(before: json.endIndex)
        return String(json[startIndex..<endIndex])
    }

    private class func addEncryptedValues(_ properties: NSMutableArray,
                                           eventProperties: [String: Any],
                                           publicEncryptionKey: String) {
        for i in 0..<properties.count {
            guard let prop = properties[i] as? NSMutableDictionary,
                  let propertyName = prop["propertyName"] as? String,
                  let propertyType = prop["propertyType"] as? String else {
                continue
            }

            guard let value = eventProperties[propertyName] else { continue }

            if propertyType == "object",
               let children = prop["children"] as? NSMutableArray,
               let dictValue = value as? [String: Any] {
                addEncryptedValues(children, eventProperties: dictValue, publicEncryptionKey: publicEncryptionKey)
            } else if !propertyType.hasPrefix("list") {
                if #available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *) {
                    if let jsonValue = jsonStringifyValue(value),
                       let encrypted = AvoEncryption.encrypt(jsonValue, recipientPublicKeyHex: publicEncryptionKey) {
                        prop["encryptedPropertyValue"] = encrypted
                    }
                }
            }
        }
    }
}
