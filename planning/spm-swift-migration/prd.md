# PRD: SPM Swift Migration

**Feature Name:** spm-swift-migration
**Branch:** fester/spm-swift-migration
**Base Branch:** main
**Created:** 2026-03-06
**Spec:** planning/spm-swift-migration/spec.md
**Review:** planning/spm-swift-migration/spec-review.md

---

## Overview

Migrate the AvoInspectorSPM library from Objective-C to Swift. This eliminates the App Store rejection caused by `CCCryptorGCMOneshotEncrypt` (a private CommonCrypto symbol) by rewriting encryption with CryptoKit. All 46 ObjC source files are replaced with 22 Swift files. All tests are ported from Specta/Expecta ObjC to Swift XCTest (23 test files). The public API is preserved with `@objc` annotations. Minimum deployment target moves to iOS 13+. Library version becomes 4.0.0.

---

## Stories

### Story 1: Package Infrastructure and Type System

**ID:** `story-1-package-and-types`
**Approach:** `general-purpose`
**Priority:** `p0`
**Depends On:** (none)

**Description:**
Update `Package.swift` for iOS 13+ and Swift-only target. Create all 9 type system Swift files (AvoEventSchemaType base class + 6 leaf types + AvoList + AvoObject). Delete the `types/` subdirectory ObjC files (18 .h/.m files). This is the foundation that all other modules depend on.

**Estimated Files:**
- `Package.swift` (modify)
- `Sources/AvoInspector/AvoEventSchemaType.swift` (create)
- `Sources/AvoInspector/AvoInt.swift` (create)
- `Sources/AvoInspector/AvoFloat.swift` (create)
- `Sources/AvoInspector/AvoBoolean.swift` (create)
- `Sources/AvoInspector/AvoString.swift` (create)
- `Sources/AvoInspector/AvoNull.swift` (create)
- `Sources/AvoInspector/AvoUnknownType.swift` (create)
- `Sources/AvoInspector/AvoList.swift` (create)
- `Sources/AvoInspector/AvoObject.swift` (create)
- Delete: `Sources/AvoInspector/types/` directory (all .h/.m files)

**Acceptance Criteria:**
- [ ] `Package.swift` contains `.iOS(.v13)` and a `testTarget` named `AvoInspectorTests`
- [ ] All 9 type Swift files exist in `Sources/AvoInspector/`
- [ ] Every type class has `@objc public class` declaration inheriting from `NSObject` (or `AvoEventSchemaType`)
- [ ] `AvoEventSchemaType` has `name()`, `isEqual(_:)`, `hash`, `description` implementations
- [ ] `AvoList.subtypes` is `NSMutableSet` and `AvoObject.fields` is `NSMutableDictionary`
- [ ] `AvoObject.name()` uses guard/as? (not force-unwraps) for error tolerance
- [ ] No .h or .m files remain in `Sources/AvoInspector/types/`
- [ ] `swift build` succeeds

**Quality Checks:**
- `swift build` (required: true)

**Test Pattern:** Type correctness verified in Story 7 (SimpleTypeSchemaExtractionTests, DictionarySchemaExtractionTests, ListSchemaExtractionTests).

---

### Story 2: Core Utilities (Storage, Guid, Utils, AnonymousId)

**ID:** `story-2-core-utilities`
**Approach:** `general-purpose`
**Priority:** `p0`
**Depends On:** `story-1-package-and-types`

**Description:**
Migrate the small utility modules: AvoStorage (protocol only), AvoGuid, AvoUtils, AvoAnonymousId. These are dependencies for most other modules. AvoAnonymousId requires NSLock-based thread safety replacing `@synchronized`. Storage key `"AvoInspectorAnonymousId"` must be preserved. Delete corresponding ObjC files.

**Estimated Files:**
- `Sources/AvoInspector/AvoStorage.swift` (create)
- `Sources/AvoInspector/AvoGuid.swift` (create)
- `Sources/AvoInspector/AvoUtils.swift` (create)
- `Sources/AvoInspector/AvoAnonymousId.swift` (create)
- Delete: `Sources/AvoInspector/AvoStorage.h`, `AvoUtils.h`, `AvoUtils.m`, `AvoGuid.h`, `AvoGuid.m`, `AvoAnonymousId.h`, `AvoAnonymousId.m`

