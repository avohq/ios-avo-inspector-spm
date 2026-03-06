# PRD Review: SPM Swift Migration

**Reviewer:** Thing (PRD QA)
**PRD:** planning/spm-swift-migration/prd.md
**Spec:** planning/spm-swift-migration/spec.md
**Revision:** 1/5
**Date:** 2026-03-06

## Engineering Preferences Applied
- DRY: flagged aggressively
- Testing: non-negotiable, more > fewer
- Engineering level: "enough" -- not fragile, not over-abstracted
- Edge cases: err on more, not fewer
- Style: explicit over clever

## Structural Validation

- [x] Valid JSON (parseable)
- [x] All required fields present (`featureName`, `branchName`, `baseBranch`, `createdAt`, `specPath`, `reviewPath`, `maxIterations`, `stories`)
- [x] Every story has all required fields (`id`, `title`, `description`, `approach`, `acceptanceCriteria`, `priority`, `dependsOn`, `estimatedFiles`, `qualityChecks`, `status`, `testPattern`)
- [x] All 11 story IDs are unique
- [x] All `dependsOn` references point to existing story IDs
- [x] No circular dependencies (graph walked)
- [x] All `approach` values are `general-purpose` (no `.claude/agents/` directory exists, so this is correct)
- [ ] All `priority` values are valid -- **ISSUE: uses `p0`/`p1` instead of `critical`/`high`/`medium`/`low`**
- [x] All `status` values are `pending`
- [x] `maxIterations` (22) >= 2 * number of stories (11) -- exactly 2x
- [x] `branchName` follows `fester/spm-swift-migration` convention

**Structural validation: CONDITIONAL PASS** -- priority enum values are non-standard but unambiguous. See Issue 1 below.

---

## Stage 1: Architecture Review -- 22/25

The dependency graph is well-structured. Types come first (Story 1), then modules build on types in parallel (Stories 2, 3, 4), then the integration layer (Stories 5, 6), then tests in dependency order (Stories 7-11). Each implementation story can be committed independently. The graph depth is 6 (1 -> 4 -> 5 -> 6 -> 7 -> 9 -> 10), which is reasonable for an 11-story PRD.

### Issue 1: Non-standard priority enum values
**Severity:** Minor
**Location:** All stories in prd.json
**Problem:** The `priority` field uses `p0` and `p1` instead of the standard `critical`/`high`/`medium`/`low` values. While unambiguous (p0 = implementation stories, p1 = test stories), this may cause parsing issues if the execution engine expects the standard enum.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Change to `critical` (p0) and `high` (p1) | Low | Low | Low | Low |
| B) Do nothing -- if execution engine accepts `p0`/`p1` | None | Medium | -- | -- |

**Recommendation:** Option A -- use standard enum values to avoid any tooling incompatibility. All 6 implementation stories become `critical`, all 5 test stories become `high`.

### Issue 2: Story 1 exceeds file count guideline (10 files + deletions)
**Severity:** Important
**Location:** `story-1-package-and-types`
**Problem:** Story 1 has 10 estimated files (Package.swift + 9 type files) plus it must delete 18 ObjC files in `types/`. That is at least 28 file operations. While the 9 type files are structurally similar (leaf classes with ~20 lines each), the combined scope increases risk of a single build failure blocking the entire foundation layer.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Split into Story 1a (Package.swift + AvoEventSchemaType + AvoList + AvoObject) and Story 1b (6 leaf types + delete ObjC) | Medium | Low | Medium | Low |
| B) Keep as-is -- the leaf types are trivial boilerplate | None | Medium | -- | -- |
| C) Keep as-is but add a note that leaf types are ~20 lines each | Low | Low | Low | Low |

**Recommendation:** Option B -- splitting would add a dependency hop and the leaf types are genuinely trivial (each is a class inheriting AvoEventSchemaType with a name() method). The description is explicit enough for autonomous execution.

