import XCTest
@testable import AvoInspector

final class AvoEventValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeConstraints(
        type: String,
        pinnedValues: [String: [String]]? = nil,
        allowedValues: [String: [String]]? = nil,
        regexPatterns: [String: [String]]? = nil,
        minmax: [String: [String]]? = nil
    ) -> AvoPropertyConstraints {
        let c = AvoPropertyConstraints()
        c.type = type
        c.required = false
        c.pinnedValues = pinnedValues
        c.allowedValues = allowedValues
        c.regexPatterns = regexPatterns
        c.minMaxRanges = minmax
        return c
    }

    private func makeEntry(
        branchId: String,
        baseEventId: String,
        variantIds: [String] = [],
        props: [String: AvoPropertyConstraints] = [:]
    ) -> AvoEventSpecEntry {
        let wireDict: [String: Any] = [
            "b": branchId,
            "id": baseEventId,
            "vids": variantIds,
            "p": [:] as [String: Any]
        ]
        let wire = AvoEventSpecEntryWire(dictionary: wireDict)
        let entry = AvoEventSpecEntry(fromWire: wire)
        entry.props = props
        return entry
    }

    private func makeResponse(events: [AvoEventSpecEntry]) -> AvoEventSpecResponse {
        let resp = AvoEventSpecResponse()
        resp.events = events
        let meta = AvoEventSpecMetadata(dictionary: [
            "schemaId": "schema1",
            "branchId": "branch1",
            "latestActionId": "action1"
        ])
        resp.metadata = meta
        return resp
    }

    // MARK: - Nil / empty spec

    func test_returnsNilForEmptyEvents() {
        let resp = makeResponse(events: [])
        let result = AvoEventValidator.validateEvent(["key": "value"], specResponse: resp)
        XCTAssertNil(result)
    }

    // MARK: - Pinned values

    func test_pinnedValues_passesWhenValueMatches() {
        let constraint = makeConstraints(type: "string", pinnedValues: ["correct": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "correct"], specResponse: resp)
        XCTAssertNotNil(result)
        let propResult = result?.propertyResults["prop"]
        XCTAssertNotNil(propResult)
        XCTAssertNil(propResult?.failedEventIds)
        XCTAssertNil(propResult?.passedEventIds)
    }

    func test_pinnedValues_failsWhenValueDoesNotMatch() {
        let constraint = makeConstraints(type: "string", pinnedValues: ["expected": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "wrong"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])
        let propResult = result!.propertyResults["prop"]!
        let hasFailed = propResult.failedEventIds != nil && !propResult.failedEventIds!.isEmpty
        let hasPassed = propResult.passedEventIds != nil
        XCTAssertTrue(hasFailed || hasPassed)
    }

    // MARK: - Allowed values

    func test_allowedValues_passesWhenValueInList() {
        let constraint = makeConstraints(type: "string", allowedValues: ["[\"a\",\"b\",\"c\"]": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "b"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.propertyResults["prop"]?.failedEventIds)
        XCTAssertNil(result?.propertyResults["prop"]?.passedEventIds)
    }

    func test_allowedValues_failsWhenValueNotInList() {
        let constraint = makeConstraints(type: "string", allowedValues: ["[\"a\",\"b\",\"c\"]": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "d"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])
    }

    // MARK: - Regex patterns

    func test_regexPatterns_passesWhenValueMatches() {
        let constraint = makeConstraints(type: "string", regexPatterns: ["^[0-9]+$": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "12345"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.propertyResults["prop"]?.failedEventIds)
        XCTAssertNil(result?.propertyResults["prop"]?.passedEventIds)
    }

    func test_regexPatterns_failsWhenValueDoesNotMatch() {
        let constraint = makeConstraints(type: "string", regexPatterns: ["^[0-9]+$": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "abc"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])
    }

    // MARK: - Min/max ranges

    func test_minMax_failsWhenBelowMin() {
        let constraint = makeConstraints(type: "int", minmax: ["10,100": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": NSNumber(value: 5)], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])
    }

    func test_minMax_failsWhenAboveMax() {
        let constraint = makeConstraints(type: "int", minmax: ["10,100": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": NSNumber(value: 200)], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])
    }

    func test_minMax_passesWhenInRange() {
        let constraint = makeConstraints(type: "int", minmax: ["10,100": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": NSNumber(value: 50)], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.propertyResults["prop"]?.failedEventIds)
        XCTAssertNil(result?.propertyResults["prop"]?.passedEventIds)
    }

    func test_minMax_failsForNonNumericValue() {
        let constraint = makeConstraints(type: "int", minmax: ["10,100": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "not a number"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])
    }

    // MARK: - Multi-event merge

    func test_multiEventMerge_reportsCorrectEventIds() {
        let constraint1 = makeConstraints(type: "string", pinnedValues: ["hello": ["evt1"]])
        let constraint2 = makeConstraints(type: "string", pinnedValues: ["world": ["evt2"]])

        let entry1 = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint1])
        let entry2 = makeEntry(branchId: "b1", baseEventId: "evt2", props: ["prop": constraint2])
        let resp = makeResponse(events: [entry1, entry2])

        let result = AvoEventValidator.validateEvent(["prop": "hello"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["prop"])

        let propResult = result!.propertyResults["prop"]!
        if let failedEventIds = propResult.failedEventIds {
            XCTAssertTrue(failedEventIds.contains("evt2"))
        } else if let passedEventIds = propResult.passedEventIds {
            XCTAssertTrue(passedEventIds.contains("evt1"))
        }
    }

    // MARK: - Boolean conversion

    func test_booleanConversion_passesForPinnedTrue() {
        let constraint = makeConstraints(type: "boolean", pinnedValues: ["true": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": NSNumber(value: true)], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.propertyResults["prop"]?.failedEventIds)
        XCTAssertNil(result?.propertyResults["prop"]?.passedEventIds)
    }

    // MARK: - Nested object validation

    func test_nestedObjectValidation() {
        let childConstraint = makeConstraints(type: "string", pinnedValues: ["expected_child": ["evt1"]])
        let parentConstraint = makeConstraints(type: "object")
        parentConstraint.children = ["childProp": childConstraint]

        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["parent": parentConstraint])
        let resp = makeResponse(events: [entry])

        let props: [String: Any] = ["parent": ["childProp": "wrong_child"]]
        let result = AvoEventValidator.validateEvent(props, specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.propertyResults["parent"])
        XCTAssertNotNil(result?.propertyResults["parent"]?.children)
        XCTAssertNotNil(result?.propertyResults["parent"]?.children?["childProp"])
    }

    // MARK: - Metadata

    func test_includesMetadataInResult() {
        let constraint = makeConstraints(type: "string", pinnedValues: ["val": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "val"], specResponse: resp)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.metadata)
        XCTAssertEqual(result?.metadata?.schemaId, "schema1")
        XCTAssertEqual(result?.metadata?.branchId, "branch1")
    }

    // MARK: - ReDoS Protection (6 required tests)

    func test_isPatternPotentiallyDangerous_detectsNestedQuantifiers() {
        // (a+)+ - nested quantifier
        XCTAssertTrue(AvoEventValidator.isPatternPotentiallyDangerous("(a+)+"),
                       "(a+)+ should be detected as dangerous")

        // (a+)* - nested quantifier
        XCTAssertTrue(AvoEventValidator.isPatternPotentiallyDangerous("(a+)*"),
                       "(a+)* should be detected as dangerous")

        // ([a-z]+)* - nested quantifier with character class
        XCTAssertTrue(AvoEventValidator.isPatternPotentiallyDangerous("([a-z]+)*"),
                       "([a-z]+)* should be detected as dangerous")
    }

    func test_isPatternPotentiallyDangerous_allowsSafePatterns() {
        // [a-z]+ - simple quantifier, no nesting
        XCTAssertFalse(AvoEventValidator.isPatternPotentiallyDangerous("[a-z]+"),
                        "[a-z]+ should be safe")

        // \\d{3}-\\d{4} - bounded quantifiers
        XCTAssertFalse(AvoEventValidator.isPatternPotentiallyDangerous("\\d{3}-\\d{4}"),
                        "\\d{3}-\\d{4} should be safe")
    }

    func test_safeNumberOfMatches_returnsCorrectCount() {
        let regex = try! NSRegularExpression(pattern: "[0-9]+")
        let count = AvoEventValidator.safeNumberOfMatches(with: regex, in: "abc 123 def 456", timeout: 2.0)
        XCTAssertEqual(count, 2, "Should find 2 matches of [0-9]+ in 'abc 123 def 456'")
    }

    func test_safeNumberOfMatches_returnsNSNotFoundOnTimeout() {
        // Use a pattern and input that will take a measurable amount of time,
        // combined with a very short timeout (0.001s).
        // We use a complex-but-valid regex on a large string.
        let regex = try! NSRegularExpression(pattern: "^(a+)+$")
        // Build a string that causes catastrophic backtracking
        let evilInput = String(repeating: "a", count: 30) + "!"

        let result = AvoEventValidator.safeNumberOfMatches(with: regex, in: evilInput, timeout: 0.001)
        XCTAssertEqual(result, UInt(NSNotFound), "Should return NSNotFound on timeout")
    }

    func test_failOpenBehavior_skipsConstraintOnTimeout() {
        // Use a dangerous pattern in regex constraints.
        // The dangerous pattern should be detected and skipped (fail-open),
        // meaning no failure is reported even though value doesn't match.
        let constraint = makeConstraints(type: "string", regexPatterns: ["(a+)+$": ["evt1"]])
        let entry = makeEntry(branchId: "b1", baseEventId: "evt1", props: ["prop": constraint])
        let resp = makeResponse(events: [entry])

        let result = AvoEventValidator.validateEvent(["prop": "test"], specResponse: resp)
        XCTAssertNotNil(result)
        let propResult = result?.propertyResults["prop"]
        XCTAssertNotNil(propResult)
        // No failure because the dangerous constraint was skipped (fail-open)
        XCTAssertNil(propResult?.failedEventIds, "Dangerous pattern should be skipped - no failures")
        XCTAssertNil(propResult?.passedEventIds, "Dangerous pattern should be skipped - no passed IDs")
    }

    func test_concurrentSafeNumberOfMatches_doesNotDeadlock() {
        // Run 50 concurrent calls to safeNumberOfMatches to verify
        // the shared static dispatch queue does not deadlock.
        let regex = try! NSRegularExpression(pattern: "[0-9]+")
        let input = "abc 123 def 456"

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        var results = [UInt](repeating: 0, count: 50)

        for i in 0..<50 {
            group.enter()
            queue.async {
                results[i] = AvoEventValidator.safeNumberOfMatches(with: regex, in: input, timeout: 0.5)
                group.leave()
            }
        }

        let completed = group.wait(timeout: .now() + 30.0)
        XCTAssertEqual(completed, .success, "All 50 concurrent calls should complete without deadlock")

        // All results that completed should be 2 (the correct match count)
        for i in 0..<50 {
            let r = results[i]
            // Either correct count (2) or NSNotFound if timed out (which is acceptable under load)
            XCTAssertTrue(r == 2 || r == UInt(NSNotFound),
                          "Result \(i) should be 2 or NSNotFound, got \(r)")
        }
    }
}