**Acceptance Criteria:**
- [ ] `AvoStorage` protocol has `@objc(setItem::)` annotation on `setItem` method
- [ ] `AvoAnonymousId` uses `NSLock` for thread safety
- [ ] Storage key `"AvoInspectorAnonymousId"` is preserved
- [ ] `AvoUtils.currentTimeAsISO8601UTCString()` uses `en_US_POSIX` locale and UTC timezone
- [ ] No ObjC utility files remain
- [ ] `swift build` succeeds

**Quality Checks:**
- `swift build` (required: true)

**Test Pattern:** AvoAnonymousIdTests (Story 9), AvoAnonymousIdThreadSafetyTests (Story 11).

---

### Story 3: Schema Extraction and Deduplication

**ID:** `story-3-schema-and-dedup`
**Approach:** `general-purpose`
**Priority:** `p0`
**Depends On:** `story-1-package-and-types`

**Description:**
Migrate AvoSchemaExtractor and AvoDeduplicator. Schema extraction requires careful type detection: CFBooleanGetTypeID check before NSNumber, objCType-based int/float detection (only "i", "s", "q" for int -- no "l"), NSNull/String/Array/Set/Dictionary handling. AvoDeduplicator uses a serial DispatchQueue replacing `@synchronized` and a `static let` singleton. The 0.3-second stale event threshold must be preserved.

**Estimated Files:**
- `Sources/AvoInspector/AvoSchemaExtractor.swift` (create)
- `Sources/AvoInspector/AvoDeduplicator.swift` (create)
- Delete: `Sources/AvoInspector/AvoSchemaExtractor.h`, `AvoSchemaExtractor.m`, `AvoDeduplicator.h`, `AvoDeduplicator.m`

**Acceptance Criteria:**
- [ ] Boolean detection uses `CFGetTypeID(obj as CFTypeRef) == CFBooleanGetTypeID()` before NSNumber check
- [ ] objCType mapping: "i","s","q" -> AvoInt; "c" -> AvoString; "d","f" and other -> AvoFloat
- [ ] No "l" (long) in AvoInt mapping
- [ ] Empty nested dictionaries produce AvoObject with empty fields
- [ ] AvoDeduplicator uses serial DispatchQueue for synchronized access
- [ ] `clearOldEvents` uses 0.3-second threshold
- [ ] `swift build` succeeds

**Quality Checks:**
- `swift build` (required: true)

**Test Pattern:** SimpleTypeSchemaExtractionTests, ListSchemaExtractionTests, DictionarySchemaExtractionTests, DeduplicatorTests (Story 7).

---

### Story 4: Encryption (CryptoKit + v0x01 Wire Format)

**ID:** `story-4-encryption`
**Approach:** `general-purpose`
**Priority:** `p0`
**Depends On:** `story-1-package-and-types`

**Description:**
Complete rewrite of AvoEncryption using CryptoKit. Implements v0x01 wire format: version byte 0x01, 65-byte ephemeral public key, 12-byte nonce (not 16-byte IV), 16-byte auth tag, N-byte ciphertext. Uses SecKey for EC operations and CryptoKit AES.GCM for encryption. Preserves secp256r1 compressed key decompression with big-number arithmetic. Eliminates all CommonCrypto references.

**Estimated Files:**
- `Sources/AvoInspector/AvoEncryption.swift` (create)
- Delete: `Sources/AvoInspector/AvoEncryption.h`, `AvoEncryption.m`

**Acceptance Criteria:**
- [ ] `import CryptoKit` present, no `CommonCrypto` anywhere in Sources/
- [ ] Version byte is `0x01`
- [ ] Nonce is 12 bytes (CryptoKit AES.GCM.Nonce)
- [ ] Wire format: [0x01][65-byte pubkey][12-byte nonce][16-byte tag][ciphertext]
- [ ] KDF is SHA256(shared_secret) via CryptoKit
- [ ] Compressed key decompression preserves secp256r1 curve math
- [ ] `encrypt()` returns nil for nil/empty inputs
- [ ] `swift build` succeeds

**Quality Checks:**
- `swift build` (required: true)

**Test Pattern:** AvoEncryptionTests, AvoEncryptionIntegrationTests (Story 10).

---

### Story 5: Networking, Batching, and Event Validation

