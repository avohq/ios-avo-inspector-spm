import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Enums

@objc public enum AvoInspectorEnv: UInt {
    case prod = 0
    case dev = 1
    case staging = 2
}

@objc public enum AvoVisualInspectorType: UInt {
    @objc(Bar) case bar = 0
    @objc(Bubble) case bubble = 1
}

// MARK: - Inspector Protocol

// NOTE: The ObjC `Inspector` protocol uses `+` class methods for the static members below.
// In ObjC, `+` methods can be overridden by subclasses. Swift `static` protocol requirements
// cannot be overridden. This is an intentional semantic narrowing — subclassing AvoInspector
// is not a supported use case.
@objc public protocol Inspector: NSObjectProtocol {
    func trackSchema(fromEvent eventName: String, eventParams params: [String: Any]) -> [String: AvoEventSchemaType]
    func trackSchema(_ eventName: String, eventSchema schema: [String: AvoEventSchemaType])
    func extractSchema(_ eventParams: [String: Any]) -> [String: AvoEventSchemaType]
    static func isLogging() -> Bool
    static func setLogging(_ isLogging: Bool)
    static func getBatchSize() -> Int32
    static func setBatchSize(_ newBatchSize: Int32)
    static func getBatchFlushSeconds() -> Int32
    static func setBatchFlushSeconds(_ newBatchFlushSeconds: Int32)
}

// MARK: - Storage Implementation

private class AvoStorageImpl: NSObject, AvoStorage {
    func isInitialized() -> Bool { return true }
    func getItem(_ key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }
    func setItem(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

// MARK: - AvoInspector

@objc public class AvoInspector: NSObject, Inspector {

    @objc public private(set) var appVersion: String
    @objc public private(set) var libVersion: String
    @objc public private(set) var apiKey: String
    private var appName: String

    // NOTE: These static vars are intentionally unsynchronized, matching ObjC behavior.
    // The ObjC code uses plain C statics with no synchronization for these values.
    private static var logging = false
    private static var maxBatchSize: Int32 = 30
    private static var batchFlushTime: Int32 = 30

    // From ObjC: `static const NSTimeInterval EVENT_SPEC_FETCH_TIMEOUT = 5.0;`
    private static let eventSpecFetchTimeout: TimeInterval = 5.0

    private var networkCallsHandler: AvoNetworkCallsHandler
    private var avoBatcher: AvoBatcher
    private var avoDeduplicator: AvoDeduplicator
    private var avoSchemaExtractor: AvoSchemaExtractor

    private var notificationCenter: NotificationCenter

    private var env: AvoInspectorEnv

    private var eventSpecFetcher: AvoEventSpecFetcher?
    private var eventSpecCache: AvoEventSpecCache?
    private var currentBranchId: String?
    private var publicEncryptionKey: String?

    private let branchLock = NSLock()

    // MARK: - Storage Singleton

    private static let sharedStorage = AvoStorageImpl()

    @objc public class func avoStorage() -> AvoStorage {
        return sharedStorage
    }

    // MARK: - Static Accessors (Inspector protocol)

    @objc public static func isLogging() -> Bool {
        return logging
    }

    @objc public static func setLogging(_ isLogging: Bool) {
        logging = isLogging
    }

    @objc public static func getBatchSize() -> Int32 {
        return maxBatchSize
    }

    @objc public static func setBatchSize(_ newBatchSize: Int32) {
        if newBatchSize < 1 {
            maxBatchSize = 1
        } else {
            maxBatchSize = newBatchSize
        }
    }

    @objc public static func getBatchFlushSeconds() -> Int32 {
        return batchFlushTime
    }

    @objc public static func setBatchFlushSeconds(_ newBatchFlushSeconds: Int32) {
        batchFlushTime = newBatchFlushSeconds
    }

    // MARK: - Initializers

    @objc public convenience init(apiKey: String, env: AvoInspectorEnv) {
        self.init(apiKey: apiKey, env: env,
                  proxyEndpoint: "https://api.avo.app/inspector/v1/track",
                  publicEncryptionKey: nil)
    }

    @objc public convenience init(apiKey: String, envInt: NSNumber) {
        // NOTE: Intentional divergence from ObjC which uses `[envInt intValue]`.
        // Using `uintValue` with `?? .dev` fallback is an improvement: negative values
        // fall through to .dev instead of undefined enum behavior. For valid values
        // (0, 1, 2) behavior is identical.
        self.init(apiKey: apiKey, env: AvoInspectorEnv(rawValue: envInt.uintValue) ?? .dev)
    }

    @objc public convenience init(apiKey: String, env: AvoInspectorEnv, proxyEndpoint: String) {
        self.init(apiKey: apiKey, env: env, proxyEndpoint: proxyEndpoint, publicEncryptionKey: nil)
    }

    @objc public convenience init(apiKey: String, env: AvoInspectorEnv,
                                   publicEncryptionKey: String?) {
        self.init(apiKey: apiKey, env: env,
                  proxyEndpoint: "https://api.avo.app/inspector/v1/track",
                  publicEncryptionKey: publicEncryptionKey)
    }

    @objc public init(apiKey: String, env: AvoInspectorEnv,
                      proxyEndpoint: String, publicEncryptionKey: String?) {
        // Validate env, fallback to .dev
        if env != .prod && env != .dev && env != .staging {
            self.env = .dev
        } else {
            self.env = env
        }

        self.publicEncryptionKey = publicEncryptionKey
        self.avoSchemaExtractor = AvoSchemaExtractor()

        if self.env == .dev {
            AvoInspector.setBatchSize(1)
            AvoInspector.setLogging(true)
        } else {
            AvoInspector.setBatchSize(30)
            AvoInspector.setBatchFlushSeconds(30)
            AvoInspector.setLogging(false)
        }

        self.appName = Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String ?? ""
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        self.libVersion = "4.0.0"
        self.apiKey = apiKey

        self.notificationCenter = NotificationCenter.default

        self.networkCallsHandler = AvoNetworkCallsHandler(
            apiKey: apiKey, appName: self.appName, appVersion: self.appVersion,
            libVersion: self.libVersion, env: Int(self.env.rawValue),
            endpoint: proxyEndpoint, publicEncryptionKey: publicEncryptionKey)

        self.avoBatcher = AvoBatcher(networkCallsHandler: self.networkCallsHandler)
        self.avoDeduplicator = AvoDeduplicator.sharedDeduplicator

        super.init()

        if let key = publicEncryptionKey, !key.isEmpty, self.env != .prod {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Property value encryption enabled")
            }
        }

        // Initialize event spec fetcher and cache for non-prod environments
        // streamId is the anonymous ID, obtained internally from AvoAnonymousId
        if self.env != .prod {
            let streamId = AvoAnonymousId.anonymousId()
            if !streamId.isEmpty && streamId != "unknown" {
                let envString = AvoNetworkCallsHandler.formatTypeToString(Int32(self.env.rawValue))
                self.eventSpecFetcher = AvoEventSpecFetcher(
                    timeout: AvoInspector.eventSpecFetchTimeout, env: envString)
                self.eventSpecCache = AvoEventSpecCache()

                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Event spec fetcher initialized for env: %@, streamId: %@",
                          envString, streamId)
                }
            }
        }

