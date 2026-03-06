# Feature Spec: SPM Swift Migration

**Feature Name:** spm-swift-migration
**Created:** 2026-03-06
**Status:** Draft — Rev 4 (Morticia Rev 3 fixes)

## Problem Statement

The AvoInspectorSPM library is written entirely in Objective-C (.h/.m pairs). This causes two critical problems:

1. **App Store rejection** — `AvoEncryption.m` forward-declares `CCCryptorGCMOneshotEncrypt`, a private/undocumented CommonCrypto symbol. Apple's review tooling flags this as a policy violation, blocking App Store submission. The fix requires CryptoKit, which is Swift-only.

2. **This repo becomes the primary distribution** — The cocoapods repo (`ios-avo-inspector`) is receiving its final ObjC release (v3.0.0) with a thin Swift CryptoKit wrapper. This SPM repo should go full Swift as v4.0.0 and become the canonical distribution going forward.

SDK consumers — iOS developers integrating the Avo Inspector via Swift Package Manager — are blocked from shipping updates due to the App Store rejection.

## Goals

1. Replace all 46 ObjC source files (.h/.m) in `Sources/AvoInspector/` with Swift equivalents, achieving zero ObjC in the main target
2. Rewrite `AvoEncryption` using CryptoKit with the v0x01 wire format (12-byte nonce), eliminating all references to `CCCryptorGCMOneshotEncrypt`
3. Preserve the exact public API surface with `@objc` annotations so existing ObjC and Swift consumers do not break
4. Port all 13 existing SPM test files and 7 cocoapods-only test files, plus add 3 thread-safety test files (23 total) from Specta/Expecta ObjC to Swift XCTest, plus add new encryption tests for v0x01
5. Bump minimum deployment target to iOS 13+ and library version to 4.0.0

## User Stories Overview

- As an **SDK consumer**, I want the AvoInspector SPM package to pass App Store review so that I can ship my app updates
- As an **SDK consumer**, I want the public API to remain unchanged so that I don't need to rewrite my integration code
- As an **SDK consumer using ObjC**, I want all public classes and methods to remain accessible from ObjC so that my mixed-language project still compiles
- As an **Avo engineer**, I want a single Swift codebase for the primary SPM distribution so that maintenance is simplified
- As an **Avo engineer**, I want all existing tests ported and passing so that regression safety is maintained
- As a **security engineer**, I want property value encryption to use documented Apple APIs (CryptoKit) so that the binary contains no private symbol references

## Affected Areas

| Area | Files/Modules | Impact |
|------|--------------|--------|
| Package config | `Package.swift` | iOS 13+ minimum, mixed-language target support |
| Type system | `types/Avo*.h/.m` (9 files, 18 total) | 9 Swift files replacing 18 ObjC files |
| Core inspector | `AvoInspector.h/.m`, `include/*.h` | Main class + public API + storage protocol |
| Schema extraction | `AvoSchemaExtractor.h/.m` | Type-detection logic rewritten in Swift |
| Encryption | `AvoEncryption.h/.m` | Complete CryptoKit rewrite with v0x01 wire format |
| Networking | `AvoNetworkCallsHandler.h/.m` | URLSession-based networking, encryption integration |
| Batching | `AvoBatcher.h/.m` | Event batching with background/foreground persistence |
| Deduplication | `AvoDeduplicator.h/.m` | Event deduplication with `@synchronized` -> serial queue |
| Event validation | `AvoEventValidator.h/.m` | Regex validation with ReDoS timeout pattern |
| Event spec fetch | `AvoEventSpecFetcher.h/.m`, `AvoEventSpecFetchTypes.h/.m`, `AvoEventSpecCache.h/.m` | Spec fetching, type models, LRU cache |
| Utilities | `AvoUtils.h/.m`, `AvoGuid.h/.m`, `AvoAnonymousId.h/.m` | Small helper classes |
| Tests | `Tests/*.m` (14 files in SPM repo: 13 active + 1 commented-out) + 7 cocoapods-only test files + 3 new thread-safety test files | Port from Specta/Expecta to XCTest, add thread-safety tests |

## Existing Patterns to Follow