### Issue 3: Story 6 estimatedFiles undercounts -- only lists 1 file but deletes many
**Severity:** Important
**Location:** `story-6-inspector-main`
**Problem:** The `estimatedFiles` array in prd.json lists only `AvoInspector.swift` (1 file). However, the PRD description and acceptance criteria require deleting `AvoInspector.m`, `include/AvoInspector.h`, `include/Inspector.h`, and "any remaining .h/.m files." The actual deletion count depends on what Stories 1-5 already cleaned up, but at minimum 3 files must be deleted. The `estimatedFiles` should reflect the true file operation count for accurate Fester planning.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Add the deletion targets to estimatedFiles (AvoInspector.m, include/AvoInspector.h, include/Inspector.h) | Low | Low | Medium | Low |
| B) Do nothing -- acceptance criteria already verify zero .h/.m files remain | None | Low | -- | -- |

**Recommendation:** Option A -- explicit file lists prevent Fester from underestimating the story scope.

---

## Stage 2: Story Quality Review -- 22/25

Stories are well-scoped with specific file paths, concrete implementation details, and clear acceptance criteria. Descriptions reference specific patterns (CFBooleanGetTypeID, NSLock, serial DispatchQueue) rather than vague instructions. The PRD incorporates all Morticia review issues (1.1, 1.2, 2.2, 3.1, 3.2, 4.1).

### Issue 4: ObjC file deletion responsibilities are ambiguous across stories
**Severity:** Important
**Location:** Stories 1-6
**Problem:** Multiple stories mention deleting ObjC files, but the boundaries are not fully explicit:
- Story 1 says "Delete: Sources/AvoInspector/types/ directory (all .h/.m files)" -- 18 files
- Story 2 says "Delete: AvoStorage.h, AvoUtils.h, AvoUtils.m, AvoGuid.h, AvoGuid.m, AvoAnonymousId.h, AvoAnonymousId.m" -- 7 files
- Story 3 says "Delete: AvoSchemaExtractor.h, AvoSchemaExtractor.m, AvoDeduplicator.h, AvoDeduplicator.m" -- 4 files
- Story 4 says "Delete: AvoEncryption.h, AvoEncryption.m" -- 2 files
- Story 5 says "Delete: corresponding .h/.m pairs (12 files)" -- but does not enumerate them
- Story 6 says "Delete: AvoInspector.m, include/AvoInspector.h, include/Inspector.h" + "any remaining .h/.m files"

Story 5's "12 files" claim: AvoNetworkCallsHandler (2) + AvoBatcher (2) + AvoEventValidator (2) + AvoEventSpecFetcher (2) + AvoEventSpecCache (2) + AvoEventSpecFetchTypes (2) = 12. This is correct but should be enumerated explicitly to prevent ambiguity during autonomous execution.

Total accounted: 18 + 7 + 4 + 2 + 12 + 3 = 46. This matches the actual 46 ObjC files. Good.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Enumerate all 12 deletion targets in Story 5's description | Low | Low | Medium | Low |
| B) Do nothing -- Story 6's "any remaining" catch-all handles drift | None | Low | -- | -- |

**Recommendation:** Option A -- explicit is better than clever. Enumerate the 6 .h/.m pairs in Story 5.

### Issue 5: Story 7 test doubles may conflict with Story 8 test doubles
**Severity:** Minor
**Location:** `story-7-tests-schema-core`, `story-8-tests-track-batch-session`
**Problem:** Story 7 mentions creating "MockNetworkCallsHandler, MockBatcher, MockStorage" test doubles. Story 8 also mentions "MockNetworkCallsHandler, MockBatcher, MockEventSpecFetcher, MockEventSpecCache." If these are defined in separate test files, there will be duplicate class definitions causing build failures. If they are defined in the same shared file, the PRD does not specify which story creates that file.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Add a shared `TestDoubles.swift` file to Story 7's estimatedFiles, and have Story 8 extend it | Low | Low | High | Low |
| B) Define mocks inline in each test file with file-private scope | Low | Low | Medium | Medium |
| C) Do nothing -- assume the agent will figure it out | None | High | -- | -- |