**ID:** `story-5-networking-batching-validation`
**Approach:** `general-purpose`
**Priority:** `p0`
**Depends On:** `story-1-package-and-types`, `story-4-encryption`

**Description:**
Migrate AvoNetworkCallsHandler, AvoBatcher, AvoEventValidator, AvoEventSpecFetcher, AvoEventSpecCache, and AvoEventSpecFetchTypes. Networking uses completion handlers (no async/await). Batching preserves storage keys "AvoBatcherSuiteKey"/"AvoBatcherCacheKey" and 1000-event cap. Event validator preserves ReDoS protection: `isPatternPotentiallyDangerous` and `safeNumberOfMatches` with shared static serial queue and semaphore timeout. Event spec fetcher preserves semaphore-based sync requests with deadlock prevention. All wire type field mappings preserved exactly.

**Estimated Files:**
- `Sources/AvoInspector/AvoNetworkCallsHandler.swift` (create)
- `Sources/AvoInspector/AvoBatcher.swift` (create)
- `Sources/AvoInspector/AvoEventValidator.swift` (create)
- `Sources/AvoInspector/AvoEventSpecFetcher.swift` (create)
- `Sources/AvoInspector/AvoEventSpecCache.swift` (create)
- `Sources/AvoInspector/AvoEventSpecFetchTypes.swift` (create)
- Delete: corresponding .h/.m pairs (12 files)

**Acceptance Criteria:**
- [ ] Storage keys "AvoBatcherSuiteKey" and "AvoBatcherCacheKey" preserved in AvoBatcher
- [ ] Event cap of 1000 preserved
- [ ] `safeNumberOfMatches` dispatches onto static serial queue `"com.avo.inspector.regex"` with DispatchSemaphore timeout
- [ ] `isPatternPotentiallyDangerous` checks for nested quantifiers
- [ ] AvoEventSpecFetcher uses semaphore-based sync request with `dispatchPrecondition(condition: .notOnQueue(.main))`
- [ ] AvoEventSpecCache uses NSLock for thread safety
- [ ] No async/await or Combine imports
- [ ] `swift build` succeeds

**Quality Checks:**
- `swift build` (required: true)

**Test Pattern:** BatchingTests, NetworkCallsHandlerTests, SamplingTests, AvoEventValidatorTests, AvoEventSpecFetcherTests, AvoEventSpecCacheTests (Stories 8, 9, 10).

---

### Story 6: Main Inspector Class and ObjC File Cleanup

**ID:** `story-6-inspector-main`
**Approach:** `general-purpose`
**Priority:** `p0`
**Depends On:** `story-2-core-utilities`, `story-3-schema-and-dedup`, `story-5-networking-batching-validation`

**Description:**
Migrate the main AvoInspector class. Includes AvoInspectorEnv and AvoVisualInspectorType enums with @objc annotations (including `@objc(Bar)` and `@objc(Bubble)` on enum cases), Inspector protocol, AvoStorageImpl private class, all public initializers (including `init(apiKey:envInt:)` convenience), the fetch-validate-send flow, branch change detection, lifecycle methods, commented-out notification observers, and dependency injection seams for testing. Delete all remaining ObjC files including the `include/` directory. Update libVersion to "4.0.0".

**Estimated Files:**
- `Sources/AvoInspector/AvoInspector.swift` (create)
- Delete: `Sources/AvoInspector/AvoInspector.m`, `Sources/AvoInspector/include/AvoInspector.h`, `Sources/AvoInspector/include/Inspector.h`
- Delete: any remaining .h/.m files in `Sources/AvoInspector/`

**Acceptance Criteria:**
- [ ] `AvoInspectorEnv` raw values: prod=0, dev=1, staging=2
- [ ] `AvoVisualInspectorType` has `@objc(Bar)` and `@objc(Bubble)` case annotations
- [ ] `Inspector` protocol conforms to `NSObjectProtocol`
- [ ] `AvoStorageImpl` is private, uses `UserDefaults.standard`
- [ ] `init(apiKey:envInt:)` uses `uintValue` with `.dev` fallback
- [ ] `eventSpecFetchTimeout` constant is 5.0
- [ ] Conditional initialization of `eventSpecFetcher`/`eventSpecCache` based on publicEncryptionKey, env, and streamId
- [ ] `handleBranchChangeAndCache` uses NSLock or objc_sync for thread safety
- [ ] `addObservers` notification registrations remain commented out
- [ ] `libVersion` is `"4.0.0"`
- [ ] `find Sources/AvoInspector -name '*.h' -o -name '*.m'` returns zero results
- [ ] `find Sources/AvoInspector -type d -name 'include' -o -name 'types'` returns zero results
- [ ] `swift build` succeeds

