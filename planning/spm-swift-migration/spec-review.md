# Spec Review: SPM Swift Migration -- Rev 4

**Reviewer:** Morticia (adversarial QA)
**Spec:** planning/spm-swift-migration/spec.md
**Revision:** 4 of 5
**Date:** 2026-03-06

---

## Rev 3 Issues -- Resolution Check

All issues from Rev 3 have been addressed:

| Rev 3 Issue | Status | Notes |
|-------------|--------|-------|
| Issue 4 (Important): `AvoVisualInspectorType` enum case ObjC names | RESOLVED | `@objc(Bar)` and `@objc(Bubble)` annotations added to enum cases. |
| Issue 5 (Minor): `AvoStorage.setItem` selector mismatch | RESOLVED | `@objc(setItem::)` annotation added to protocol method. |
| Issue 1 (Minor): `static` vs `class` protocol methods | RESOLVED | Intentional narrowing note added. |
| Issue 2 (Minor): Unsynchronized static vars | RESOLVED | Note added acknowledging intentional match with ObjC behavior. |
| Issue 3 (Minor): `envInt.uintValue` divergence | RESOLVED | Divergence noted with rationale. |
| Issue 6 (Minor): Missing `EVENT_SPEC_FETCH_TIMEOUT` | RESOLVED | `eventSpecFetchTimeout` constant added. |
| Issue 7 (Minor): No `envInt` init test | RESOLVED | `test_initWithEnvInt_mapsToCorrectEnv` added to InitializationTests. |
| Issue 8 (Minor): No concurrent `safeNumberOfMatches` test | RESOLVED | `test_concurrentSafeNumberOfMatches_doesNotDeadlock` added to AvoEventValidatorTests. |
| Issue 9 (Minor): VisualDebuggerTests.m deletion not flagged | RESOLVED | Explicit "DEVIATION FROM INTERVIEW BRIEF" label added. |
| Issue 10 (Minor): `AvoObject.name()` force-unwraps | RESOLVED | Replaced with `guard/as?` + `continue` for error tolerance. |
| Issue 11 (Minor): Nonce generation comment | RESOLVED | Comment added clarifying explicit-nonce API usage rationale. |

All 11 Rev 3 issues resolved. The spec is in strong shape.

---

## Stage 1: Architecture Review -- 23/25

The migration approach is sound and well-justified. Module boundaries are clear. The @objc bridging strategy is now thorough with explicit selector annotations, enum case annotations, and protocol compatibility notes. Thread safety patterns are specified for every synchronized module.

### Issue 1.1: Bool/char `objCType "c"` interaction needs explicit test (-1 pt)
**Severity:** Important

**Problem:** The spec's type detection strategy (lines 395-419) correctly places the `CFBooleanGetTypeID` check before `NSNumber` to catch booleans first. However, on some platforms `NSNumber(value: true)` has `objCType "c"` (same as `char`). The spec maps `"c"` to `AvoString` (line 399). If the `CFBooleanGetTypeID` guard fails or is implemented incorrectly, `true` would be misdetected as `AvoString` instead of `AvoBoolean`.

The spec documents the boolean detection challenge (line 419) and requires behavioral parity tests for `NSConstantIntegerNumber`, etc. (lines 410-416), but does not include an explicit test for the `true`-as-`"c"` interaction.

| Option | Tradeoff |
|--------|----------|
| A) Add test cases: `NSNumber(value: true)` -> `AvoBoolean` (not `AvoString`), and `NSNumber(value: Int8(65))` -> `AvoString` | Low effort, catches the most dangerous misdetection. (Recommended) |
| B) Add a comment noting the interaction but no test | Documents but does not verify. |

**Recommendation:** Option A. Add both test cases to `SimpleTypeSchemaExtractionTests.swift`.

### Issue 1.2: `safeNumberOfMatches` ObjC selector name change (-1 pt)
**Severity:** Minor

**Problem:** The ObjC method selector is `safeNumberOfMatchesWithRegex:inString:timeout:`. The spec's Swift signature `safeNumberOfMatches(with:in:timeout:)` auto-bridges to `safeNumberOfMatchesWith:in:timeout:` -- a different selector. Since this is a class method used only internally within `AvoEventValidator` and all callers are being migrated to Swift, the mismatch has no external impact. But it should be acknowledged as an intentional rename.

| Option | Tradeoff |
|--------|----------|
| A) Accept and add a one-line note that the ObjC selector changes | Low effort. (Recommended) |
| B) Add `@objc(safeNumberOfMatchesWithRegex:inString:timeout:)` | Preserves exact selector but adds clutter for an internal method. |

**Recommendation:** Option A.

---

## Stage 2: Completeness & Quality Review -- 22/25