| Pattern | Where | Why Relevant |
|---------|-------|-------------|
| `@synchronized(self)` for thread safety | `AvoDeduplicator.m`, `AvoEventSpecCache.m`, `AvoInspector.m` | Must become serial `DispatchQueue` or `NSLock` in Swift |
| `dispatch_once` singletons | `AvoDeduplicator.m`, `AvoInspector.m` (avoStorage), `AvoEventValidator.m` (regexQueue) | Use `static let` in Swift (thread-safe by language spec) |
| `dispatch_queue_create` + `dispatch_semaphore` for regex timeout | `AvoEventValidator.m` | Preserve exact ReDoS timeout mechanism in Swift |
| `NSUserDefaults` with suite key for batch persistence | `AvoBatcher.m` (suite: "AvoBatcherSuiteKey", key: "AvoBatcherCacheKey") | Storage keys must not change for upgrade compatibility |
| `NSUserDefaults.standard` for anonymous ID | `AvoInspector.m` (AvoStorageImpl) | Storage key "AvoInspectorAnonymousId" must be preserved |
| `__weak`/`__strong` capture in async blocks | `AvoInspector.m`, `AvoBatcher.m`, `AvoNetworkCallsHandler.m` | Use `[weak self]` in Swift closures |
| `@try/@catch` exception safety | Throughout all `.m` files | Use Swift `do/catch` where appropriate; for ObjC interop runtime exceptions, some try/catch translates to explicit nil-checking |
| Completion handler networking (no async/await) | `AvoNetworkCallsHandler.m`, `AvoEventSpecFetcher.m` | Must stay completion-handler based (iOS 13+ doesn't support async/await) |

## Implementation Details

### Part 1: Package & Infrastructure Changes

**File:** `/Users/alexverein/code/ios/AvoInspectorSPM/Package.swift`

Changes required:
```swift
// swift-tools-version:5.9
let package = Package(
    name: "AvoInspector",
    platforms: [
        .iOS(.v13)  // Changed from .v12 for CryptoKit
    ],
    products: [
        .library(
            name: "AvoInspector",
            targets: ["AvoInspector"]),
    ],
    targets: [
        .target(
            name: "AvoInspector",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "AvoInspectorTests",
            dependencies: ["AvoInspector"]
        )
    ]
)
```

Key changes:
- Platform minimum: `.iOS(.v13)` (required for CryptoKit)
- Add `testTarget` for Swift XCTest tests
- The target remains `AvoInspector` — SPM will detect Swift source files automatically
- `PrivacyInfo.xcprivacy` resource stays unchanged

**Directory structure after migration:**
```
Sources/AvoInspector/
  AvoInspector.swift
  AvoEncryption.swift
  AvoSchemaExtractor.swift
  AvoBatcher.swift
  AvoNetworkCallsHandler.swift
  AvoDeduplicator.swift
  AvoEventValidator.swift
  AvoEventSpecFetcher.swift
  AvoEventSpecCache.swift
  AvoEventSpecFetchTypes.swift
  AvoGuid.swift
  AvoAnonymousId.swift
  AvoStorage.swift
  AvoUtils.swift
  AvoEventSchemaType.swift
  AvoInt.swift
  AvoFloat.swift
  AvoBoolean.swift
  AvoString.swift
  AvoNull.swift
  AvoList.swift
  AvoObject.swift
  AvoUnknownType.swift
  PrivacyInfo.xcprivacy
Tests/AvoInspectorTests/
  (Swift XCTest files)
```

All `.h` and `.m` files are deleted. The `include/` and `types/` subdirectories are removed entirely — all Swift files go in the flat `Sources/AvoInspector/` directory. After migration, the target is pure Swift. No `publicHeadersPath`, module map, or umbrella header is needed; SPM generates a Swift module map automatically.

**Implementation order:** Parts 1-5 should be implemented and validated in sequence. Run `swift build` after completing each Part to catch errors incrementally rather than facing hundreds of compiler errors at the end.

**Test directory migration:** All 14 existing `.m` test files in `Tests/` (including the commented-out `VisualDebuggerTests.m`) are deleted. The entire `Tests/` directory is replaced by `Tests/AvoInspectorTests/` containing only new Swift XCTest files. The commented-out `VisualDebuggerTests.m` adds no value and is deleted — it contains no executable test code.

### Part 2: Type System Migration

The type hierarchy is a base class `AvoEventSchemaType` with leaf subclasses. Each overrides `name` and inherits `isEqual:`, `hash`, `description` from the base.

#### AvoEventSchemaType.swift

```swift
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
```

**Important:** The ObjC `isEqual:` checks `[other isKindOfClass:[self class]]`, which means `AvoInt` != `AvoFloat` even though both are `AvoEventSchemaType`. In Swift, use `type(of: self) == type(of: other)` to match this behavior.

#### Leaf Types

Each leaf type is a trivial subclass. Pattern (same for all 7):

| ObjC Files | Swift File | Class Name | `name()` return |
|-----------|-----------|-----------|----------------|
| `AvoInt.h/.m` | `AvoInt.swift` | `AvoInt` | `"int"` |
| `AvoFloat.h/.m` | `AvoFloat.swift` | `AvoFloat` | `"float"` |
| `AvoBoolean.h/.m` | `AvoBoolean.swift` | `AvoBoolean` | `"boolean"` |
| `AvoString.h/.m` | `AvoString.swift` | `AvoString` | `"string"` |
| `AvoNull.h/.m` | `AvoNull.swift` | `AvoNull` | `"null"` |
| `AvoUnknownType.h/.m` | `AvoUnknownType.swift` | `AvoUnknownType` | `"unknown"` |

Example (all follow this pattern):
```swift
@objc public class AvoInt: AvoEventSchemaType {
    @objc public override func name() -> String { return "int" }
}
```

#### AvoList.swift

```swift
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
```

**Note:** `subtypes` is `NSMutableSet` (not `Set<AvoEventSchemaType>`) to preserve ObjC API compatibility.

#### AvoObject.swift

```swift
@objc public class AvoObject: AvoEventSchemaType {
    @objc public var fields: NSMutableDictionary = NSMutableDictionary()
    // fields is NSMutableDictionary<NSString, AvoEventSchemaType> in practice

    @objc public override func name() -> String {
        var objectSchema = "{"
        let allKeys = fields.allKeys as? [String] ?? []
        for fieldKey in allKeys {
            // NOTE: Using guard/as? instead of force-unwraps to match ObjC's error-tolerant
            // behavior. In ObjC, callers wrap schema operations in @try/@catch, so bad data
            // is recoverable. Swift force-unwraps would crash (fatalError) instead -- not
            // catchable. Safe casts preserve the graceful-degradation behavior.
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
            objectSchema = String(objectSchema.dropLast()) // strip trailing comma
        }
        objectSchema += "}"
        return objectSchema
    }
}
```

**Behavioral note:** The ObjC `AvoObject.name` appends a comma after every entry, then strips the trailing comma with `substringToIndex:length-1` when `fields.count > 0`. The Swift version above faithfully replicates this append-then-strip pattern. Do NOT use index-based conditional comma logic — if any entry were skipped by a type guard, the index counter would advance and produce trailing or missing commas. The ObjC code calls `[value name]` on every entry without a type guard, and the Swift version must do the same. The JSON-like output string is parsed by `AvoNetworkCallsHandler.bodyForTrackSchemaCall` via `NSJSONSerialization`, so any formatting divergence breaks the network payload.

### Part 3: Core Modules Migration

#### AvoStorage.swift

**ObjC:** `AvoStorage.h` — protocol only, no `.m` file.

```swift
import Foundation

@objc public protocol AvoStorage: NSObjectProtocol {
    func isInitialized() -> Bool
    func getItem(_ key: String) -> String?
    @objc(setItem::) func setItem(_ key: String, _ value: String)
}
```

**Note:** The ObjC protocol method `- (void)setItem:(NSString *)key :(NSString *)value;` has an unnamed second parameter (selector `setItem::`). In Swift, `func setItem(_ key: String, _ value: String)` would auto-bridge to `setItemWith::` or `setItem:value:`, NOT the original `setItem::`. The explicit `@objc(setItem::)` annotation is required to preserve the exact ObjC selector.

#### AvoGuid.swift

```swift
import Foundation

@objc public class AvoGuid: NSObject {
    @objc public class func newGuid() -> String {
        return UUID().uuidString
    }
}
```

#### AvoUtils.swift

```swift
import Foundation

@objc public class AvoUtils: NSObject {
    @objc public class func currentTimeAsISO8601UTCString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
```

#### AvoAnonymousId.swift

**Thread safety:** The ObjC uses `@synchronized(self)` on the class object. In Swift, use a private serial `DispatchQueue` or `NSLock`.

**Storage key:** `"AvoInspectorAnonymousId"` — must remain unchanged for upgrade compatibility.

```swift
import Foundation

@objc public class AvoAnonymousId: NSObject {
    private static let lock = NSLock()
    private static var _anonymousId: String?
    private static let storageKey = "AvoInspectorAnonymousId"

    @objc public class func anonymousId() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = _anonymousId, !cached.isEmpty {
            return cached
        }
        guard AvoInspector.avoStorage().isInitialized() else {
            return "unknown"
        }
        let stored = AvoInspector.avoStorage().getItem(storageKey)
        if let stored = stored, !stored.isEmpty {
            _anonymousId = stored
        } else {
            _anonymousId = AvoGuid.newGuid()
            AvoInspector.avoStorage().setItem(storageKey, _anonymousId!)
        }
        return _anonymousId!
    }

    @objc public class func setAnonymousId(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        _anonymousId = id
        AvoInspector.avoStorage().setItem(storageKey, id)
    }

    @objc public class func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        _anonymousId = nil
    }
}
```

**Behavioral preservation:** Error logging in the ObjC version uses `@try/@catch` around storage operations. In Swift, since `AvoStorage` is a protocol that ObjC objects implement, calls may throw ObjC exceptions. Wrap storage calls in `ObjC.try {}` if needed, or simply let them propagate since the protocol methods don't throw.

#### AvoDeduplicator.swift

**Thread safety:** The ObjC version uses `@synchronized(self)` extensively. Use a private serial `DispatchQueue` for synchronized access.

**Singleton:** `dispatch_once` + `sharedDeduplicator` becomes `static let`.

```swift
@objc public class AvoDeduplicator: NSObject {
    @objc public static let sharedDeduplicator = AvoDeduplicator()

    private let queue = DispatchQueue(label: "com.avo.deduplicator")
    private var avoFunctionsEvents = [NSNumber: String]()
    private var manualEvents = [NSNumber: String]()
    private var avoFunctionsEventsParams = [String: [String: Any]]()
    private var manualEventsParams = [String: [String: Any]]()
    private var avoSchemaExtractor = AvoSchemaExtractor()

    // ... methods with queue.sync { } for synchronized access
}
```

Key methods to preserve:
- `shouldRegisterEvent(_:eventParams:fromAvoFunction:) -> Bool`
- `hasSeenEventParams(_:checkInAvoFunctions:) -> Bool`
- `shouldRegisterSchemaFromManually(_:schema:) -> Bool`
- `clearOldEvents()` — 0.3 second threshold for "old" events

**Critical behavioral detail:** The `clearOldEvents` method considers events older than 0.3 seconds as stale. This exact threshold must be preserved.

#### AvoSchemaExtractor.swift

The schema extractor maps ObjC runtime class names to schema types. In Swift, the type detection logic changes significantly because Swift bridges types differently.

```swift
@objc public class AvoSchemaExtractor: NSObject {
    @objc public func extractSchema(_ eventParams: [String: Any]) -> [String: AvoEventSchemaType] {
        // ... iterate keys, call objectToAvoSchemaType for each value
    }

    private func objectToAvoSchemaType(_ obj: Any) -> AvoEventSchemaType {
        // ... type detection
    }
}
```

**Type detection strategy in Swift:**

The ObjC version checks class names as strings (`__NSCFNumber`, `__NSCFBoolean`, `NSConstantIntegerNumber`, `NSConstantDoubleNumber`, `NSConstantFloatNumber`, `__NSSingleObjectSetI`, `__NSSingleObjectArrayI`, `__NSSingleEntryDictionaryI`, etc.). In Swift, we use idiomatic `is`-based type checks which cover all private subclasses:

- `obj is NSNull` -> `AvoNull`
- `obj is Bool` / check `CFBooleanGetTypeID` -> `AvoBoolean` (must check BEFORE `NSNumber` since `Bool` bridges to `NSNumber`)
- `obj is NSNumber` -> examine `objCType` property:
  - `"i"`, `"s"`, `"q"` -> `AvoInt`
  - `"c"` -> `AvoString` (matches ObjC behavior for `char`)
  - `"d"`, `"f"` and other -> `AvoFloat`
- `obj is String` -> `AvoString`
- `obj is [Any]` or `obj is NSArray` or `obj is NSSet` -> `AvoList` (recurse into items)
- `obj is [String: Any]` or `obj is NSDictionary` -> `AvoObject` (recurse into fields)
- Default -> `AvoUnknownType`

**Note on `"l"` (long) objCType:** The ObjC code only checks `"i"`, `"s"`, `"q"` for integer detection -- it does NOT check `"l"`. The Swift port must match this exactly. Do NOT add `"l"` to the AvoInt mapping. This is a migration, not a behavior change.

**Behavioral parity with ObjC class-name matching:** The ObjC code uses private class names (`__NSCFNumber`, `NSConstantIntegerNumber`, `NSConstantDoubleNumber`, `NSConstantFloatNumber`, `__NSCFBoolean`, `__NSSingleObjectSetI`, `__NSSingleObjectArrayI`, `__NSSingleEntryDictionaryI`) for type detection. The Swift `is`-based approach is semantically equivalent but uses a different mechanism. The following behavioral parity must be verified by tests:

1. **`NSConstantIntegerNumber`** (produced by `NSNumber(value: 42)` on some OS versions): The ObjC code returns `AvoInt` for this class. In Swift, `obj is NSNumber` will match, and `objCType` should be `"q"` or `"i"`, producing `AvoInt`. Test required.
2. **`NSConstantDoubleNumber`** (produced by `NSNumber(value: 3.14)` on some OS versions): The ObjC code returns `AvoFloat`. In Swift, `obj is NSNumber` will match, and `objCType` should be `"d"`, producing `AvoFloat`. Test required.
3. **`NSConstantFloatNumber`** (produced by `NSNumber(value: Float(1.5))` on some OS versions): The ObjC code returns `AvoFloat`. Same Swift path as above. Test required.
4. **`__NSSingleObjectArrayI`** (single-element array): The ObjC code checks this by class name. In Swift, `obj is NSArray` / `obj is [Any]` covers this. Test required.
5. **`__NSSingleObjectSetI`** (single-element set): The ObjC code checks this by class name. In Swift, `obj is NSSet` covers this. Test required.
6. **`__NSSingleEntryDictionaryI`** (single-entry dictionary): The ObjC code checks this by class name. In Swift, `obj is NSDictionary` covers this. Test required.

Add these as explicit test cases in `SimpleTypeSchemaExtractionTests.swift` (for items 1-3) and `ListSchemaExtractionTests.swift` / `DictionarySchemaExtractionTests.swift` (for items 4-6).

**Critical:** Boolean detection is the trickiest part. In ObjC, `@YES` is `__NSCFBoolean` which is distinct from `__NSCFNumber`. In Swift, `NSNumber(value: true)` and `NSNumber(value: 1)` are the same at runtime. Use `CFGetTypeID(obj as CFTypeRef) == CFBooleanGetTypeID()` to reliably detect booleans, matching how the ObjC code distinguishes them by class name.

**Non-string dictionary keys:** The ObjC code has a special path for non-string dictionary keys — it calls `[paramName description]` and splits by `.` to create a shortened key. This must be preserved.

#### AvoBatcher.swift

```swift
@objc public class AvoBatcher: NSObject {
    @objc public let networkCallsHandler: AvoNetworkCallsHandler
    private var events = [Any]()
    private var batchFlushAttemptTime: TimeInterval = Date().timeIntervalSince1970
    private let lock = NSLock()

    static let suiteKey = "AvoBatcherSuiteKey"
    static let cacheKey = "AvoBatcherCacheKey"

    @objc public init(networkCallsHandler: AvoNetworkCallsHandler) { ... }
    @objc public func handleTrackSchema(_ eventName: String, schema: [String: AvoEventSchemaType],
                                         eventId: String?, eventHash: String?) { ... }
    @objc public func handleTrackSchema(_ eventName: String, schema: [String: AvoEventSchemaType],
                                         eventId: String?, eventHash: String?,
                                         eventProperties: [String: Any]?) { ... }
    @objc public func enterBackground() { ... }
    @objc public func enterForeground() { ... }
}
```

**Storage keys must match exactly:**
- Suite: `"AvoBatcherSuiteKey"`
- Key: `"AvoBatcherCacheKey"`

**Thread safety:** Uses `@synchronized(self)` in ObjC. Use `NSLock` or a serial dispatch queue.

**Event cap:** 1000 events maximum (preserved from ObjC `removeExtraElements`).

**Event filtering:** `filterEvents` uses `NSPredicate` to remove non-dictionary items and items without a `"type"` key. In Swift, use standard array filtering.

#### AvoNetworkCallsHandler.swift

```swift
@objc public class AvoNetworkCallsHandler: NSObject {
    @objc public let apiKey: String
    @objc public let appName: String
    @objc public let appVersion: String
    @objc public let libVersion: String

    private var env: Int
    private var endpoint: String
    private var publicEncryptionKey: String?
    private var samplingRate: Double = 1.0
    private var urlSession: URLSession

    @objc public init(apiKey: String, appName: String, appVersion: String,
                      libVersion: String, env: Int, endpoint: String) { ... }

    @objc public init(apiKey: String, appName: String, appVersion: String,
                      libVersion: String, env: Int, endpoint: String,
                      publicEncryptionKey: String?) { ... }

    @objc public func callInspectorWithBatchBody(_ batchBody: [Any],
        completionHandler: @escaping (Error?) -> Void) { ... }

    @objc public func bodyForTrackSchemaCall(_ eventName: String,
        schema: [String: AvoEventSchemaType], eventId: String?,
        eventHash: String?) -> NSMutableDictionary { ... }

    @objc public func bodyForTrackSchemaCall(_ eventName: String,
        schema: [String: AvoEventSchemaType], eventId: String?,
        eventHash: String?, eventProperties: [String: Any]?) -> NSMutableDictionary { ... }

    @objc public func bodyForValidatedEventSchemaCall(_ eventName: String,
        schema: [String: AvoEventSchemaType], eventId: String?,
        eventHash: String?, validationResult: AvoValidationResult,
        streamId: String) -> NSMutableDictionary { ... }

    @objc public func bodyForValidatedEventSchemaCall(_ eventName: String,
        schema: [String: AvoEventSchemaType], eventId: String?,
        eventHash: String?, validationResult: AvoValidationResult,
        streamId: String, eventProperties: [String: Any]?) -> NSMutableDictionary { ... }

    @objc public func shouldEncrypt() -> Bool { ... }
    @objc public class func jsonStringifyValue(_ value: Any) -> String? { ... }
    @objc public func reportValidatedEvent(_ body: [String: Any]) { ... }
    @objc public class func formatTypeToString(_ formatType: Int) -> String { ... }
}
```

**`@objc` selector auto-bridging note:** When a Swift method name does not naturally produce the expected ObjC selector, either (a) rename the Swift method so it auto-bridges correctly, or (b) add an explicit `@objc(selectorName:)` attribute. The `formatTypeToString` method above uses approach (a): the Swift signature `formatTypeToString(_ formatType:)` auto-bridges to ObjC selector `formatTypeToString:`, matching the original ObjC `+ (NSString *)formatTypeToString:(int)formatType;`. Review all migrated method signatures to ensure the auto-bridged ObjC selector matches the original. Any method where the Swift name would produce a different ObjC selector (e.g., `formatType(toString:)` would become `formatTypeWithToString:`) must be fixed using one of these two approaches.

```text
(This note applies spec-wide, not just to this method.)
```

**Encryption integration:** `addEncryptedValues` is a class method that iterates properties, calls `AvoEncryption.encrypt(_:recipientPublicKeyHex:)`, and sets `"encryptedPropertyValue"` on each property dictionary. In Swift, use `NSMutableDictionary` for the property dicts to maintain mutability through the recursion.

**Sampling:** `drand48()` is used for sampling rate. In Swift, use `Double.random(in: 0..<1)` or `drand48()` (available in Swift).

#### AvoEventSpecFetchTypes.swift

All the wire/internal types from `AvoEventSpecFetchTypes.h/.m` go into one file. These are:
- `AvoPropertyConstraintsWire` — wire format with short field names
- `AvoEventSpecEntryWire` — wire format event entry
- `AvoEventSpecMetadata` — metadata (shared between wire and internal)
- `AvoEventSpecResponseWire` — wire format response
- `AvoPropertyConstraints` — internal with meaningful names
- `AvoEventSpecEntry` — internal event entry
- `AvoEventSpecResponse` — internal response
- `AvoEventSpecCacheEntry` — cache entry with TTL/LRU data
- `AvoFetchEventSpecParams` — fetch parameters
- `AvoPropertyValidationResult` — per-property validation result
- `AvoValidationResult` — overall validation result

All classes need `@objc` and `NSObject` inheritance. Properties should use `@objc` annotations.

**Key pattern:** Each wire type has `init(dictionary:)` that parses from JSON dictionary. Each internal type has `init(fromWire:)` that maps short names to meaningful names.

**Implementer note:** Port all properties and field mappings directly from `Sources/AvoInspector/AvoEventSpecFetchTypes.h` and `Sources/AvoInspector/AvoEventSpecFetchTypes.m`. The wire types use short single-letter field names (e.g., `"t"` -> type, `"r"` -> required, `"l"` -> list, `"p"` -> path, `"v"` -> allowed values, `"rx"` -> regex pattern, `"n"` -> name, `"s"` -> streamId). All field mappings must be preserved exactly. The `children` property on `AvoPropertyConstraintsWire` is recursive (each child is also an `AvoPropertyConstraintsWire`).

#### AvoEventSpecFetcher.swift

```swift
@objc public class AvoEventSpecFetcher: NSObject {
    private let baseUrl: String
    private let timeout: TimeInterval
    private let env: String
    private var inFlightCallbacks = [String: [(AvoEventSpecResponse?) -> Void]]()

    @objc public init(timeout: TimeInterval, env: String) { ... }
    @objc public init(timeout: TimeInterval, env: String, baseUrl: String) { ... }
    @objc public func fetchEventSpec(_ params: AvoFetchEventSpecParams,
                                      completion: @escaping (AvoEventSpecResponse?) -> Void) { ... }
}
```

**In-flight deduplication:** Uses `@synchronized(self.inFlightCallbacks)` in ObjC. Use `NSLock` in Swift.

**Synchronous request with semaphore:** `makeRequest` uses `dispatch_semaphore` to block until the URLSession callback fires. Preserve this pattern exactly.

**Queue constraints (deadlock prevention):** `makeRequest` blocks the calling thread with `semaphore.wait()` until the URLSession completion handler signals. To avoid deadlocks:
1. `makeRequest` must NOT be called from the main queue.
2. The `URLSession` must be configured with a `nil` delegate queue (the default), so the completion handler fires on a system-managed background queue that is never the same queue blocked by the semaphore.
3. The ObjC code works because `fetchEventSpec` is always called from a background context. The Swift port must preserve this invariant. Add a debug assertion: `dispatchPrecondition(condition: .notOnQueue(.main))` at the top of `makeRequest` to catch main-queue calls during development.

#### AvoEventSpecCache.swift

```swift
@objc public class AvoEventSpecCache: NSObject {
    private static let ttlMs: Int64 = 60_000
    private static let maxEventCount = 50
    private var cache = [String: AvoEventSpecCacheEntry]()
    private var globalEventCount = 0
    private let lock = NSLock()

    @objc public func get(_ key: String) -> AvoEventSpecResponse? { ... }
    @objc public func set(_ key: String, spec: AvoEventSpecResponse?) { ... }
    @objc public func contains(_ key: String) -> Bool { ... }
    @objc public func clear() { ... }
    @objc public func size() -> Int { ... }
    @objc public class func generateKey(_ apiKey: String, streamId: String,
                                         eventName: String) -> String { ... }
}
```

**Thread safety:** Uses `@synchronized(self.cache)` in ObjC. Use `NSLock` in Swift.

#### AvoEventValidator.swift

```swift
@objc public class AvoEventValidator: NSObject {
    private static let maxChildDepth = 2
    private static let regexCache = NSCache<NSString, NSRegularExpression>()
    private static let allowedValuesCache = NSCache<NSString, NSArray>()

    @objc public class func validateEvent(_ properties: [String: Any],
        specResponse: AvoEventSpecResponse) -> AvoValidationResult? { ... }

    @objc public class func isPatternPotentiallyDangerous(_ pattern: String) -> Bool { ... }

    @objc public class func safeNumberOfMatches(with regex: NSRegularExpression,
        in string: String, timeout: TimeInterval) -> UInt { ... }
}
```

**ReDoS protection pattern (CRITICAL):** This must be preserved exactly from the `fix/redos-vulnerability` branch:

1. **Pattern validation:** `isPatternPotentiallyDangerous` checks for nested quantifiers using regex `\([^)]*[+*][^)]*\)[+*]`. Reject patterns that match.

2. **Timeout execution:** `safeNumberOfMatches` dispatches regex matching onto a shared static serial queue (`"com.avo.inspector.regex"`) and waits with a semaphore. If the semaphore times out (2 seconds), return `NSNotFound` and log a warning. The caller treats `NSNotFound` as "skip this constraint" (fail-open).

```swift
private static let regexQueue = DispatchQueue(label: "com.avo.inspector.regex")

@objc public class func safeNumberOfMatches(with regex: NSRegularExpression,
    in string: String, timeout: TimeInterval) -> UInt {
    var result: UInt = UInt(NSNotFound)
    let semaphore = DispatchSemaphore(value: 0)

    regexQueue.async {
        result = UInt(regex.numberOfMatches(in: string, range: NSRange(location: 0, length: string.utf16.count)))
        semaphore.signal()
    }

    let timedOut = semaphore.wait(timeout: .now() + timeout)
    if timedOut == .timedOut {
        if AvoInspector.isLogging() {
            NSLog("[avo] Avo Inspector: Regex execution timed out after %.0fs for pattern '%@'",
                  timeout, regex.pattern)
        }
        return UInt(NSNotFound)
    }
    return result
}
```

**Important:** The ObjC return type is `NSUInteger`. In Swift, use `UInt` for the return type to match. `NSNotFound` is `Int.max` in Swift; use `UInt(NSNotFound)` as the timeout sentinel.

#### AvoInspector.swift

This is the main class. Key aspects:

```swift
@objc public enum AvoInspectorEnv: UInt {
    case prod = 0
    case dev = 1
    case staging = 2
}

@objc public enum AvoVisualInspectorType: UInt {
    @objc(Bar) case bar = 0
    @objc(Bubble) case bubble = 1
}

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

@objc public class AvoInspector: NSObject, Inspector {
    @objc public private(set) var appVersion: String
    @objc public private(set) var libVersion: String
    @objc public private(set) var apiKey: String
    private var appName: String  // Set from Bundle.main.infoDictionary[kCFBundleIdentifierKey], passed to AvoNetworkCallsHandler init

    // NOTE: These static vars are intentionally unsynchronized, matching ObjC behavior.
    // The ObjC code uses plain C statics with no synchronization for these values.
    private static var logging = false
    private static var maxBatchSize: Int32 = 30
    private static var batchFlushTime: Int32 = 30

    // From ObjC: `static const NSTimeInterval EVENT_SPEC_FETCH_TIMEOUT = 5.0;`
    // Used when constructing AvoEventSpecFetcher.
    private static let eventSpecFetchTimeout: TimeInterval = 5.0

    @objc public class func avoStorage() -> AvoStorage { ... }

    @objc public init(apiKey: String, env: AvoInspectorEnv) { ... }
    @objc public init(apiKey: String, envInt: NSNumber) {
        // Convenience initializer that delegates to init(apiKey:env:)
        // ObjC signature: initWithApiKey:envInt:
        // NOTE: Intentional divergence from ObjC which uses `[envInt intValue]`.
        // Using `uintValue` with `?? .dev` fallback is an improvement: negative values
        // fall through to .dev instead of undefined enum behavior. For valid values
        // (0, 1, 2) behavior is identical.
        self.init(apiKey: apiKey, env: AvoInspectorEnv(rawValue: envInt.uintValue) ?? .dev)
    }
    @objc public init(apiKey: String, env: AvoInspectorEnv, proxyEndpoint: String) { ... }
    @objc public init(apiKey: String, env: AvoInspectorEnv,
                      publicEncryptionKey: String?) { ... }
    @objc public init(apiKey: String, env: AvoInspectorEnv,
                      proxyEndpoint: String, publicEncryptionKey: String?) { ... }
}
```

**Additional methods to port from AvoInspector.m:**

The following methods must be ported. They are listed here with behavioral notes for the non-trivial ones. For simpler methods, port directly from the ObjC source.

**Internal API -- `avoFunctionTrackSchemaFromEvent`:**
```swift
@objc public func avoFunctionTrackSchemaFromEvent(_ eventName: String,
    eventParams params: NSMutableDictionary) -> [String: AvoEventSchemaType]
```
This is called by Avo-generated code. It:
1. Checks deduplication via `avoDeduplicator.shouldRegisterEvent(_:eventParams:fromAvoFunction: true)`
2. Copies params to a new dictionary
3. Extracts and removes `"avoFunctionEventId"` and `"avoFunctionEventHash"` from the copied params
4. Delegates to `internalTrackSchemaFromEvent`

**Internal tracking -- `internalTrackSchemaFromEvent`:**
```swift
private func internalTrackSchemaFromEvent(_ eventName: String,
    eventParams params: [String: Any],
    eventId: String?, eventHash: String?) -> [String: AvoEventSchemaType]
```
Extracts schema from params, then calls `fetchAndValidateAsync` with the schema and original params. Returns the extracted schema.

**Fetch-validate-send flow -- `fetchAndValidateAsync` (IMPORTANT -- thread safety):**
```swift
private func fetchAndValidateAsync(_ eventName: String,
    eventParams params: [String: Any],
    eventSchema schema: [String: AvoEventSchemaType],
    eventId: String?, eventHash: String?,
    eventProperties: [String: Any]?)
```
This is the core event-spec validation flow (from the recently merged event-spec-validation feature). The flow is:

1. **Guard conditions:** If `eventSpecFetcher` is nil, `eventSpecCache` is nil, `streamId` is nil/`"unknown"`, or params is nil/empty, fall through to `internalTrackSchema` (the non-validated batched path).
2. **Generate cache key:** `AvoEventSpecCache.generateKey(apiKey, streamId: streamId, eventName: eventName)`
3. **Cache hit path:** If `eventSpecCache.contains(cacheKey)`:
   - Get cached spec. If non-nil, validate via `AvoEventValidator.validateEvent(params, specResponse: cachedSpec)`.
   - If validation result is non-nil, send via `sendEventWithValidation`.
   - If cached spec is nil or validation returns nil, fall through to `internalTrackSchema`.
4. **Cache miss path:** Fetch spec asynchronously:
   - Create defensive copies of `params` and `eventProperties` (to prevent caller mutations during async execution).
   - Use `[weak self]` capture in the fetch completion block.
   - On fetch success: call `handleBranchChangeAndCache`, then validate and send.
   - On fetch failure (nil response): cache nil to avoid re-fetching within TTL, then fall through to `internalTrackSchema`.

**Branch change detection -- `handleBranchChangeAndCache` (SYNCHRONIZED):**
```swift
private func handleBranchChangeAndCache(_ cacheKey: String,
    specResponse: AvoEventSpecResponse)
```
**Thread safety:** This method uses `@synchronized(self)` in ObjC. In Swift, use `NSLock` or `objc_sync_enter/objc_sync_exit` to protect the critical section. The method:
1. Checks if `specResponse.metadata.branchId` differs from `self.currentBranchId`
2. If branch changed: logs a message and clears the entire cache
3. Updates `self.currentBranchId`
4. Caches the spec response

**Validated event sending -- `sendEventWithValidation`:**
```swift
private func sendEventWithValidation(_ eventName: String,
    schema: [String: AvoEventSchemaType],
    eventId: String?, eventHash: String?,
    validationResult: AvoValidationResult,
    eventProperties: [String: Any]?)
```
Builds a validated event body via `networkCallsHandler.bodyForValidatedEventSchemaCall` and sends it via `networkCallsHandler.reportValidatedEvent`. Wrapped in `@try/@catch` in ObjC; in Swift, use do/catch or guard-let as appropriate since the methods involved don't throw Swift errors.

**Lifecycle methods:**
```swift
@objc public func enterBackground() { ... }  // Delegates to avoBatcher.enterBackground()
@objc public func enterForeground() { ... }  // Delegates to avoBatcher.enterForeground()
```

**Notification observers -- `addObservers` (COMMENTED OUT):**
The `addObservers` method in the ObjC source has the `UIApplicationDidEnterBackgroundNotification` and `UIApplicationWillEnterForegroundNotification` observer registrations entirely commented out. The Swift port must preserve this commented-out state. Include the method with the registrations commented out and a code comment explaining they are intentionally disabled, matching the ObjC source. Do NOT re-enable them and do NOT delete them -- keep them as commented-out code so a future developer can see the intended pattern.

**Deallocation:**
```swift
deinit {
    notificationCenter.removeObserver(self)
}
```

**Other methods to port directly from AvoInspector.m (no special behavioral notes needed):**
- `trackSchemaFromEvent(_:eventParams:) -> [String: AvoEventSchemaType]` (public, checks deduplication)
- `trackSchema(_:eventSchema:)` (public, checks deduplication for manual schema tracking)
- `internalTrackSchema(_:eventSchema:eventId:eventHash:eventProperties:)` (validates schema types, delegates to batcher)
- `extractSchema(_:) -> [String: AvoEventSchemaType]` (public, checks deduplication warning, delegates to schemaExtractor)
- `printAvoGenericError(_:)` (private error logging)

**Storage implementation:** `AvoStorageImpl` is a private inner class using `UserDefaults.standard`:
```swift
private class AvoStorageImpl: NSObject, AvoStorage {
    func isInitialized() -> Bool { return true }
    func getItem(_ key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }
    func setItem(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
```

**Singleton storage:** Use `static let` for thread-safe lazy initialization:
```swift
private static let sharedStorage = AvoStorageImpl()
@objc public class func avoStorage() -> AvoStorage { return sharedStorage }
```

**Library version:** Update from `"1.5.1"` to `"4.0.0"`.

**Default endpoint:** `"https://api.avo.app/inspector/v1/track"`.

### Part 4: Encryption — CryptoKit + v0x01 Wire Format

**File:** `AvoEncryption.swift`

This is the most complex module and requires a complete rewrite using CryptoKit.

#### v0x01 Wire Format

Reference: `/Users/alexverein/code/avo/ios-avo-inspector/planning/ecies-v1-wire-format/spec.md`

```
Offset  Length  Field
0       1       Version byte (0x01)
1       65      Ephemeral EC public key (uncompressed: 0x04 + X(32) + Y(32))
66      12      Nonce (random, for AES-GCM)
78      16      Auth tag (AES-GCM authentication tag)
94      N       Ciphertext
```

Total: 94 + N bytes (vs. 98 + N for v0x00).

Key differences from v0x00:
- Version byte: `0x01` instead of `0x00`
- Nonce: 12 bytes instead of 16-byte IV
- CryptoKit `AES.GCM.Nonce(data:)` requires exactly 12 bytes

#### CryptoKit Implementation

```swift
import Foundation
import CryptoKit
import Security

@objc public class AvoEncryption: NSObject {
    private static let kNonceLength = 12
    private static let kAuthTagLength = 16
    private static let kUncompressedKeyLength = 65
    private static let kVersionByte: UInt8 = 0x01

    @objc public class func encrypt(_ plaintext: String?,
                                     recipientPublicKeyHex: String?) -> String? {
        guard let plaintext = plaintext,
              let recipientPublicKeyHex = recipientPublicKeyHex,
              !recipientPublicKeyHex.isEmpty else {
            return nil
        }

        do {
            // 1. Parse recipient public key from hex
            guard let pubKeyBytes = hexToBytes(recipientPublicKeyHex),
                  let uncompressedPubKeyData = parseAndUncompressPublicKey(pubKeyBytes) else {
                return nil
            }

            guard let recipientKey = createECPublicKey(from: uncompressedPubKeyData) else {
                return nil
            }

            // 2. Generate ephemeral P-256 keypair
            guard let (ephemeralPrivate, ephemeralPublic) = generateEphemeralKeyPair() else {
                return nil
            }

            // 3. ECDH shared secret
            guard let sharedSecret = computeECDHSharedSecret(
                privateKey: ephemeralPrivate, publicKey: recipientKey) else {
                return nil
            }

            // 4. KDF: SHA-256(sharedSecret) -> 32-byte AES key
            let aesKeyData = SHA256.hash(data: sharedSecret)
            let aesKey = SymmetricKey(data: aesKeyData)

            // 5. Generate random 12-byte nonce
            // We generate a random nonce but pass it explicitly to `seal()` so we can
            // include the nonce bytes at a known offset in the wire format. The two-argument
            // seal() overload auto-generates a nonce but may not expose it for wire assembly.
            let nonce = AES.GCM.Nonce()

            // 6. AES-256-GCM encrypt (no AAD)
            guard let plaintextData = plaintext.data(using: .utf8) else {
                return nil
            }
            let sealedBox = try AES.GCM.seal(plaintextData, using: aesKey, nonce: nonce)

            // 7. Export ephemeral public key as uncompressed point
            guard let ephemeralPubData = exportUncompressedPublicKey(ephemeralPublic),
                  ephemeralPubData.count == kUncompressedKeyLength else {
                return nil
            }

            // 8. Assemble v0x01 wire format
            var output = Data(capacity: 1 + kUncompressedKeyLength + kNonceLength + kAuthTagLength + sealedBox.ciphertext.count)
            output.append(kVersionByte)
            output.append(ephemeralPubData)
            output.append(contentsOf: nonce)          // 12 bytes
            output.append(sealedBox.tag)               // 16 bytes
            output.append(sealedBox.ciphertext)

            // 9. Base64 encode
            return output.base64EncodedString()
        } catch {
            NSLog("[avo] Avo Inspector: Encryption failed: %@", error.localizedDescription)
            return nil
        }
    }
}
```

#### Key Parsing (Preserved from ObjC)

The hex parsing, compressed key decompression (secp256r1 Y-coordinate recovery), and SecKey operations must be ported:

- `hexToBytes(_:)` — hex string to `Data`, strips `0x` prefix
- `parseAndUncompressPublicKey(_:)` — handles 33-byte compressed, 65-byte uncompressed (0x04 prefix), and 64-byte raw formats
- `decompressPublicKey(_:)` — recovers Y from X using secp256r1 curve math
- `computeYFromX(_:yOdd:)` — big-number arithmetic for modular exponentiation

**The big-number arithmetic can be significantly simplified.** The ObjC implementation uses hand-rolled byte-array big-number operations (modular multiplication, exponentiation, etc.) for Y-coordinate recovery. In Swift with CryptoKit available, consider:

1. **Option A (recommended):** Keep the big-number approach but rewrite in Swift with cleaner code. The functions are mathematically correct and tested.
2. **Option B:** Since iOS Security.framework always produces 65-byte uncompressed keys, and the server should send uncompressed keys too, the compressed key path may never be exercised in production. However, the tests verify it works, so it must be preserved.

The secp256r1 curve constants (`p`, `a`, `b`, `(p+1)/4`) must be preserved exactly.

#### SecKey Operations in Swift

```swift
private class func createECPublicKey(from uncompressedData: Data) -> SecKey? {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(uncompressedData as CFData,
                                          attributes as CFDictionary, &error) else {
        return nil
    }
    return key
}

private class func generateEphemeralKeyPair() -> (SecKey, SecKey)? {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
          let publicKey = SecKeyCopyPublicKey(privateKey) else {
        return nil
    }
    return (privateKey, publicKey)
}

private class func computeECDHSharedSecret(privateKey: SecKey, publicKey: SecKey) -> Data? {
    var error: Unmanaged<CFError>?
    guard let sharedSecretRef = SecKeyCopyKeyExchangeResult(
        privateKey,
        .ecdhKeyExchangeStandard,
        publicKey,
        [:] as CFDictionary,
        &error) else {
        return nil
    }
    return sharedSecretRef as Data
}

private class func exportUncompressedPublicKey(_ publicKey: SecKey) -> Data? {
    var error: Unmanaged<CFError>?
    guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
          keyData.count == 65 else {
        return nil
    }
    return keyData
}
```

**Note:** CryptoKit's `P256.KeyAgreement` could replace `SecKey` operations entirely, but `SecKey` is retained because:
1. The compressed key decompression logic uses `SecKeyCreateWithData` to validate the uncompressed point
2. Consistency with the ObjC approach reduces risk of behavioral changes
3. `SecKeyCopyKeyExchangeResult` with `ecdhKeyExchangeStandard` produces the raw shared secret without any KDF, matching the ObjC behavior

#### SHA-256 KDF

The ObjC version uses `CC_SHA256()`. In Swift with CryptoKit:
```swift
let hash = SHA256.hash(data: sharedSecret)
let aesKey = SymmetricKey(data: hash)
```

This eliminates the CommonCrypto dependency for hashing as well.

### Part 5: Test Migration

The SPM repo contains 14 `.m` test files in `Tests/` (13 active + 1 commented-out `VisualDebuggerTests.m`). The cocoapods repo contains 7 additional test files not present in the SPM repo. All 14 existing files are deleted and replaced by Swift XCTest files in `Tests/AvoInspectorTests/`. The 7 cocoapods-only files are ported from `/Users/alexverein/code/avo/ios-avo-inspector/Example/Tests/`.

**Authoritative test count:** 13 files ported from SPM repo + 7 new files from cocoapods + 3 new thread-safety test files = **23 Swift test files** in `Tests/AvoInspectorTests/`. The commented-out `VisualDebuggerTests.m` is deleted (not ported).

**Test directory:** `Tests/AvoInspectorTests/`

**Framework mapping:**

| Specta/Expecta | XCTest |
|----------------|--------|
| `describe(@"...", ^{ ... })` | `class XYZTests: XCTestCase { ... }` |
| `it(@"...", ^{ ... })` | `func test_description() { ... }` |
| `beforeAll(^{ ... })` | `override class func setUp() { ... }` |
| `beforeEach(^{ ... })` | `override func setUp() { ... }` |
| `expect(x).to.equal(y)` | `XCTAssertEqual(x, y)` |
| `expect(x).toNot.beNil()` | `XCTAssertNotNil(x)` |
| `expect(x).to.beNil()` | `XCTAssertNil(x)` |
| `expect(x).to.beTruthy()` | `XCTAssertTrue(x)` |
| `expect(x).to.beFalsy()` | `XCTAssertFalse(x)` |
| `expect(x).to.beGreaterThan(y)` | `XCTAssertGreaterThan(x, y)` |
| `expect(x).to.beLessThan(y)` | `XCTAssertLessThan(x, y)` |
| `OCMClassMock([Class class])` | Protocol-based mocking or manual test doubles |

**OCMock replacement:** Swift does not have OCMock. Use lightweight manual test doubles (subclasses or protocol conformances). The existing ObjC tests mock the following classes — each needs a corresponding test-double strategy:

| Mocked Class | Used In Tests | Test Double Strategy |
|-------------|---------------|---------------------|
| `AvoNetworkCallsHandler` | BatchingTests, NetworkCallsHandlerTests, SamplingTests | Subclass override: `MockNetworkCallsHandler` overrides `callInspectorWithBatchBody` and `bodyForTrackSchemaCall` |
| `AvoBatcher` | TrackTests, SessionBetweenRestartsTests | Subclass override: `MockBatcher` overrides `handleTrackSchema` |
| `AvoInspector` (class methods: `avoStorage`, `isLogging`) | AvoAnonymousIdTests, LogsTests | Dependency injection seam (see below) |
| `AvoSchemaExtractor` | DeduplicatorTests | Direct instantiation (no mock needed — it's stateless) |
| `AvoDeduplicator` (singleton) | TrackTests | Dependency injection seam (see below) |

**Dependency injection seams for singletons and class methods:**

The `static let` singleton pattern (`AvoDeduplicator.sharedDeduplicator`) and class-level methods (`AvoInspector.avoStorage()`) are test-hostile because they cannot be swapped. Add internal-visibility initializers that accept injected dependencies, while keeping the public convenience initializers unchanged:

```swift
// AvoInspector — add internal init for testing
@objc public class AvoInspector: NSObject, Inspector {
    // ... existing public properties ...

    // Internal init with injectable storage — used by tests only
    internal init(apiKey: String, env: AvoInspectorEnv, storage: AvoStorage) {
        // ... same setup but uses injected storage instead of sharedStorage
    }
}

// AvoAnonymousId — add storage parameter for testing
@objc public class AvoAnonymousId: NSObject {
    // Public API unchanged (uses AvoInspector.avoStorage())
    @objc public class func anonymousId() -> String { ... }

    // Internal test seam
    internal class func anonymousId(storage: AvoStorage) -> String { ... }
}
```

This approach preserves the public API exactly while making internals testable. The `internal` visibility means test targets (in the same module via `@testable import`) can access the seams, but consumers cannot.

**Example test double:**

```swift
class MockNetworkCallsHandler: AvoNetworkCallsHandler {
    var callInspectorCallCount = 0
    var lastBatchBody: [Any]?

    override func callInspectorWithBatchBody(_ batchBody: [Any],
        completionHandler: @escaping (Error?) -> Void) {
        callInspectorCallCount += 1
        lastBatchBody = batchBody
        completionHandler(nil)
    }
}

class MockStorage: NSObject, AvoStorage {
    var store = [String: String]()
    var initialized = true
    func isInitialized() -> Bool { return initialized }
    func getItem(_ key: String) -> String? { return store[key] }
    func setItem(_ key: String, _ value: String) { store[key] = value }
}
```

#### Test Files to Create

| Source | ObjC Test File | Swift Test File | Notes |
|--------|---------------|----------------|-------|
| SPM repo | `SimpleTypeSchemaExtractionTests.m` | `SimpleTypeSchemaExtractionTests.swift` | Tests int/float/bool/null/string extraction |
| SPM repo | `DictionarySchemaExtractionTests.m` | `DictionarySchemaExtractionTests.swift` | Tests nested dict -> AvoObject |
| SPM repo | `ListSchemaExtractionTests.m` | `ListSchemaExtractionTests.swift` | Tests array -> AvoList |
| SPM repo | `DeduplicatorTests.m` | `DeduplicatorTests.swift` | Tests event deduplication |
| SPM repo | `BatchingTests.m` | `BatchingTests.swift` | Tests batch size, flush timing, background/foreground |
| SPM repo | `NetworkCallsHandlerTests.m` | `NetworkCallsHandlerTests.swift` | Tests body construction, sampling |
| SPM repo | `InitializationTests.m` | `InitializationTests.swift` | Tests inspector init with various params. Must include `test_initWithEnvInt_mapsToCorrectEnv`: init with `NSNumber(value: 1)` and assert env is `.dev`; init with `NSNumber(value: 0)` and assert env is `.prod`. |
| SPM repo | `LogsTests.m` | `LogsTests.swift` | Tests logging flag behavior |
| SPM repo | `TrackTests.m` | `TrackTests.swift` | Tests trackSchemaFromEvent / trackSchema |
| SPM repo | `EnvironmentMappingTest.m` | `EnvironmentMappingTests.swift` | Tests env enum -> string mapping |
| SPM repo | `SamplingTests.m` | `SamplingTests.swift` | Tests sampling rate behavior |
| SPM repo | `SessionBetweenRestartsTests.m` | `SessionBetweenRestartsTests.swift` | Tests session persistence |
| SPM repo | `SessionTests.m` | `SessionTests.swift` | Tests session handling |
| SPM repo | `VisualDebuggerTests.m` | **Deleted** | DEVIATION FROM INTERVIEW BRIEF: Intentionally deleting because file contains zero executable test code. Keeping it would require a mixed-language test target for no value. |
| Cocoapods | `AvoEncryptionTests.m` | `AvoEncryptionTests.swift` | Port from cocoapods, update for v0x01 wire format |
| Cocoapods | `AvoEncryptionIntegrationTests.m` | `AvoEncryptionIntegrationTests.swift` | Port from cocoapods |
| Cocoapods | `AvoAnonymousIdTests.m` | `AvoAnonymousIdTests.swift` | Port from cocoapods |
| Cocoapods | `AvoEventSpecCacheTests.m` | `AvoEventSpecCacheTests.swift` | Port from cocoapods |
| Cocoapods | `AvoEventSpecFetcherTests.m` | `AvoEventSpecFetcherTests.swift` | Port from cocoapods. Tests in-flight deduplication, semaphore-based sync requests, timeout handling, and response parsing. Source: `/Users/alexverein/code/avo/ios-avo-inspector/Example/Tests/AvoEventSpecFetcherTests.m` |
| Cocoapods | `AvoEventValidatorTests.m` | `AvoEventValidatorTests.swift` | Port from cocoapods |
| New | -- | `AvoAnonymousIdThreadSafetyTests.swift` | New: concurrent access tests for NSLock-based synchronization |
| New | -- | `AvoDeduplicatorThreadSafetyTests.swift` | New: concurrent access tests for serial-queue synchronization |
| New | -- | `AvoEventSpecCacheThreadSafetyTests.swift` | New: concurrent access tests for NSLock-based synchronization |

**Encryption test changes for v0x01:**

The decryption helper in tests must be updated:
- Check for version byte `0x01`
- Parse 12-byte nonce at offset 66 (not 16-byte IV)
- Parse auth tag at offset 78 (not 82)
- Ciphertext starts at offset 94 (not 98)
- Minimum message size: 95 bytes (94 header + at least 1 byte ciphertext)

The test decryption helper should use CryptoKit for decryption. Port from the ObjC helper at `/Users/alexverein/code/avo/ios-avo-inspector/Example/Tests/AvoEncryptionTests.m` (the `AvoEncryptionTestHelper` class, lines 24-129), replacing `CC_SHA256` with `CryptoKit.SHA256.hash(data:)` and `CCCryptorGCMOneshotDecrypt` with `AES.GCM.open`:

```swift
func decrypt(_ base64: String, privateKey: SecKey) -> String? {
    guard let data = Data(base64Encoded: base64), data.count >= 95 else { return nil }
    guard data[0] == 0x01 else { return nil }

    let ephemeralPubData = data[1..<66]
    let nonceData = data[66..<78]
    let tagData = data[78..<94]
    let ciphertext = data[94...]

    // Reconstruct ephemeral public key
    let keyAttrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    guard let ephemeralPubKey = SecKeyCreateWithData(
        Data(ephemeralPubData) as CFData, keyAttrs as CFDictionary, &error) else {
        return nil
    }

    // ECDH shared secret
    guard let sharedSecretRef = SecKeyCopyKeyExchangeResult(
        privateKey, .ecdhKeyExchangeStandard, ephemeralPubKey,
        [:] as CFDictionary, &error) else {
        return nil
    }
    let sharedSecret = sharedSecretRef as Data

    // KDF: SHA-256
    let hash = SHA256.hash(data: sharedSecret)
    let aesKey = SymmetricKey(data: hash)

    // AES-256-GCM decrypt
    do {
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce, ciphertext: ciphertext, tag: tagData)
        let plainData = try AES.GCM.open(sealedBox, using: aesKey)
        return String(data: plainData, encoding: .utf8)
    } catch {
        return nil
    }
}
```

Also port the `generateTestPrivateKey()` and `publicKeyHexFromPrivateKey(_:)` helpers from the same ObjC file.

#### Thread Safety Tests (REQUIRED)

The migration changes every synchronization primitive in the codebase (`@synchronized` -> `NSLock`/serial queue, `dispatch_once` -> `static let`). Thread-safety tests are required to validate the new primitives under concurrent access. Add the following test cases:

**AvoAnonymousIdThreadSafetyTests.swift:**
- `test_concurrentAnonymousIdAccess_returnsConsistentValue`: Call `AvoAnonymousId.anonymousId()` from 100 concurrent threads using `DispatchQueue.concurrentPerform(iterations: 100)`. Assert all returned values are identical.
- `test_concurrentSetAndGet_doesNotCrash`: Interleave `setAnonymousId` and `anonymousId` calls from 50 concurrent threads. Assert no crash (EXC_BAD_ACCESS) and final value is one of the set values.
- `test_concurrentClearAndGet_doesNotCrash`: Interleave `clearCache` and `anonymousId` calls from 50 concurrent threads. Assert no crash.

**AvoDeduplicatorThreadSafetyTests.swift:**
- `test_concurrentShouldRegisterEvent_doesNotCrash`: Call `shouldRegisterEvent` from 50 concurrent threads with distinct event names. Assert no crash.
- `test_concurrentClearOldEvents_doesNotCrash`: Interleave `clearOldEvents` and `shouldRegisterEvent` from 50 concurrent threads. Assert no crash.

**AvoEventSpecCacheThreadSafetyTests.swift:**
- `test_concurrentGetAndSet_doesNotCrash`: Interleave `get`, `set`, and `contains` calls from 50 concurrent threads. Assert no crash and `get` returns either nil or a valid `AvoEventSpecResponse`.
- `test_concurrentClearAndSet_doesNotCrash`: Interleave `clear` and `set` calls from 50 concurrent threads. Assert no crash.

**Pattern for all thread-safety tests:**
```swift
func test_concurrentAccess_doesNotCrash() {
    let iterations = 100
    DispatchQueue.concurrentPerform(iterations: iterations) { i in
        // Exercise the API under test
    }
    // If we reach here without crashing, the test passes
}
```

These tests validate that the NSLock/serial-queue replacements for `@synchronized` do not introduce data races or deadlocks. A crash (EXC_BAD_ACCESS) or hang (deadlock detected by XCTest timeout) constitutes failure.

#### ReDoS Protection Tests (REQUIRED)

The ReDoS timeout mechanism is labeled CRITICAL in this spec. Add the following explicit test cases to `AvoEventValidatorTests.swift`:

- `test_isPatternPotentiallyDangerous_detectsNestedQuantifiers`: Assert `isPatternPotentiallyDangerous("(a+)+")` returns `true`. Assert `isPatternPotentiallyDangerous("(a+)*")` returns `true`. Assert `isPatternPotentiallyDangerous("([a-z]+)*")` returns `true`.
- `test_isPatternPotentiallyDangerous_allowsSafePatterns`: Assert `isPatternPotentiallyDangerous("[a-z]+")` returns `false`. Assert `isPatternPotentiallyDangerous("\\d{3}-\\d{4}")` returns `false`.
- `test_safeNumberOfMatches_returnsCorrectCount`: Create a simple regex `[0-9]+`, call `safeNumberOfMatches` with `"abc 123 def 456"`, assert result is `2`.
- `test_safeNumberOfMatches_returnsNSNotFoundOnTimeout`: Create a known-slow regex and input that causes backtracking. Call `safeNumberOfMatches` with a very short timeout (e.g., 0.001 seconds). Assert result equals `UInt(NSNotFound)`.
- `test_failOpenBehavior_skipsConstraintOnTimeout`: Verify that when `safeNumberOfMatches` returns `NSNotFound`, the calling validation logic treats the constraint as passed (not failed).
- `test_concurrentSafeNumberOfMatches_doesNotDeadlock`: Call `safeNumberOfMatches` from 50 concurrent threads using `DispatchQueue.concurrentPerform(iterations: 50)` with a simple regex and short input. Assert all calls complete without deadlock (XCTest timeout constitutes failure) and return valid results. This validates that the shared static serial queue with semaphore-based timeouts does not back up under concurrent load.

#### Validation Flow Tests (REQUIRED -- extend TrackTests.swift)

The event-spec fetch-validate-send flow in `AvoInspector` is the most complex orchestration in the codebase. The following test cases must be added to `TrackTests.swift` to cover the validation paths:

**Test doubles needed for validation tests:**
- `MockEventSpecFetcher`: Subclass of `AvoEventSpecFetcher` that returns a pre-configured `AvoEventSpecResponse` (or nil) without making a network call.
- `MockEventSpecCache`: Subclass of `AvoEventSpecCache` that allows pre-populating cache entries and inspecting cache state.
- `MockNetworkCallsHandler` (already defined): Extended to capture `reportValidatedEvent` calls.

**Test cases:**

- `test_fetchAndValidate_cacheHit_validSpec_sendsValidatedEvent`: Pre-populate the cache with a valid spec for the event. Call `trackSchemaFromEvent`. Assert `reportValidatedEvent` was called (not `handleTrackSchema` on the batcher).

- `test_fetchAndValidate_cacheHit_nilSpec_fallsThroughToBatcher`: Pre-populate the cache with a nil spec entry. Call `trackSchemaFromEvent`. Assert `handleTrackSchema` was called on the batcher (the non-validated path).

- `test_fetchAndValidate_cacheMiss_fetchSuccess_sendsValidatedEvent`: Configure mock fetcher to return a valid spec. Ensure cache is empty. Call `trackSchemaFromEvent`. Assert the spec was cached and `reportValidatedEvent` was called.

- `test_fetchAndValidate_cacheMiss_fetchFailure_fallsThroughToBatcher`: Configure mock fetcher to return nil. Call `trackSchemaFromEvent`. Assert nil was cached (to prevent re-fetching within TTL) and `handleTrackSchema` was called on the batcher.

- `test_fetchAndValidate_branchChange_clearsCache`: Pre-populate cache with entries from branch "A". Configure mock fetcher to return a spec with branch "B". Call `trackSchemaFromEvent` for an uncached event. Assert the cache was cleared before the new entry was stored.

- `test_fetchAndValidate_noFetcher_fallsThroughToBatcher`: Initialize AvoInspector with prod env (which does not create a fetcher). Call `trackSchemaFromEvent`. Assert `handleTrackSchema` was called on the batcher directly.

- `test_avoFunctionTrackSchemaFromEvent_extractsEventIdAndHash`: Call `avoFunctionTrackSchemaFromEvent` with params containing `"avoFunctionEventId"` and `"avoFunctionEventHash"`. Assert these keys are removed from the params passed downstream and are forwarded as separate arguments.

#### VisualDebuggerTests.m — Deleted

**DEVIATION FROM INTERVIEW BRIEF:** The interview brief says "Keep as-is (visual debugger stays ObjC)." This file is intentionally deleted because it contains zero executable test code -- the entire file is commented out. Keeping a dead `.m` file would require a mixed-language test target for zero value. Deleting it avoids mixed-language compilation complexity in the test target.

## Constraints

- **Performance:** No performance regression. The CryptoKit encryption path may actually be faster than the CommonCrypto forward-declared function. Big-number arithmetic for compressed key decompression remains O(n) with n = key size (small, fixed).
- **Compatibility:** Public API surface must be identical. All public classes/methods need `@objc` and `NSObject` inheritance. `AvoInspectorEnv` and `AvoVisualInspectorType` enums must use `@objc` with matching raw values. `AvoVisualInspectorType` enum cases require explicit `@objc(Bar)` and `@objc(Bubble)` annotations to preserve the original unprefixed ObjC names.
- **Security:** No reference to `CCCryptorGCMOneshotEncrypt` or any private CommonCrypto symbol may appear anywhere in the compiled binary. CryptoKit + Security.framework only.
- **Storage:** NSUserDefaults keys (`"AvoInspectorAnonymousId"`, `"AvoBatcherSuiteKey"/"AvoBatcherCacheKey"`) must not change. Existing app installs upgrading from ObjC version must retain their data.
- **Networking:** Completion-handler style only. No async/await (requires iOS 15+). No Combine.
- **Minimum target:** iOS 13+ (required for CryptoKit). This is a breaking change from iOS 12.

## Out of Scope

- **Visual debugger migration** — Stays ObjC, not part of this migration
- **Android/Web SDK changes** — Those are separate repos
- **Server-side decryption changes for v0x01** — Already handled in the web app spec (separate work)
- **New features** — This is a code migration only, no new functionality
- **CocoaPods distribution** — The cocoapods repo gets its own v3.0.0 release independently
- **Async/await adoption** — Would require iOS 15+ minimum
- **SwiftUI integration** — Not in scope

## Edge Cases

| Case | Expected Behavior |
|------|------------------|
| Empty event properties `[:]` | `extractSchema` returns empty dictionary |
| `nil` event properties | `extractSchema` returns empty dictionary |
| Empty nested dictionary `{"key": {}}` | Returns `AvoObject` with empty `fields` (fix from fa5bed6) |
| `NSNull` values | Mapped to `AvoNull` in schema extraction |
| Non-string dictionary keys | Convert via `.description`, take last two dot-separated components |
| Encryption with nil plaintext | Returns nil |
| Encryption with nil/empty key | Returns nil |
| Encryption with invalid hex key (e.g., "deadbeef") | Returns nil (key too short to be valid EC key) |
| Encryption with compressed EC key | Decompresses via secp256r1 math, then encrypts normally |
| CryptoKit error during encryption | Caught by do/catch, returns nil, logs error |
| Network timeout in spec fetch | Semaphore times out, task cancelled, returns nil |
| Network error in batch send | Events re-added to queue for retry |
| Regex pattern with nested quantifiers `(a+)+` | Rejected by `isPatternPotentiallyDangerous`, skipped |
| Regex matching timeout (>2s) | Returns `NSNotFound`, constraint skipped (fail-open) |
| Storage unavailable (not initialized) | `anonymousId` returns `"unknown"` |
| >1000 events queued | Excess events trimmed from front of array |
| Events older than 0.3s in deduplicator | Cleared by `clearOldEvents` |
| Boolean vs NSNumber(1) distinction | Use `CFBooleanGetTypeID()` check to reliably detect booleans |
| `char` type in schema extraction | Mapped to `AvoString` (not `AvoInt`) — preserved from ObjC behavior |

## Acceptance Criteria

All criteria are binary pass/fail. A criterion passes only if the stated condition is verifiable with a single command or inspection.

**Source migration:**
- [ ] `find Sources/AvoInspector -name '*.h' -o -name '*.m'` returns zero results
- [ ] `find Sources/AvoInspector -type d -name 'include' -o -name 'types'` returns zero results (subdirectories deleted)
- [ ] `ls Sources/AvoInspector/*.swift | wc -l` returns exactly 22 (the 22 Swift files listed in Part 1 directory structure)
- [ ] Every `.swift` file in `Sources/AvoInspector/` contains `@objc` on its public class declaration (verify with: `grep -L '@objc' Sources/AvoInspector/*.swift` returns empty)
- [ ] `Package.swift` contains `.iOS(.v13)` (grep returns match)
- [ ] `grep -r 'CCCryptorGCMOneshotEncrypt\|CommonCrypto' Sources/` returns zero results
- [ ] `grep -r 'import CryptoKit' Sources/` returns exactly one result, in `AvoEncryption.swift`
- [ ] `grep 'libVersion.*=.*"4.0.0"' Sources/AvoInspector/AvoInspector.swift` returns a match

**Encryption:**
- [ ] `AvoEncryption.swift` calls `AES.GCM.seal` with a 12-byte nonce and prepends version byte `0x01`
- [ ] Encryption test decrypts output and verifies: `data[0] == 0x01`, `data[1..<66].count == 65`, `data[66..<78].count == 12`, `data[78..<94].count == 16`
- [ ] Encryption round-trip test: `decrypt(encrypt("hello"), privateKey)` returns `"hello"` for string, integer, double, and boolean JSON values
- [ ] Compressed key decompression test: secp256r1 generator point (`04 + known X + known Y`) round-trips correctly. This test must be an explicit test case in `AvoEncryptionTests.swift` (e.g., `test_compressedKeyDecompression_roundTrip`): compress a known uncompressed point, decompress it, and verify the result matches the original

**Public API preservation:**
- [ ] `AvoInspector` class conforms to `Inspector` protocol (compiler verifies)
- [ ] `AvoInspectorEnv` enum raw values: `AvoInspectorEnv.prod.rawValue == 0`, `.dev.rawValue == 1`, `.staging.rawValue == 2`
- [ ] `AvoStorage` protocol has exactly 3 methods: `isInitialized() -> Bool`, `getItem(_:) -> String?`, `setItem(_:_:)`
- [ ] `AvoInspector` has `appName` private property initialized from `Bundle.main.infoDictionary[kCFBundleIdentifierKey as String]`

**Storage compatibility:**
- [ ] `grep '"AvoInspectorAnonymousId"' Sources/AvoInspector/AvoAnonymousId.swift` returns a match
- [ ] `grep '"AvoBatcherSuiteKey"' Sources/AvoInspector/AvoBatcher.swift` returns a match
- [ ] `grep '"AvoBatcherCacheKey"' Sources/AvoInspector/AvoBatcher.swift` returns a match

**ReDoS protection:**
- [ ] `AvoEventValidator.swift` contains `isPatternPotentiallyDangerous` and `safeNumberOfMatches` methods
- [ ] `safeNumberOfMatches` dispatches onto a static serial queue `"com.avo.inspector.regex"` and uses `DispatchSemaphore` with timeout
- [ ] ReDoS tests pass: dangerous pattern detection, timeout returns `NSNotFound`, fail-open behavior

**Tests:**
- [ ] `find Tests/AvoInspectorTests -name '*.swift' | wc -l` returns exactly 23 (13 ported from SPM + 7 from cocoapods + 3 thread-safety)
- [ ] `find Tests -name '*.m'` returns zero results (all `.m` test files deleted, including `VisualDebuggerTests.m`)
- [ ] Thread-safety tests exist for `AvoAnonymousId`, `AvoDeduplicator`, and `AvoEventSpecCache` using `DispatchQueue.concurrentPerform`
- [ ] `swift test` passes with zero failures
- [ ] `grep -r 'async\s\+func\|await\s' Sources/` returns zero results (no async/await)
- [ ] `grep -r 'import Combine' Sources/` returns zero results
- [ ] `PrivacyInfo.xcprivacy` is listed in Package.swift resources and exists in `Sources/AvoInspector/`

## Open Questions Resolved

| Question | Resolution |
|----------|-----------|
| Should Package.swift include CryptoKit framework? | No. CryptoKit is available by default on iOS 13+. Just `import CryptoKit` in `AvoEncryption.swift`. |
| How to handle mixed ObjC (visual debugger tests) + Swift in SPM? | `VisualDebuggerTests.m` is entirely commented out and is deleted. The test target is pure Swift. No mixed-language complexity. |
| ReDoS branch merge status | The `fix/redos-vulnerability` branch is not yet merged to main. Either merge it first, or carry the pattern forward into Swift directly. The spec documents the exact pattern to preserve. |
| How to replace OCMock in Swift tests? | Use lightweight manual test doubles (subclasses that override methods and record calls). No third-party mocking framework. |
| Should compressed key decompression be preserved? | Yes. Tests verify it, and external consumers may pass compressed keys. The big-number math is ported to Swift. |
| Where does `import CommonCrypto` remain after migration? | Nowhere. `CC_SHA256` is replaced by `CryptoKit.SHA256.hash(data:)`. All CommonCrypto usage is eliminated. |
| What about the `handleSessionStarted` method referenced in BatchingTests? | This method was removed from `AvoBatcher` in the current codebase (not present in the SPM `.m` files). Tests referencing it should be updated to only test `handleTrackSchema`. |

## Dependencies

- **CryptoKit** (iOS 13+ system framework) — for AES-GCM encryption and SHA-256 hashing
- **Security.framework** (system) — for SecKey EC operations (key generation, ECDH, key import/export)
- **Foundation** (system) — URLSession, UserDefaults, JSONSerialization, etc.
- **Cocoapods ECIES v1 wire format spec** at `/Users/alexverein/code/avo/ios-avo-inspector/planning/ecies-v1-wire-format/spec.md` — defines the wire format this implementation must produce
- **Web app decryption update** — The web app's `InspectorStream__CryptoHelper.res` must accept version byte `0x01` for the new wire format to work end-to-end (separate work, already specified)

## Revision History

| Rev | Date | Author | Changes |
|-----|------|--------|---------|
| 1 | 2026-03-06 | Wednesday | Initial draft |
| 2 | 2026-03-06 | Wednesday | Morticia Rev 1 fixes: (1) Fixed AvoObject.name() to use append-then-strip comma pattern matching ObjC behavior [Critical, Issue 3]. (2) Added thread-safety test requirements for AvoAnonymousId, AvoDeduplicator, AvoEventSpecCache using concurrentPerform [Critical, Issue 8]. (3) Clarified test directory migration: all 14 .m files deleted, Tests/ replaced by Tests/AvoInspectorTests/ with pure Swift files, VisualDebuggerTests.m deleted [Important, Issue 1]. (4) Fixed test file counts: 13 SPM + 7 cocoapods = 20 test files, consistent throughout [Important, Issue 4]. (5) Added AvoEventSpecFetcherTests.swift to test table [Important, Issue 5]. (6) Enumerated all OCMock replacement needs with test-double strategy table and dependency injection seams for singletons [Important, Issue 9]. (7) Added explicit ReDoS protection test cases: dangerous pattern detection, timeout behavior, fail-open semantics [Important, Issue 10]. (8) Documented semaphore/queue constraints for AvoEventSpecFetcher.makeRequest to prevent deadlocks [Important, Issue 12]. Also addressed minor issues: added appName to AvoInspector class definition [Issue 7], added AvoEventSpecFetchTypes field mapping implementer note [Issue 6], completed decryption test helper [Issue 11], added pure-Swift target note about include/ directory removal [Issue 13], added implementation order note [Issue 2]. Strengthened all acceptance criteria to binary pass/fail with verifiable commands. |
| 3 | 2026-03-06 | Wednesday | Morticia Rev 2 fixes: (1) Removed spurious `"l"` (long) objCType from AvoInt mapping -- ObjC only checks `"i"`, `"s"`, `"q"` [Important, Issue 1 + Minor, Issue 9]. (2) Added behavioral parity documentation for NSNumber subclasses (NSConstantIntegerNumber, NSConstantDoubleNumber, NSConstantFloatNumber) and single-element collection types, with required test cases [Important, Issue 1]. (3) Added `init(apiKey:envInt:)` convenience initializer to AvoInspector spec [Minor, Issue 2]. (4) Fixed `formatTypeToString` method signature to auto-bridge correctly and added spec-wide `@objc` selector bridging guidance [Minor, Issue 3]. (5) Added complete fetch-validate-send flow documentation: `fetchAndValidateAsync`, `handleBranchChangeAndCache` (@synchronized pattern), `sendEventWithValidation`, `avoFunctionTrackSchemaFromEvent`, lifecycle methods, and `addObservers` commented-out state [Important, Issue 4 + Minor, Issue 6]. (6) Removed `AvoSessionTracker` from mock table -- class does not exist in either SPM or cocoapods repo [Minor, Issue 5]. (7) Fixed test count from 20 to 23: added 3 thread-safety test files to the test file table and updated all references (Goals, Affected Areas, authoritative count, acceptance criteria) [Important, Issue 7]. (8) Added 7 validation flow test specifications to TrackTests.swift covering cache hit/miss, fetch success/failure, branch change cache clear, no-fetcher fallback, and avoFunctionEventId extraction [Important, Issue 8]. (9) Added explicit compressed key round-trip test requirement to acceptance criteria [Minor, Issue 11]. |
| 4 | 2026-03-06 | Wednesday | Morticia Rev 3 fixes: (1) Added `@objc(Bar)` and `@objc(Bubble)` annotations to `AvoVisualInspectorType` enum cases to preserve original unprefixed ObjC names [Important, Issue 4]. (2) Added `@objc(setItem::)` annotation to `AvoStorage.setItem` protocol method to preserve the unnamed-second-parameter ObjC selector [Minor, Issue 5]. (3) Added `static` vs `class` intentional narrowing note on `Inspector` protocol [Minor, Issue 1]. (4) Added unsynchronized static vars note for `logging`, `maxBatchSize`, `batchFlushTime` matching ObjC behavior [Minor, Issue 2]. (5) Added `envInt.uintValue` divergence note from ObjC `intValue` [Minor, Issue 3]. (6) Added `eventSpecFetchTimeout` constant (`5.0`) to AvoInspector [Minor, Issue 6]. (7) Added `test_initWithEnvInt_mapsToCorrectEnv` test case to InitializationTests [Minor, Issue 7]. (8) Added `test_concurrentSafeNumberOfMatches_doesNotDeadlock` test case to AvoEventValidatorTests [Minor, Issue 8]. (9) Flagged VisualDebuggerTests.m deletion as explicit DEVIATION FROM INTERVIEW BRIEF [Minor, Issue 9]. (10) Replaced force-unwraps in AvoObject.name() with guard/as? to match ObjC's error-tolerant @try/@catch behavior [Minor, Issue 10]. (11) Added nonce generation comment clarifying why explicit-nonce API is used [Minor, Issue 11]. |