**Quality Checks:**
- `swift build` (required: true)

**Test Pattern:** InitializationTests, TrackTests, LogsTests, SessionTests, SessionBetweenRestartsTests, EnvironmentMappingTests (Stories 7, 8).

---

### Story 7: Port SPM Test Files -- Schema and Core Tests

**ID:** `story-7-tests-schema-core`
**Approach:** `general-purpose`
**Priority:** `p1`
**Depends On:** `story-6-inspector-main`

**Description:**
Port the 7 schema/core test files from SPM repo ObjC Specta/Expecta to Swift XCTest. Create the test directory structure. Delete all existing ObjC test files. Includes test doubles (MockNetworkCallsHandler, MockBatcher, MockStorage). Tests must account for nondeterministic iteration order in AvoList.name() and AvoObject.name(). Add Bool/char objCType interaction tests (NSNumber(value: true) -> AvoBoolean not AvoString) and AvoObject.name() guard fallback test per review issues 1.1 and 3.1.

**Estimated Files:**
- `Tests/AvoInspectorTests/SimpleTypeSchemaExtractionTests.swift` (create)
- `Tests/AvoInspectorTests/DictionarySchemaExtractionTests.swift` (create)
- `Tests/AvoInspectorTests/ListSchemaExtractionTests.swift` (create)
- `Tests/AvoInspectorTests/DeduplicatorTests.swift` (create)
- `Tests/AvoInspectorTests/InitializationTests.swift` (create)
- `Tests/AvoInspectorTests/EnvironmentMappingTests.swift` (create)
- `Tests/AvoInspectorTests/LogsTests.swift` (create)
- Delete: all .m test files in `Tests/`, `Tests-Info.plist`, `Tests-Prefix.pch`, `Info.plist`

**Acceptance Criteria:**
- [ ] 7 Swift test files exist in `Tests/AvoInspectorTests/`
- [ ] No .m files remain in `Tests/`
- [ ] `test_initWithEnvInt_mapsToCorrectEnv` tests NSNumber(value:1) -> .dev and NSNumber(value:0) -> .prod
- [ ] Bool/char test: NSNumber(value: true) -> AvoBoolean, NSNumber(value: Int8(65)) -> AvoString
- [ ] AvoObject.name() guard fallback test: non-AvoEventSchemaType value in fields is skipped without crash
- [ ] Nondeterministic iteration order handled (single-element collections or set-based assertions)
- [ ] Behavioral parity tests for NSConstantIntegerNumber, NSConstantDoubleNumber, single-element collections
- [ ] `swift build` succeeds
- [ ] `swift test` passes for these test files

**Quality Checks:**
- `swift build` (required: true)
- `swift test` (required: true)

**Test Pattern:** XCTestCase classes with `test_` method naming.

---

### Story 8: Port SPM Test Files -- Track, Batching, Session, Sampling

**ID:** `story-8-tests-track-batch-session`
**Approach:** `general-purpose`
**Priority:** `p1`
**Depends On:** `story-7-tests-schema-core`

**Description:**
Port the remaining 6 SPM repo test files: TrackTests, BatchingTests, NetworkCallsHandlerTests, SamplingTests, SessionTests, SessionBetweenRestartsTests. Includes MockNetworkCallsHandler, MockBatcher, MockEventSpecFetcher, MockEventSpecCache test doubles. TrackTests includes the 7 validation flow test cases covering cache hit/miss, fetch success/failure, branch change, no-fetcher fallback, and avoFunctionEventId extraction.

**Estimated Files:**
- `Tests/AvoInspectorTests/TrackTests.swift` (create)
- `Tests/AvoInspectorTests/BatchingTests.swift` (create)
- `Tests/AvoInspectorTests/NetworkCallsHandlerTests.swift` (create)
- `Tests/AvoInspectorTests/SamplingTests.swift` (create)
- `Tests/AvoInspectorTests/SessionTests.swift` (create)
- `Tests/AvoInspectorTests/SessionBetweenRestartsTests.swift` (create)