**Recommendation:** Option A -- add `Tests/AvoInspectorTests/TestDoubles.swift` to Story 7's estimated files and note that Story 8 adds MockEventSpecFetcher and MockEventSpecCache to it. This prevents duplicate class errors and follows DRY.

### Issue 6: Spec acceptance criterion for exactly 22 Swift source files not in PRD
**Severity:** Minor
**Location:** Spec acceptance criteria vs PRD stories
**Problem:** The spec states: "`ls Sources/AvoInspector/*.swift | wc -l` returns exactly 22." The PRD does not include this as an acceptance criterion on any story. Counting the PRD's estimated files: Story 1 (9) + Story 2 (4) + Story 3 (2) + Story 4 (1) + Story 5 (6) + Story 6 (1) = 23, not 22. However, `AvoStorage.swift` is a protocol-only file -- it might be that the spec counts differently, or there is an off-by-one. Either way, Story 6 (the final implementation story) should verify the total count.

Actually, recounting from the spec's directory listing would be the authoritative source. The PRD creates 23 Swift files total in Sources/. This discrepancy needs resolution.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Add the 22-file count acceptance criterion to Story 6 and verify which count is correct | Low | Low | Medium | Low |
| B) Do nothing -- the per-story file checks are sufficient | None | Low | -- | -- |

**Recommendation:** Option A -- verify whether the correct count is 22 or 23, then add to Story 6's acceptance criteria.

---

## Stage 3: Test & Acceptance Review -- 23/25

Every implementation story has a `testPattern` field pointing to specific test stories. Every test story has both `swift build` and `swift test` quality checks. Acceptance criteria are binary pass/fail with concrete assertions. The PRD correctly incorporates all Morticia review recommendations (Bool/char tests, guard fallback test, nondeterministic iteration, 0.5s timeout).

### Issue 7: Story 8 missing `swift build` quality check mention in acceptance criteria
**Severity:** Minor
**Location:** `story-8-tests-track-batch-session`
**Problem:** Story 8's acceptance criteria list only 5 items, and the last one is "`swift test` passes for these test files." The `swift build succeeds` criterion is missing from the acceptance criteria text, though it IS present in the `qualityChecks` array in prd.json. This is inconsistent with other test stories (7, 9, 10, 11) which all include both in their acceptance criteria text.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Add "swift build succeeds" to Story 8's acceptance criteria | Low | Low | Low | Low |
| B) Do nothing -- qualityChecks in JSON already includes it | None | Low | -- | -- |

**Recommendation:** Option A -- consistency across stories aids autonomous execution.

### Issue 8: No acceptance criterion for PrivacyInfo.xcprivacy preservation
**Severity:** Minor
**Location:** Spec acceptance criteria vs PRD stories
**Problem:** The spec states: "`PrivacyInfo.xcprivacy` is listed in Package.swift resources and exists in `Sources/AvoInspector/`." No PRD story includes this as an acceptance criterion. Story 1 modifies Package.swift and could accidentally remove the resource declaration. The file itself already exists and should be preserved.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Add a criterion to Story 1: "Package.swift preserves `.copy("PrivacyInfo.xcprivacy")` in resources" | Low | Low | Low | Low |
| B) Do nothing -- the spec shows the full Package.swift with the resource line | None | Low | -- | -- |

**Recommendation:** Option A -- defensive criterion costs nothing and prevents accidental regression.

---

## Stage 4: Execution & Performance Review -- 21/25

### Issue 9: maxIterations at exactly 2x may be tight for this migration
**Severity:** Important
**Location:** prd.json `maxIterations: 22`
**Problem:** With 11 stories and `maxIterations` of 22 (exactly 2x), there is zero margin for retry. This is a complete ObjC-to-Swift migration with complex modules (encryption with big-number math, ReDoS protection, semaphore-based networking). If even one story requires a third iteration attempt, the entire run fails. Stories 4 (encryption) and 5 (networking/validation with 6 files) are particularly risky.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Increase to 28 (2.5x) to allow 1-2 retries | Low | Low | Medium | Low |
| B) Increase to 33 (3x) for maximum safety | Low | Low | Medium | Low |
| C) Keep at 22 | None | High | -- | -- |