Every ObjC file has a Swift replacement. Method signatures are detailed with @objc annotations. Storage keys are explicitly preserved. Wire format is fully specified. Rev 4 fixed the two most dangerous bridging issues (enum case names and setItem selector).

### Issue 2.1: Missing `init(apiKey:env:)` delegation chain (-1 pt)
**Severity:** Minor

**Problem:** The spec lists `init(apiKey:env:)` (line 685) as a public initializer but does not specify its implementation. The ObjC source does not have an explicit `initWithApiKey:env:` in the .m file either -- it appears to be a declaration in the .h that must delegate to the 4-argument initializer with default values (endpoint = `"https://api.avo.app/inspector/v1/track"`, publicEncryptionKey = nil).

The implementer can infer this from context, but a migration spec should be explicit about initializer delegation chains.

| Option | Tradeoff |
|--------|----------|
| A) Add a note: "`init(apiKey:env:)` is a convenience initializer that delegates to `init(apiKey:env:proxyEndpoint:publicEncryptionKey:)` with default endpoint and nil encryption key." | Low effort, explicit. (Recommended) |
| B) Leave as-is | Risk of implementer creating a separate init body. |

**Recommendation:** Option A.

### Issue 2.2: Missing `eventSpecFetcher`/`eventSpecCache` conditional initialization logic (-2 pts)
**Severity:** Important

**Problem:** The spec thoroughly documents the `fetchAndValidateAsync` flow and its guard conditions, but does not specify WHEN `eventSpecFetcher` and `eventSpecCache` are created. In the ObjC source (AvoInspector.m lines 148-165), these are conditionally initialized only when:
1. `publicEncryptionKey` is non-nil and non-empty
2. `env != AvoInspectorEnvProd`
3. `streamId` (anonymous ID) is valid (non-nil, non-empty, not `"unknown"`)

This is a non-obvious conditional initialization that determines whether the entire validation flow is active. An implementer reading only the spec would not know these conditions. The `fetchAndValidateAsync` guard conditions (line 738-742 in the spec) check if `eventSpecFetcher` is nil, but the spec never says when it would be nil vs non-nil.

| Option | Tradeoff |
|--------|----------|
| A) Add the conditional initialization logic to the AvoInspector init section | Low effort, prevents misimplementation. (Recommended) |
| B) Rely on implementer reading ObjC source | Risk of always-creating or never-creating the fetcher. |

**Recommendation:** Option A. This is the gating condition for the entire event-spec validation feature.

### Issue 2.3: `env` parameter type widening in `AvoNetworkCallsHandler` (-0 pts)
**Severity:** Informational (no deduction)

**Problem:** The ObjC `AvoNetworkCallsHandler` init takes `env:(int)env` (32-bit). The spec shows `env: Int` (64-bit on 64-bit platforms). Since the value range is 0-2 and this is internal, the widening is harmless. Just noting for completeness -- no action needed.

---

## Stage 3: Test & Edge Cases Review -- 23/25

Test coverage is thorough with 23 files consistently counted throughout. Specta-to-XCTest mapping is clear. Mock strategies are concrete. Thread-safety and ReDoS tests are well-specified. Validation flow tests cover all paths.

### Issue 3.1: No test for `AvoObject.name()` guard/as? fallback behavior (-1 pt)
**Severity:** Minor

**Problem:** Rev 4 replaced force-unwraps in `AvoObject.name()` with `guard/as?` + `continue` (line 228) to match ObjC's error-tolerant behavior. This is a good defensive change, but there is no test that exercises the fallback path -- what happens when `AvoObject.fields` contains a value that is not an `AvoEventSchemaType`?

| Option | Tradeoff |
|--------|----------|
| A) Add a test in `DictionarySchemaExtractionTests.swift`: manually insert a non-`AvoEventSchemaType` value into `AvoObject.fields`, call `name()`, assert it skips the bad entry without crashing | Low effort, validates the defensive change. (Recommended) |
| B) Accept -- unlikely edge case | The guard/as? change was specifically made for this case, so it should be tested. |

**Recommendation:** Option A.

### Issue 3.2: `AvoList.name()` and `AvoObject.name()` iteration order is nondeterministic (-1 pt)
**Severity:** Minor

**Problem:** `AvoList.subtypes` is `NSMutableSet` (unordered) and `AvoObject.fields` is `NSMutableDictionary` (unordered keys). The `name()` methods iterate these collections and build string output. The order is nondeterministic, meaning `"list(int|string)"` and `"list(string|int)"` are both valid outputs for the same content. This matches ObjC behavior, so it's not a bug.

However, the spec does not mention this, and an implementer writing tests that assert on `name()` string output will create flaky tests.