**Acceptance Criteria:**
- [ ] 6 Swift test files created in `Tests/AvoInspectorTests/`
- [ ] MockNetworkCallsHandler captures `callInspectorWithBatchBody` and `reportValidatedEvent` calls
- [ ] MockBatcher captures `handleTrackSchema` calls
- [ ] TrackTests includes all 7 validation flow test cases
- [ ] `test_avoFunctionTrackSchemaFromEvent_extractsEventIdAndHash` verifies key extraction
- [ ] `swift test` passes for these test files

**Quality Checks:**
- `swift build` (required: true)
- `swift test` (required: true)

**Test Pattern:** XCTestCase classes with test doubles (subclass overrides).

---

### Story 9: Port Cocoapods-Only Test Files

**ID:** `story-9-tests-cocoapods`
**Approach:** `general-purpose`
**Priority:** `p1`
**Depends On:** `story-7-tests-schema-core`

**Description:**
Port the 4 cocoapods-only test files that do not involve encryption: AvoAnonymousIdTests, AvoEventSpecCacheTests, AvoEventSpecFetcherTests, AvoEventValidatorTests. Source from `/Users/alexverein/code/avo/ios-avo-inspector/Example/Tests/`. AvoEventValidatorTests must include all ReDoS protection tests: dangerous pattern detection, safe pattern acceptance, correct match count, NSNotFound on timeout, fail-open behavior, and concurrent safeNumberOfMatches (with 0.5s timeout to prevent serial queue backup per review issue 4.1). Selector name change for safeNumberOfMatches acknowledged per review issue 1.2.

**Estimated Files:**
- `Tests/AvoInspectorTests/AvoAnonymousIdTests.swift` (create)
- `Tests/AvoInspectorTests/AvoEventSpecCacheTests.swift` (create)
- `Tests/AvoInspectorTests/AvoEventSpecFetcherTests.swift` (create)
- `Tests/AvoInspectorTests/AvoEventValidatorTests.swift` (create)

**Acceptance Criteria:**
- [ ] 4 Swift test files created
- [ ] `test_isPatternPotentiallyDangerous_detectsNestedQuantifiers` tests "(a+)+", "(a+)*", "([a-z]+)*"
- [ ] `test_isPatternPotentiallyDangerous_allowsSafePatterns` tests "[a-z]+", "\\d{3}-\\d{4}"
- [ ] `test_safeNumberOfMatches_returnsCorrectCount` verifies count of 2 for "[0-9]+" in "abc 123 def 456"
- [ ] `test_safeNumberOfMatches_returnsNSNotFoundOnTimeout` uses 0.001s timeout
- [ ] `test_failOpenBehavior_skipsConstraintOnTimeout` verifies fail-open
- [ ] `test_concurrentSafeNumberOfMatches_doesNotDeadlock` uses 50 iterations with 0.5s timeout
- [ ] `swift test` passes for these test files

**Quality Checks:**
- `swift build` (required: true)
- `swift test` (required: true)

**Test Pattern:** XCTestCase classes porting from Specta/Expecta ObjC.

---

### Story 10: Port Encryption Test Files

**ID:** `story-10-tests-encryption`
**Approach:** `general-purpose`
**Priority:** `p1`
**Depends On:** `story-9-tests-cocoapods`

**Description:**
Port the 2 encryption test files from cocoapods, updated for v0x01 wire format. Test decryption helper uses CryptoKit (SHA256.hash, AES.GCM.open). Wire format validation: version byte 0x01, 12-byte nonce at offset 66, auth tag at offset 78, ciphertext at offset 94, minimum 95 bytes. Includes round-trip tests for string/integer/double/boolean values and compressed key decompression round-trip test.

**Estimated Files:**
- `Tests/AvoInspectorTests/AvoEncryptionTests.swift` (create)
- `Tests/AvoInspectorTests/AvoEncryptionIntegrationTests.swift` (create)

**Acceptance Criteria:**
- [ ] 2 Swift test files created
- [ ] Test decryption helper checks version byte 0x01
- [ ] Wire format offsets: pubkey [1,66), nonce [66,78), tag [78,94), ciphertext [94,...)
- [ ] Round-trip test: decrypt(encrypt("hello"), privateKey) == "hello"
- [ ] Compressed key decompression round-trip test exists
- [ ] `generateTestPrivateKey()` and `publicKeyHexFromPrivateKey(_:)` helpers ported
- [ ] `swift test` passes for these test files

