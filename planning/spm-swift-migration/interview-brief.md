# Interview Brief: SPM Swift Migration

**Feature Name:** spm-swift-migration
**Date:** 2026-03-06

## Problem & Goals

The AvoInspectorSPM library is currently written entirely in Objective-C (.h/.m pairs). It needs to be migrated to pure Swift for two reasons:

1. **App Store rejection fix** — The cocoapods repo (`ios-avo-inspector`) uses `CCCryptorGCMOneshotEncrypt`, a private/undocumented CommonCrypto symbol that causes App Store rejection. The fix requires CryptoKit (Swift-only). The cocoapods repo is getting a final ObjC release with a thin Swift CryptoKit wrapper (`AvoGCMEncryptor.swift`). This SPM repo should go full Swift instead.

2. **This becomes the main repo** — The cocoapods repo gets its last release. This SPM repo becomes the primary distribution going forward.

## ECIES v1 Wire Format (from cocoapods spec)

The encryption fix changes the wire format:
- **v0x00 (legacy):** 1-byte version + 65-byte ephemeral pubkey + 16-byte IV + 16-byte auth tag + ciphertext = 98 + n bytes
- **v0x01 (new):** 1-byte version + 65-byte ephemeral pubkey + 12-byte nonce + 16-byte auth tag + ciphertext = 94 + n bytes

Key details:
- CryptoKit `AES.GCM.Nonce(data:)` requires exactly 12 bytes (throws for any other length)
- Use `CryptoKit.AES.GCM.seal(_:using:nonce:)` (three-argument overload with caller-supplied nonce)
- iOS Security.framework always produces 65-byte uncompressed ephemeral keys
- No AAD (matches original CCCryptorGCMOneshotEncrypt which passed NULL, 0 for AAD)
- Full spec at: `/Users/alexverein/code/avo/ios-avo-inspector/planning/ecies-v1-wire-format/spec.md`

## Scope & Approach

**Big-bang rewrite:** All .h/.m files replaced with .swift files in a single migration. No incremental mixed ObjC/Swift.

### Files to migrate (Sources/AvoInspector/):
- `AvoInspector.h/.m` — Main inspector class
- `AvoEncryption.h/.m` — ECIES encryption (gets CryptoKit rewrite + v0x01 wire format)
- `AvoSchemaExtractor.h/.m` — Schema extraction from event properties
- `AvoBatcher.h/.m` — Event batching
- `AvoNetworkCallsHandler.h/.m` — Network calls (NSURLSession)
- `AvoDeduplicator.h/.m` — Event deduplication
- `AvoEventValidator.h/.m` — Event spec validation
- `AvoEventSpecFetcher.h/.m` — Fetch event specs from server
- `AvoEventSpecCache.h/.m` — Cache event specs
- `AvoEventSpecFetchTypes.h/.m` — Types for spec fetching
- `AvoGuid.h/.m` — GUID generation
- `AvoAnonymousId.h/.m` — Anonymous ID management
- `AvoStorage.h` — Storage protocol/interface
- `AvoUtils.h/.m` — Utilities
- `include/Inspector.h` — Umbrella header
- `include/AvoInspector.h` — Public header
- Type classes in `types/`: AvoBoolean, AvoFloat, AvoInt, AvoList, AvoNull, AvoString, AvoUnknownType, AvoObject, AvoEventSchemaType

### Tests to port from cocoapods repo (`/Users/alexverein/code/avo/ios-avo-inspector/Example/Tests/`):
- `AvoEncryptionTests.m` — Encryption unit tests (update for v0x01)
- `AvoEncryptionIntegrationTests.m` — Encryption integration tests
- `AvoEventSpecCacheTests.m`
- `AvoEventSpecFetcherTests.m`
- `AvoEventValidatorTests.m`
- `AvoAnonymousIdTests.m`
- `BatchingTests.m`
- `DeduplicatorTests.m`
- `DictionarySchemaExtractionTests.m`
- `SimpleTypeSchemaExtractionTests.m`
- `ListSchemaExtractionTests.m`
- `EnvironmentMappingTest.m`
- `InitializationTests.m`
- `LogsTests.m`
- `NetworkCallsHandlerTests.m`
- `SamplingTests.m`
- `TrackTests.m`

Note: CocoaPods tests use Specta/Expecta (BDD-style ObjC). Swift tests should use XCTest.

### Existing SPM test:
- `Tests/VisualDebuggerTests.m` — Keep as-is (visual debugger stays ObjC)

## Constraints

- **Public API preservation:** Same class names, method signatures. Existing Swift and ObjC consumers should not break.
- **@objc compatibility:** All public classes/methods need `@objc` annotations and `NSObject` inheritance since ObjC consumers may exist.
- **iOS 13+ minimum** (up from iOS 12) — required for CryptoKit.
- **Completion-handler style networking** — No async/await (would require iOS 15+).
- **Storage compatibility:** Same storage keys/mechanism (NSUserDefaults) so existing app installs don't lose data on upgrade.
- **Version bump to 4.0.0** — Independent from cocoapods (which goes to 3.0.0).
- **ReDoS protection pattern:** The `fix/redos-vulnerability` branch adds regex timeout protection. This pattern should be preserved in the Swift migration. NOTE: This branch is NOT yet merged to main as of 2026-03-06 — needs to be merged first, or the pattern carried forward regardless.
- **Visual debugger:** Keep in ObjC, use existing dependency. Don't migrate.

## Edge Cases

- Empty/nil event properties in schema extraction
- Empty nested dictionaries (fix already on main: fa5bed6)
- Network failures / timeouts in AvoNetworkCallsHandler
- Regex patterns that could cause ReDoS — use timeout pattern
- Encryption failure (key generation, CryptoKit errors) — return nil gracefully
- Storage unavailable or corrupted
- Thread safety (AvoAnonymousId has synchronization fix on main: d39edda)

## Acceptance Criteria

- All ObjC source files (.h/.m) in Sources/AvoInspector/ replaced with Swift equivalents
- Public API surface preserved with @objc annotations for ObjC compatibility
- AvoEncryption rewritten to use CryptoKit with v0x01 wire format (12-byte nonce)
- No references to CCCryptorGCMOneshotEncrypt in the codebase
- Package.swift updated: iOS 13+ minimum, version 4.0.0
- All 17 test files from cocoapods repo ported to Swift XCTest
- All tests pass
- Visual debugger test (VisualDebuggerTests.m) still works
- Storage keys/mechanisms unchanged for upgrade compatibility
- ReDoS timeout pattern preserved in Swift
- No async/await — completion handlers only

## Open Questions

| Question | Resolution |
|----------|-----------|
| Should Package.swift include CryptoKit framework? | CryptoKit is available by default on iOS 13+, just `import CryptoKit` in Swift files |
| How to handle mixed ObjC (visual debugger tests) + Swift sources in SPM? | SPM supports mixed-language targets since Swift 5.9. The visual debugger test stays .m |
| ReDoS branch merge status | User says it's merged but git shows it's not on main yet. Spec should note to merge first or carry the pattern. |