| Option | Tradeoff |
|--------|----------|
| A) Add a note in the test section: "Tests comparing `AvoList.name()` or `AvoObject.name()` output must account for nondeterministic iteration order. Use set-based comparisons or test with single-element collections." | Low effort, prevents flaky tests. (Recommended) |
| B) Sort subtypes/keys in `name()` for deterministic output | Behavioral change from ObjC -- out of scope. |

**Recommendation:** Option A.

---

## Stage 4: Performance & Feasibility Review -- 23/25

iOS 13 minimum is enforced consistently. No impossible or contradictory requirements. The big-bang approach is realistic given the spec's thorough coverage. Acceptance criteria are binary pass/fail with concrete shell commands.

### Issue 4.1: Concurrent `safeNumberOfMatches` test may be extremely slow (-2 pts)
**Severity:** Important

**Problem:** The spec (line 1221) adds `test_concurrentSafeNumberOfMatches_doesNotDeadlock` which calls `safeNumberOfMatches` from 50 concurrent threads via `DispatchQueue.concurrentPerform(iterations: 50)`. The method dispatches work onto a shared SERIAL queue and blocks the calling thread with a semaphore until completion (or timeout).

With 50 concurrent callers, each dispatching onto the serial queue:
- The serial queue processes regex evaluations one at a time
- Each blocked caller waits up to 2 seconds (the default timeout from line 484 of AvoEventValidator.m)
- In the worst case, later callers wait for all prior evaluations to complete

Even with a "simple regex and short input," 50 serial evaluations could take several seconds total. The test description says "simple regex and short input" but does not specify overriding the timeout parameter to something shorter.

If the test uses the default 2-second timeout, and a slow CI machine causes regex evaluations to take slightly longer, later callers' semaphore waits will stack up. This won't deadlock (it will eventually complete), but may exceed XCTest's test-method timeout.

| Option | Tradeoff |
|--------|----------|
| A) Specify that the test should pass an explicit short timeout (e.g., 0.5 seconds) to prevent semaphore backup on slow CI | Low effort, prevents false failures. (Recommended) |
| B) Reduce iteration count to 10 | Weakens the concurrency test. |
| C) Both A and B | Overkill. |

**Recommendation:** Option A. The test already calls `safeNumberOfMatches(with:in:timeout:)` which accepts a timeout parameter. Passing 0.5 seconds means backed-up calls return `NSNotFound` quickly. Add to the test description: "Use a timeout of 0.5 seconds to prevent serial queue backup from exceeding XCTest timeout."

---

## Strengths

Rev 4 is a polished spec. Specific strengths:

- All 11 Rev 3 issues resolved thoroughly. `@objc(Bar)`, `@objc(Bubble)`, and `@objc(setItem::)` annotations fix real API breakage risks.
- `AvoObject.name()` guard/as? change is a genuine improvement over force-unwraps, matching ObjC's error-tolerant semantics.
- `AvoVisualInspectorType` enum cases now preserve exact ObjC names.
- The `static` vs `class` protocol note and unsynchronized static vars note show attention to semantic accuracy.
- `envInt.uintValue` divergence is properly documented as an intentional improvement.
- `eventSpecFetchTimeout` constant is now included.
- `test_initWithEnvInt_mapsToCorrectEnv` and `test_concurrentSafeNumberOfMatches_doesNotDeadlock` fill real test gaps.
- VisualDebuggerTests.m deletion is properly flagged as a deviation from the interview brief.
- Nonce generation comment prevents implementer confusion about the explicit-nonce API choice.
- Revision history is detailed and traceable.

---

## Summary

| Stage | Score | Top Remaining Issue |
|-------|-------|---------------------|
| Architecture | 23/25 | Bool/char objCType interaction needs test (Issue 1.1) |
| Completeness & Quality | 22/25 | Missing eventSpecFetcher/Cache conditional init logic (Issue 2.2) |
| Test & Edge Cases | 23/25 | No test for AvoObject.name() guard fallback (Issue 3.1) |
| Performance & Feasibility | 23/25 | Concurrent regex test timeout concern (Issue 4.1) |
| **Total** | **91/100** | |

**Issue Count:**
- Critical: 0
- Important: 2 (Issue 1.1: Bool/char test, Issue 2.2: conditional init logic, Issue 4.1: concurrent test timeout)
- Minor: 4 (Issues 1.2, 2.1, 3.1, 3.2)
- Informational: 1 (Issue 2.3)

**Verdict:** PASS

The spec is ready for implementation. The remaining issues are addressable with small additions: two missing test cases, one missing initialization logic block, one test parameter clarification, and documentation notes. No structural or architectural problems remain. Rev 4 successfully resolved all Rev 3 issues including the important @objc bridging correctness items. A Rev 5 addressing Issues 1.1, 2.2, and 4.1 would bring this to production quality with zero known gaps.