**Quality Checks:**
- `swift build` (required: true)
- `swift test` (required: true)

**Test Pattern:** CryptoKit-based test decryption helper, SecKey test key generation.

---

### Story 11: Thread Safety Tests

**ID:** `story-11-tests-thread-safety`
**Approach:** `general-purpose`
**Priority:** `p1`
**Depends On:** `story-9-tests-cocoapods`

**Description:**
Create 3 new thread-safety test files validating that NSLock/serial-queue replacements for `@synchronized` do not introduce data races or deadlocks. Uses `DispatchQueue.concurrentPerform` with 50-100 iterations. Covers AvoAnonymousId (concurrent get/set/clear), AvoDeduplicator (concurrent shouldRegisterEvent/clearOldEvents), and AvoEventSpecCache (concurrent get/set/contains/clear).

**Estimated Files:**
- `Tests/AvoInspectorTests/AvoAnonymousIdThreadSafetyTests.swift` (create)
- `Tests/AvoInspectorTests/AvoDeduplicatorThreadSafetyTests.swift` (create)
- `Tests/AvoInspectorTests/AvoEventSpecCacheThreadSafetyTests.swift` (create)

**Acceptance Criteria:**
- [ ] 3 Swift test files created
- [ ] AvoAnonymousIdThreadSafetyTests: concurrent access returns consistent value, concurrent set/get doesn't crash, concurrent clear/get doesn't crash
- [ ] AvoDeduplicatorThreadSafetyTests: concurrent shouldRegisterEvent doesn't crash, concurrent clearOldEvents interleaved doesn't crash
- [ ] AvoEventSpecCacheThreadSafetyTests: concurrent get/set/contains doesn't crash, concurrent clear/set doesn't crash
- [ ] All tests use `DispatchQueue.concurrentPerform` with 50+ iterations
- [ ] `swift test` passes for these test files
- [ ] Total test file count: `find Tests/AvoInspectorTests -name '*.swift' | wc -l` returns exactly 23

**Quality Checks:**
- `swift build` (required: true)
- `swift test` (required: true)

**Test Pattern:** Concurrent access via `DispatchQueue.concurrentPerform`, pass = no crash/hang.

---

## Dependency Graph

```
story-1-package-and-types
  |
  +-- story-2-core-utilities
  |     |
  |     +-- story-6-inspector-main --+
  |                                   |
  +-- story-3-schema-and-dedup ------+
  |                                   |
  +-- story-4-encryption             |
  |     |                             |
  |     +-- story-5-networking ------+
  |                                   |
  +-----------------------------------+
                                      |
                            story-6-inspector-main
                                      |
                            story-7-tests-schema-core
                                      |
                         +------------+------------+
                         |                         |
              story-8-tests-track       story-9-tests-cocoapods
                                                   |
                                        +----------+----------+
                                        |                      |
                              story-10-tests-encrypt  story-11-thread-safety
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Boolean/NSNumber detection regression | Medium | High | CFBooleanGetTypeID check before NSNumber; explicit test for true-as-"c" interaction (review issue 1.1) |
| ObjC selector mismatch breaking consumers | Low | High | Explicit @objc annotations on all public API; AvoStorage setItem:: and enum case names verified |
| ReDoS timeout mechanism regression | Low | High | Exact preservation of serial queue + semaphore pattern; 6 explicit test cases |
| Storage key change breaking upgrades | Low | High | Grep-verified acceptance criteria for all 3 storage keys |
| Encryption wire format incompatibility | Medium | High | Round-trip tests with test decryption helper; wire format offset assertions |
| Thread safety regression from @synchronized removal | Medium | Medium | 3 dedicated thread-safety test files with concurrent access patterns |
| Compressed key decompression math error | Low | Medium | Preserved big-number arithmetic with round-trip test |
| Concurrent safeNumberOfMatches test timeout on CI | Medium | Low | Use 0.5s timeout parameter per review issue 4.1 |
| Missing conditional init logic for eventSpecFetcher | Medium | Medium | Review issue 2.2 documented; acceptance criteria verifies conditional initialization |