        enterForeground()

        addObservers()
    }

    // Internal init with injectable dependencies — used by tests only
    internal init(apiKey: String, env: AvoInspectorEnv, storage: AvoStorage,
                  networkCallsHandler: AvoNetworkCallsHandler,
                  batcher: AvoBatcher,
                  deduplicator: AvoDeduplicator) {
        self.env = env
        self.apiKey = apiKey
        self.appName = Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String ?? ""
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        self.libVersion = "4.0.0"
        self.avoSchemaExtractor = AvoSchemaExtractor()
        self.notificationCenter = NotificationCenter.default
        self.networkCallsHandler = networkCallsHandler
        self.avoBatcher = batcher
        self.avoDeduplicator = deduplicator
        super.init()
    }

    // Internal init with injectable dependencies including event spec — used by validation flow tests
    internal init(apiKey: String, env: AvoInspectorEnv, storage: AvoStorage,
                  networkCallsHandler: AvoNetworkCallsHandler,
                  batcher: AvoBatcher,
                  deduplicator: AvoDeduplicator,
                  eventSpecFetcher: AvoEventSpecFetcher?,
                  eventSpecCache: AvoEventSpecCache?) {
        self.env = env
        self.apiKey = apiKey
        self.appName = Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String ?? ""
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        self.libVersion = "4.0.0"
        self.avoSchemaExtractor = AvoSchemaExtractor()
        self.notificationCenter = NotificationCenter.default
        self.networkCallsHandler = networkCallsHandler
        self.avoBatcher = batcher
        self.avoDeduplicator = deduplicator
        self.eventSpecFetcher = eventSpecFetcher
        self.eventSpecCache = eventSpecCache
        super.init()
    }

    // MARK: - Notification Observers

    private func addObservers() {
        #if canImport(UIKit)
        notificationCenter.addObserver(self,
            selector: #selector(enterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil)

        notificationCenter.addObserver(self,
            selector: #selector(enterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
        #endif
    }

    // MARK: - Lifecycle

    @objc public func enterBackground() {
        avoBatcher.enterBackground()
    }

    @objc public func enterForeground() {
        avoBatcher.enterForeground()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    // MARK: - Public API (Inspector protocol)

    @objc public func trackSchema(fromEvent eventName: String,
                                   eventParams params: [String: Any]) -> [String: AvoEventSchemaType] {
        if avoDeduplicator.shouldRegisterEvent(eventName, eventParams: params, fromAvoFunction: false) {
            return internalTrackSchemaFromEvent(eventName, eventParams: params, eventId: nil, eventHash: nil)
        } else {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Deduplicated event %@", eventName)
            }
            return [String: AvoEventSchemaType]()
        }
    }

    @objc public func trackSchema(_ eventName: String,
                                   eventSchema schema: [String: AvoEventSchemaType]) {
        if avoDeduplicator.shouldRegisterSchemaFromManually(eventName, schema: schema) {
            internalTrackSchema(eventName, eventSchema: schema, eventId: nil, eventHash: nil, eventProperties: nil)
        } else {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Deduplicated schema %@", eventName)
            }
        }
    }

    @objc public func extractSchema(_ eventParams: [String: Any]) -> [String: AvoEventSchemaType] {
        if !avoDeduplicator.hasSeenEventParams(eventParams, checkInAvoFunctions: true) {
            NSLog("[avo]     WARNING! You are trying to extract schema shape that was just reported by your Avo functions. This is an indicator of duplicate inspector reporting. Please reach out to support@avo.app for advice if you are not sure how to handle this.")
        }

        return avoSchemaExtractor.extractSchema(eventParams)
    }

    // MARK: - Internal API (Avo Functions)

    @objc public func avoFunctionTrackSchemaFromEvent(_ eventName: String,
                                                       eventParams params: NSMutableDictionary) -> [String: AvoEventSchemaType] {
        guard let swiftParams = params as? [String: Any] else {
            return [String: AvoEventSchemaType]()
        }

        if avoDeduplicator.shouldRegisterEvent(eventName, eventParams: swiftParams, fromAvoFunction: true) {
            var objcParams = [String: Any]()

            for (paramName, paramValue) in swiftParams {
                objcParams[paramName] = paramValue
            }

            let eventId = objcParams["avoFunctionEventId"] as? String
            objcParams.removeValue(forKey: "avoFunctionEventId")
            let eventHash = objcParams["avoFunctionEventHash"] as? String
            objcParams.removeValue(forKey: "avoFunctionEventHash")

            return internalTrackSchemaFromEvent(eventName, eventParams: objcParams, eventId: eventId, eventHash: eventHash)
        } else {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Deduplicated event %@", eventName)
            }
            return [String: AvoEventSchemaType]()
        }
    }

    // MARK: - Internal Tracking

    private func internalTrackSchemaFromEvent(_ eventName: String,
                                               eventParams params: [String: Any],
                                               eventId: String?,
                                               eventHash: String?) -> [String: AvoEventSchemaType] {
        if AvoInspector.isLogging() {
            NSLog("[avo] Avo Inspector: Supplied event %@ with params %@", eventName, "\(params)")
        }

        let schema = avoSchemaExtractor.extractSchema(params)

        fetchAndValidateAsync(eventName, eventParams: params, eventSchema: schema,
                              eventId: eventId, eventHash: eventHash, eventProperties: params)

        return schema
    }

    private func internalTrackSchema(_ eventName: String,
                                      eventSchema schema: [String: AvoEventSchemaType],
                                      eventId: String?,
                                      eventHash: String?,
                                      eventProperties: [String: Any]?) {
        if let eventProperties = eventProperties, !eventProperties.isEmpty {
            avoBatcher.handleTrackSchema(eventName, schema: schema, eventId: eventId,
                                          eventHash: eventHash, eventProperties: eventProperties)
        } else {
            avoBatcher.handleTrackSchema(eventName, schema: schema, eventId: eventId,
                                          eventHash: eventHash)
        }
    }

    // MARK: - Event Spec Fetch & Validate

    private func fetchAndValidateAsync(_ eventName: String,
                                        eventParams params: [String: Any],
                                        eventSchema schema: [String: AvoEventSchemaType],
                                        eventId: String?,
                                        eventHash: String?,
                                        eventProperties: [String: Any]?) {
        // If no fetcher (prod, etc.), fall through to existing path
        let streamId = AvoAnonymousId.anonymousId()
        if eventSpecFetcher == nil || eventSpecCache == nil || streamId == "unknown" || params.isEmpty {
            internalTrackSchema(eventName, eventSchema: schema, eventId: eventId,
                                eventHash: eventHash, eventProperties: eventProperties)
            return
        }

        let cacheKey = AvoEventSpecCache.generateKey(apiKey, streamId: streamId, eventName: eventName)

        // Check cache first
        if eventSpecCache!.contains(cacheKey) {
            let cachedSpec = eventSpecCache!.get(cacheKey)
            if let cachedSpec = cachedSpec {
                let validationResult = AvoEventValidator.validateEvent(params, specResponse: cachedSpec)
                if let validationResult = validationResult {
                    sendEventWithValidation(eventName, schema: schema, eventId: eventId,
                                            eventHash: eventHash, validationResult: validationResult,
                                            eventProperties: eventProperties)
                    return
                }
            }
            // Cache hit but nil spec or no validation result - use existing path
            internalTrackSchema(eventName, eventSchema: schema, eventId: eventId,
                                eventHash: eventHash, eventProperties: eventProperties)
            return
        }

        // Cache miss: fetch spec, validate, then send (aligned with Android/JS implementation)
        if AvoInspector.isLogging() {
            NSLog("[avo] Avo Inspector: Event spec cache miss for event: %@. Fetching before sending.", eventName)
        }

        let fetchParams = AvoFetchEventSpecParams(apiKey: apiKey, streamId: streamId, eventName: eventName)

        // Defensive copy to prevent caller mutations affecting async validation
        let capturedParams = params
        let capturedEventProperties = eventProperties

        weak var weakSelf = self
        eventSpecFetcher!.fetchEventSpec(fetchParams) { specResponse in
            guard let strongSelf = weakSelf else { return }

            if let specResponse = specResponse {
                strongSelf.handleBranchChangeAndCache(cacheKey, specResponse: specResponse)

                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Cached event spec for: %@", eventName)
                }

                // Validate and send the validated event
                let validationResult = AvoEventValidator.validateEvent(capturedParams, specResponse: specResponse)
                if let validationResult = validationResult {
                    strongSelf.sendEventWithValidation(eventName, schema: schema, eventId: eventId,
                                                        eventHash: eventHash, validationResult: validationResult,
                                                        eventProperties: capturedEventProperties)
                } else {
                    // Validation returned nil — send through batched path
                    strongSelf.internalTrackSchema(eventName, eventSchema: schema, eventId: eventId,
                                                    eventHash: eventHash, eventProperties: capturedEventProperties)
                }
            } else {
                // Cache nil to avoid re-fetching within TTL, send through batched path
                strongSelf.eventSpecCache?.set(cacheKey, spec: nil)
                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Event spec fetch returned nil for event: %@. Cached empty response. Sending without validation.", eventName)
                }
                strongSelf.internalTrackSchema(eventName, eventSchema: schema, eventId: eventId,
                                                eventHash: eventHash, eventProperties: capturedEventProperties)
            }
        }
    }

    private func handleBranchChangeAndCache(_ cacheKey: String,
                                             specResponse: AvoEventSpecResponse) {
        branchLock.lock()
        defer { branchLock.unlock() }

        if let metadata = specResponse.metadata, !metadata.branchId.isEmpty {
            let newBranchId = metadata.branchId
            if let currentBranch = currentBranchId, currentBranch != newBranchId {
                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Branch changed from %@ to %@, clearing cache",
                          currentBranch, newBranchId)
                }
                eventSpecCache?.clear()
            }
            currentBranchId = newBranchId
        }
        eventSpecCache?.set(cacheKey, spec: specResponse)
    }

    private func sendEventWithValidation(_ eventName: String,
                                          schema: [String: AvoEventSchemaType],
                                          eventId: String?,
                                          eventHash: String?,
                                          validationResult: AvoValidationResult,
                                          eventProperties: [String: Any]?) {
        let streamId = AvoAnonymousId.anonymousId()
        let body = networkCallsHandler.bodyForValidatedEventSchemaCall(
            eventName, schema: schema, eventId: eventId, eventHash: eventHash,
            validationResult: validationResult, streamId: streamId,
            eventProperties: eventProperties)

        if AvoInspector.isLogging() {
            NSLog("[avo] Avo Inspector: Sending validated event %@", eventName)
        }

        guard let bodyDict = body as? [String: Any] else {
            NSLog("[avo] Avo Inspector: Failed to cast validated event body to [String: Any]")
            return
        }
        networkCallsHandler.reportValidatedEvent(bodyDict)
    }

    // MARK: - Error Logging

    private func printAvoGenericError(_ exception: NSException) {
        NSLog("[avo]        ! Avo Inspector Error !")
        NSLog("[avo]        Please report the following error to support@avo.app")
        NSLog("[avo]        CRASH: %@", exception)
        NSLog("[avo]        Stack Trace: %@", exception.callStackSymbols.description)
    }
}