**Recommendation:** Option A -- 28 iterations gives a comfortable buffer. 3x would be overly conservative for a well-specified PRD.

### Issue 10: Story 5 is the largest implementation story (6 files, 6 modules)
**Severity:** Important
**Location:** `story-5-networking-batching-validation`
**Problem:** Story 5 creates 6 Swift files spanning 6 distinct modules (networking, batching, event validation, spec fetching, spec caching, fetch types). Each has its own threading model, error handling, and test surface. This is the most complex implementation story and the most likely to fail or require multiple iterations. The 6 files are at the upper bound of the 5-7 file guideline, but the conceptual complexity exceeds what the file count suggests.

The modules have internal dependencies too: AvoNetworkCallsHandler depends on AvoEncryption (Story 4), AvoBatcher depends on AvoNetworkCallsHandler, AvoEventValidator is standalone, AvoEventSpecFetcher depends on AvoNetworkCallsHandler and AvoEventSpecCache, AvoEventSpecFetchTypes is standalone.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Split into Story 5a (AvoEventSpecFetchTypes + AvoEventValidator -- standalone, no deps) and Story 5b (AvoNetworkCallsHandler + AvoBatcher + AvoEventSpecFetcher + AvoEventSpecCache -- interconnected) | Medium | Low | High | Low |
| B) Keep as-is but increase maxIterations to compensate | Low | Medium | Low | Low |
| C) Keep as-is | None | High | -- | -- |

**Recommendation:** Option B -- splitting would add dependency graph complexity and the modules, while conceptually distinct, all need each other to compile (AvoBatcher references AvoNetworkCallsHandler, etc). Increasing maxIterations (Issue 9) compensates for the retry risk.

### Issue 11: Stories 7-11 test execution depends on ALL implementation being complete
**Severity:** Minor
**Location:** `story-7-tests-schema-core` depends on `story-6-inspector-main`
**Problem:** Story 7 (first test story) depends on Story 6, which depends on Stories 2, 3, and 5. This means NO tests run until ALL implementation is complete. If there is a subtle bug in Story 1's type system, it will not be caught until Story 7 runs -- potentially 6 iterations later. This is inherent to the migration approach (you cannot test Swift code that does not exist yet), but it is a risk worth noting.

| Option | Effort | Risk | Impact | Maintenance |
|--------|--------|------|--------|-------------|
| A) Accept as inherent to migration -- tests cannot run until implementation compiles | None | Medium | -- | -- |
| B) Add a simple smoke-test story after Story 1 that verifies basic type instantiation | Medium | Low | Low | Medium |

**Recommendation:** Option A -- the `swift build` quality check on every implementation story provides compile-time verification. Adding a smoke test would increase story count without meaningful benefit since the type system is straightforward.

---

## Spec Coverage Analysis

