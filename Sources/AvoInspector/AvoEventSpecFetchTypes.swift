import Foundation

// MARK: - Wire Types

@objc public class AvoPropertyConstraintsWire: NSObject {
    @objc public var t: String = ""
    @objc public var r: Bool = false
    @objc public var l: NSNumber?
    @objc public var p: [String: [String]]?
    @objc public var v: [String: [String]]?
    @objc public var rx: [String: [String]]?
    @objc public var minmax: [String: [String]]?
    @objc public var children: [String: AvoPropertyConstraintsWire]?

    @objc public init(dictionary dict: [String: Any]) {
        super.init()
        t = dict["t"] as? String ?? ""
        r = (dict["r"] as? NSNumber)?.boolValue ?? false
        l = dict["l"] as? NSNumber

        p = dict["p"] as? [String: [String]]
        v = dict["v"] as? [String: [String]]
        rx = dict["rx"] as? [String: [String]]
        minmax = dict["minmax"] as? [String: [String]]

        if let childrenDict = dict["children"] as? [String: [String: Any]] {
            var parsedChildren = [String: AvoPropertyConstraintsWire]()
            for (key, value) in childrenDict {
                parsedChildren[key] = AvoPropertyConstraintsWire(dictionary: value)
            }
            children = parsedChildren
        }
    }
}

@objc public class AvoEventSpecEntryWire: NSObject {
    @objc public var b: String = ""
    @objc public var eventId: String = ""
    @objc public var vids: [String] = []
    @objc public var p: [String: AvoPropertyConstraintsWire] = [:]

    @objc public init(dictionary dict: [String: Any]) {
        super.init()
        b = dict["b"] as? String ?? ""
        eventId = dict["id"] as? String ?? ""
        vids = dict["vids"] as? [String] ?? []

        if let propsDict = dict["p"] as? [String: [String: Any]] {
            var parsedProps = [String: AvoPropertyConstraintsWire]()
            for (key, value) in propsDict {
                parsedProps[key] = AvoPropertyConstraintsWire(dictionary: value)
            }
            p = parsedProps
        }
    }
}

@objc public class AvoEventSpecMetadata: NSObject {
    @objc public var schemaId: String = ""
    @objc public var branchId: String = ""
    @objc public var latestActionId: String = ""
    @objc public var sourceId: String?

    @objc public init(dictionary dict: [String: Any]) {
        super.init()
        schemaId = dict["schemaId"] as? String ?? ""
        branchId = dict["branchId"] as? String ?? ""
        latestActionId = dict["latestActionId"] as? String ?? ""
        sourceId = dict["sourceId"] as? String
    }

    override init() {
        super.init()
    }
}

@objc public class AvoEventSpecResponseWire: NSObject {
    @objc public var events: [AvoEventSpecEntryWire] = []
    @objc public var metadata: AvoEventSpecMetadata?

    @objc public init(dictionary dict: [String: Any]) {
        super.init()
        if let eventsArray = dict["events"] as? [[String: Any]] {
            events = eventsArray.map { AvoEventSpecEntryWire(dictionary: $0) }
        }
        if let metadataDict = dict["metadata"] as? [String: Any] {
            metadata = AvoEventSpecMetadata(dictionary: metadataDict)
        }
    }
}

// MARK: - Internal Types

@objc public class AvoPropertyConstraints: NSObject {
    @objc public var type: String = ""
    @objc public var required: Bool = false
    @objc public var isList: NSNumber?
    @objc public var pinnedValues: [String: [String]]?
    @objc public var allowedValues: [String: [String]]?
    @objc public var regexPatterns: [String: [String]]?
    @objc public var minMaxRanges: [String: [String]]?
    @objc public var children: [String: AvoPropertyConstraints]?

    @objc public init(fromWire wire: AvoPropertyConstraintsWire) {
        super.init()
        type = wire.t
        required = wire.r
        isList = wire.l
        pinnedValues = wire.p
        allowedValues = wire.v
        regexPatterns = wire.rx
        minMaxRanges = wire.minmax

        if let wireChildren = wire.children {
            var parsedChildren = [String: AvoPropertyConstraints]()
            for (key, value) in wireChildren {
                parsedChildren[key] = AvoPropertyConstraints(fromWire: value)
            }
            children = parsedChildren
        }
    }

    override init() {
        super.init()
    }
}

@objc public class AvoEventSpecEntry: NSObject {
    @objc public var branchId: String = ""
    @objc public var baseEventId: String = ""
    @objc public var variantIds: [String] = []
    @objc public var props: [String: AvoPropertyConstraints] = [:]

    @objc public init(fromWire wire: AvoEventSpecEntryWire) {
        super.init()
        branchId = wire.b
        baseEventId = wire.eventId
        variantIds = wire.vids

        var parsedProps = [String: AvoPropertyConstraints]()
        for (key, value) in wire.p {
            parsedProps[key] = AvoPropertyConstraints(fromWire: value)
        }
        props = parsedProps
    }
}

@objc public class AvoEventSpecResponse: NSObject {
    @objc public var events: [AvoEventSpecEntry] = []
    @objc public var metadata: AvoEventSpecMetadata?

    @objc public init(fromWire wire: AvoEventSpecResponseWire) {
        super.init()
        events = wire.events.map { AvoEventSpecEntry(fromWire: $0) }
        metadata = wire.metadata
    }

    override init() {
        super.init()
    }
}

// MARK: - Cache / Params / Validation Result Types

@objc public class AvoEventSpecCacheEntry: NSObject {
    @objc public var spec: AvoEventSpecResponse?
    @objc public var timestamp: Int64
    @objc public var lastAccessed: Int64
    @objc public var eventCount: Int32 = 0

    @objc public init(spec: AvoEventSpecResponse?, timestamp: Int64) {
        self.spec = spec
        self.timestamp = timestamp
        self.lastAccessed = timestamp
        super.init()
    }
}

@objc public class AvoFetchEventSpecParams: NSObject {
    @objc public var apiKey: String
    @objc public var streamId: String
    @objc public var eventName: String

    @objc public init(apiKey: String, streamId: String, eventName: String) {
        self.apiKey = apiKey
        self.streamId = streamId
        self.eventName = eventName
        super.init()
    }
}

@objc public class AvoPropertyValidationResult: NSObject {
    @objc public var failedEventIds: [String]?
    @objc public var passedEventIds: [String]?
    @objc public var children: [String: AvoPropertyValidationResult]?

    override init() {
        super.init()
    }
}

@objc public class AvoValidationResult: NSObject {
    @objc public var metadata: AvoEventSpecMetadata?
    @objc public var propertyResults: [String: AvoPropertyValidationResult] = [:]

    override init() {
        super.init()
    }
}