| Spec Acceptance Criterion | Covered By | Status |
|--------------------------|-----------|--------|
| Zero .h/.m files in Sources/ | story-6 AC #11 | Covered |
| Zero include/types subdirectories | story-6 AC #12 | Covered |
| Exactly 22 Swift source files | -- | **Gap** (see Issue 6) |
| Every .swift has @objc on public class | Not explicit | **Gap** |
| Package.swift contains .iOS(.v13) | story-1 AC #1 | Covered |
| No CCCryptorGCMOneshotEncrypt/CommonCrypto | story-4 AC #1 | Covered |
| Exactly one CryptoKit import (AvoEncryption.swift) | story-4 AC #1 (partial) | Partial -- checks presence, not uniqueness |
| libVersion 4.0.0 | story-6 AC #10 | Covered |
| AES.GCM.seal with 12-byte nonce, 0x01 version | story-4 AC #2-4 | Covered |
| Encryption round-trip test | story-10 AC #4 | Covered |
| Compressed key decompression round-trip | story-10 AC #5 | Covered |
| AvoInspector conforms to Inspector protocol | story-6 AC #3 | Covered |
| AvoInspectorEnv raw values | story-6 AC #1 | Covered |
| AvoStorage 3 methods | story-2 AC #1 (partial) | Partial -- checks setItem annotation but not method count |
| appName from Bundle.main | Not explicit | **Gap** |
| Storage key AvoInspectorAnonymousId | story-2 AC #3 | Covered |
| Storage keys AvoBatcherSuiteKey/CacheKey | story-5 AC #1 | Covered |
| ReDoS isPatternPotentiallyDangerous + safeNumberOfMatches | story-5 AC #3-4 | Covered |
| ReDoS tests pass | story-9 AC #2-7 | Covered |
| 23 test files total | story-11 AC #7 | Covered |
| Zero .m test files | story-7 AC #2 | Covered |
| Thread-safety tests exist | story-11 AC #1-5 | Covered |
| swift test passes | story-7/8/9/10/11 QC | Covered |
| No async/await | story-5 AC #7 | Covered |
| No Combine | story-5 AC #7 (implicit) | Partial -- criterion says "No async/await or Combine imports" |
| PrivacyInfo.xcprivacy preserved | -- | **Gap** (see Issue 8) |
| Wire format offsets validated in tests | story-10 AC #3 | Covered |

**Coverage gaps:** 4 minor gaps identified (22-file count, @objc on every file, appName property, PrivacyInfo preservation). None are Critical.

## Strengths

- **Thorough Morticia integration.** Every review issue (1.1, 1.2, 2.2, 3.1, 3.2, 4.1) is reflected in story descriptions and acceptance criteria. The PRD does not just acknowledge the issues -- it bakes them into concrete test assertions (Bool/char test, guard fallback test, 0.5s timeout).
- **Precise acceptance criteria.** Criteria like "objCType mapping: i/s/q -> AvoInt; c -> AvoString; d/f and other -> AvoFloat" are specific enough for autonomous verification without interpretation.
- **Risk table is realistic.** The PRD identifies 9 risks with concrete mitigations, including the less-obvious ones (compressed key math, concurrent regex test timeout, conditional init logic).
- **Clean dependency graph.** Implementation stories fan out after Story 1 (3 parallel tracks: utilities, schema, encryption), converge at Story 6, then test stories fan out again. Maximizes parallelism.
- **Storage key preservation.** All 3 storage keys are explicitly called out with grep-verifiable acceptance criteria. This is the most common data-loss bug in migrations.

---

## Summary

| Stage | Score | Top Issue |
|-------|-------|-----------|
| Architecture | 22/25 | Story 1 has 10+ files (Issue 2), Story 6 undercounts files (Issue 3) |
| Story Quality | 22/25 | Test doubles may conflict between Stories 7/8 (Issue 5), ObjC deletions in Story 5 not enumerated (Issue 4) |
| Test & Acceptance | 23/25 | Missing PrivacyInfo and 22-file-count spec criteria (Issues 6, 8) |
| Execution & Performance | 21/25 | maxIterations too tight at 2x (Issue 9), Story 5 is oversized (Issue 10) |
| **Total** | **88/100** | |

**Verdict:** PASS
**Critical issues:** 0
**Important issues:** 4 (Issues 2, 4, 9, 10)
**Minor issues:** 7 (Issues 1, 3, 5, 6, 7, 8, 11)

## Recommendation

This PRD is ready for autonomous execution. The Important issues are real but non-blocking:

1. **Issue 9 (maxIterations)** -- Increase from 22 to 28. This is the single highest-value change. A tight iteration budget on a complex migration is asking for trouble.
2. **Issue 5 (test doubles)** -- Add a shared `TestDoubles.swift` to Story 7's file list. This prevents a guaranteed build failure when Story 8 re-declares the same mock classes.
3. **Issues 4 and 10** -- Acceptable as-is if maxIterations is increased.

Address Issues 9 and 5, then run `/fester spm-swift-migration` to begin.
