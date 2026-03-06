import Foundation

@objc public class AvoEventValidator: NSObject {

    private static let maxChildDepth = 2
    private static let regexCache = NSCache<NSString, NSRegularExpression>()
    private static let allowedValuesCache = NSCache<NSString, NSArray>()

    private static let regexQueue = DispatchQueue(label: "com.avo.inspector.regex")

    static let regexCacheLimit = 100
    static let allowedValuesCacheLimit = 100

    private static let initialized: Void = {
        regexCache.countLimit = regexCacheLimit
        allowedValuesCache.countLimit = allowedValuesCacheLimit
    }()

    // MARK: - Public

    @objc public class func validateEvent(_ properties: [String: Any],
                                           specResponse: AvoEventSpecResponse) -> AvoValidationResult? {
        _ = initialized

        guard !specResponse.events.isEmpty else { return nil }

        let allEventIds = collectAllEventIds(specResponse)
        guard !allEventIds.isEmpty else { return nil }

        let mergedConstraints = collectConstraintsByPropertyName(specResponse)

        let result = AvoValidationResult()
        result.metadata = specResponse.metadata

        var propertyResults = [String: AvoPropertyValidationResult]()

        for (propName, value) in properties {
            guard let constraints = mergedConstraints[propName] else {
                propertyResults[propName] = AvoPropertyValidationResult()
                continue
            }

            if let propResult = validatePropertyConstraints(constraints, value: value,
                                                             allEventIds: allEventIds, depth: 0) {
                propertyResults[propName] = propResult
            } else {
                propertyResults[propName] = AvoPropertyValidationResult()
            }
        }

        result.propertyResults = propertyResults
        return result
    }

    // MARK: - ReDoS Protection

    @objc public class func isPatternPotentiallyDangerous(_ pattern: String) -> Bool {
        // Check for nested quantifiers pattern: (something+or*)+or*
        guard let detector = try? NSRegularExpression(pattern: "\\([^)]*[+*][^)]*\\)[+*]") else {
            return true // fail-safe: treat as dangerous if we can't compile the detector
        }
        let range = NSRange(location: 0, length: pattern.utf16.count)
        return detector.numberOfMatches(in: pattern, range: range) > 0
    }

    @objc public class func safeNumberOfMatches(with regex: NSRegularExpression,
                                                 in string: String,
                                                 timeout: TimeInterval) -> UInt {
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

    // MARK: - Collect Event IDs

    private class func collectAllEventIds(_ specResponse: AvoEventSpecResponse) -> [String] {
        var ids = [String]()
        for entry in specResponse.events {
            if !entry.baseEventId.isEmpty {
                ids.append(entry.baseEventId)
            }
            ids.append(contentsOf: entry.variantIds)
        }
        return ids
    }

    // MARK: - Merge Constraints

    private class func collectConstraintsByPropertyName(_ specResponse: AvoEventSpecResponse) -> [String: AvoPropertyConstraints] {
        var merged = [String: AvoPropertyConstraints]()

        for entry in specResponse.events {
            for (propName, constraint) in entry.props {
                if let existing = merged[propName] {
                    mergeConstraints(into: existing, from: constraint)
                } else {
                    merged[propName] = deepCopyConstraints(constraint)
                }
            }
        }

        return merged
    }

    private class func deepCopyConstraints(_ src: AvoPropertyConstraints) -> AvoPropertyConstraints {
        let copy = AvoPropertyConstraints()
        copy.type = src.type
        copy.required = src.required
        copy.isList = src.isList
        copy.pinnedValues = src.pinnedValues.map { deepCopyMapping($0) }
        copy.allowedValues = src.allowedValues.map { deepCopyMapping($0) }
        copy.regexPatterns = src.regexPatterns.map { deepCopyMapping($0) }
        copy.minMaxRanges = src.minMaxRanges.map { deepCopyMapping($0) }

        if let srcChildren = src.children {
            var childCopy = [String: AvoPropertyConstraints]()
            for (key, value) in srcChildren {
                childCopy[key] = deepCopyConstraints(value)
            }
            copy.children = childCopy
        }

        return copy
    }

    private class func deepCopyMapping(_ src: [String: [String]]) -> [String: [String]] {
        var result = [String: [String]]()
        for (key, value) in src {
            result[key] = Array(value)
        }
        return result
    }

    private class func mergeConstraints(into target: AvoPropertyConstraints, from source: AvoPropertyConstraints) {
        target.pinnedValues = mergeMapping(target.pinnedValues, with: source.pinnedValues)
        target.allowedValues = mergeMapping(target.allowedValues, with: source.allowedValues)
        target.regexPatterns = mergeMapping(target.regexPatterns, with: source.regexPatterns)
        target.minMaxRanges = mergeMapping(target.minMaxRanges, with: source.minMaxRanges)

        if let sourceChildren = source.children {
            if target.children == nil {
                var childCopy = [String: AvoPropertyConstraints]()
                for (key, value) in sourceChildren {
                    childCopy[key] = deepCopyConstraints(value)
                }
                target.children = childCopy
            } else {
                var mergedChildren = target.children!
                for (key, value) in sourceChildren {
                    if let existingChild = mergedChildren[key] {
                        mergeConstraints(into: existingChild, from: value)
                    } else {
                        mergedChildren[key] = deepCopyConstraints(value)
                    }
                }
                target.children = mergedChildren
            }
        }
    }

    private class func mergeMapping(_ target: [String: [String]]?,
                                     with source: [String: [String]]?) -> [String: [String]]? {
        guard let source = source else { return target }
        guard let target = target else { return deepCopyMapping(source) }

        var result = target
        for (key, sourceValues) in source {
            if var existing = result[key] {
                let existingSet = Set(existing)
                for id in sourceValues {
                    if !existingSet.contains(id) {
                        existing.append(id)
                    }
                }
                result[key] = existing
            } else {
                result[key] = Array(sourceValues)
            }
        }
        return result
    }

    // MARK: - Validate Property

    private class func validatePropertyConstraints(_ constraints: AvoPropertyConstraints,
                                                    value: Any?,
                                                    allEventIds: [String],
                                                    depth: Int) -> AvoPropertyValidationResult? {
        if let isList = constraints.isList, isList.boolValue {
            return validateListProperty(constraints, value: value, allEventIds: allEventIds, depth: depth)
        }

        if let children = constraints.children, !children.isEmpty {
            return validateObjectProperty(constraints, value: value, allEventIds: allEventIds, depth: depth)
        }

        return validatePrimitiveProperty(constraints, value: value, allEventIds: allEventIds)
    }

    // MARK: - Primitive Validation

    private class func validatePrimitiveProperty(_ constraints: AvoPropertyConstraints,
                                                  value: Any?,
                                                  allEventIds: [String]) -> AvoPropertyValidationResult? {
        if (value == nil || value is NSNull) && !constraints.required {
            return nil
        }

        var failedIds = Set<String>()

        if let pinnedValues = constraints.pinnedValues {
            checkPinnedValues(pinnedValues, value: value, failedIds: &failedIds)
        }

        if let allowedValues = constraints.allowedValues {
            checkAllowedValues(allowedValues, value: value, failedIds: &failedIds)
        }

        if let regexPatterns = constraints.regexPatterns {
            checkRegexPatterns(regexPatterns, value: value, failedIds: &failedIds)
        }

        if let minMaxRanges = constraints.minMaxRanges {
            checkMinMaxRanges(minMaxRanges, value: value, failedIds: &failedIds)
        }

        if failedIds.isEmpty {
            return nil
        }

        return buildValidationResult(failedIds, allEventIds: allEventIds)
    }

    // MARK: - Object Validation

    private class func validateObjectProperty(_ constraints: AvoPropertyConstraints,
                                               value: Any?,
                                               allEventIds: [String],
                                               depth: Int) -> AvoPropertyValidationResult? {
        if depth >= maxChildDepth { return nil }

        let selfResult = validatePrimitiveProperty(constraints, value: value, allEventIds: allEventIds)

        let objectValue = value as? [String: Any]
        var childResults: [String: AvoPropertyValidationResult]?

        if let children = constraints.children {
            for (childName, childConstraints) in children {
                let childValue = objectValue?[childName]

                if let childResult = validatePropertyConstraints(childConstraints, value: childValue,
                                                                  allEventIds: allEventIds, depth: depth + 1) {
                    if childResults == nil { childResults = [:] }
                    childResults![childName] = childResult
                }
            }
        }

        if selfResult == nil && childResults == nil { return nil }

        let result = selfResult ?? AvoPropertyValidationResult()
        if let childResults = childResults {
            result.children = childResults
        }
        return result
    }

    // MARK: - List Validation

    private class func validateListProperty(_ constraints: AvoPropertyConstraints,
                                             value: Any?,
                                             allEventIds: [String],
                                             depth: Int) -> AvoPropertyValidationResult? {
        if depth >= maxChildDepth { return nil }

        guard let listValue = value as? [Any], !listValue.isEmpty else {
            return validatePrimitiveProperty(constraints, value: value, allEventIds: allEventIds)
        }

        var allFailed = Set<String>()
        var allChildResults: [String: AvoPropertyValidationResult]?

        for item in listValue {
            let itemResult: AvoPropertyValidationResult?

            if let children = constraints.children, !children.isEmpty {
                itemResult = validateObjectProperty(constraints, value: item, allEventIds: allEventIds, depth: depth)
            } else {
                itemResult = validatePrimitiveProperty(constraints, value: item, allEventIds: allEventIds)
            }

            if let itemResult = itemResult {
                if let failedEventIds = itemResult.failedEventIds {
                    allFailed.formUnion(failedEventIds)
                }
                if let passedEventIds = itemResult.passedEventIds {
                    var passedAsInverted = Set(allEventIds)
                    passedAsInverted.subtract(passedEventIds)
                    allFailed.formUnion(passedAsInverted)
                }
                if let itemChildren = itemResult.children {
                    if allChildResults == nil { allChildResults = [:] }
                    for (key, newChild) in itemChildren {
                        if let existingChild = allChildResults![key] {
                            mergeValidationResults(existingChild, from: newChild, allEventIds: allEventIds)
                        } else {
                            allChildResults![key] = newChild
                        }
                    }
                }
            }
        }

        if allFailed.isEmpty && allChildResults == nil { return nil }

        let result: AvoPropertyValidationResult
        if !allFailed.isEmpty {
            result = buildValidationResult(allFailed, allEventIds: allEventIds)
        } else {
            result = AvoPropertyValidationResult()
        }

        if let allChildResults = allChildResults {
            result.children = allChildResults
        }

        return result
    }

    private class func mergeValidationResults(_ target: AvoPropertyValidationResult,
                                               from source: AvoPropertyValidationResult,
                                               allEventIds: [String]) {
        var targetFailed = Set<String>()

        if let failedIds = target.failedEventIds {
            targetFailed.formUnion(failedIds)
        } else if let passedIds = target.passedEventIds {
            targetFailed.formUnion(allEventIds)
            targetFailed.subtract(passedIds)
        }

        if let failedIds = source.failedEventIds {
            targetFailed.formUnion(failedIds)
        } else if let passedIds = source.passedEventIds {
            var sourceFailed = Set(allEventIds)
            sourceFailed.subtract(passedIds)
            targetFailed.formUnion(sourceFailed)
        }

        if !targetFailed.isEmpty {
            let merged = buildValidationResult(targetFailed, allEventIds: allEventIds)
            target.failedEventIds = merged.failedEventIds
            target.passedEventIds = merged.passedEventIds
        }

        if let sourceChildren = source.children {
            var mergedChildren = target.children ?? [:]
            for (key, newChild) in sourceChildren {
                if let existingChild = mergedChildren[key] {
                    mergeValidationResults(existingChild, from: newChild, allEventIds: allEventIds)
                } else {
                    mergedChildren[key] = newChild
                }
            }
            target.children = mergedChildren
        }
    }

    // MARK: - Constraint Checks

    private class func checkPinnedValues(_ pinnedValues: [String: [String]],
                                          value: Any?,
                                          failedIds: inout Set<String>) {
        let stringValue = convertValueToString(value)

        for (pinnedValue, eventIds) in pinnedValues {
            if pinnedValue != stringValue {
                failedIds.formUnion(eventIds)
            }
        }
    }

    private class func checkAllowedValues(_ allowedValues: [String: [String]],
                                            value: Any?,
                                            failedIds: inout Set<String>) {
        let stringValue = convertValueToString(value)

        for (allowedJsonArray, eventIds) in allowedValues {
            guard let allowed = getOrParseAllowedValues(allowedJsonArray) else { continue }

            var found = false
            for allowedItem in allowed {
                if allowedItem == stringValue {
                    found = true
                    break
                }
            }

            if !found {
                failedIds.formUnion(eventIds)
            }
        }
    }

    private class func checkRegexPatterns(_ regexPatterns: [String: [String]],
                                           value: Any?,
                                           failedIds: inout Set<String>) {
        let stringValue = convertValueToString(value)
        guard let stringValue = stringValue else {
            for (_, eventIds) in regexPatterns {
                failedIds.formUnion(eventIds)
            }
            return
        }

        for (pattern, eventIds) in regexPatterns {
            // ReDoS protection: skip dangerous patterns
            if isPatternPotentiallyDangerous(pattern) {
                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Skipping potentially dangerous regex pattern: %@", pattern)
                }
                continue
            }

            guard let regex = getOrCompileRegex(pattern) else { continue }

            let matches = safeNumberOfMatches(with: regex, in: stringValue, timeout: 2.0)
            if matches == UInt(NSNotFound) {
                // Timed out - fail-open, skip this constraint
                continue
            }
            if matches == 0 {
                failedIds.formUnion(eventIds)
            }
        }
    }

    private class func checkMinMaxRanges(_ minMaxRanges: [String: [String]],
                                          value: Any?,
                                          failedIds: inout Set<String>) {
        guard let number = value as? NSNumber else {
            for (_, eventIds) in minMaxRanges {
                failedIds.formUnion(eventIds)
            }
            return
        }

        let numericValue = number.doubleValue

        for (range, eventIds) in minMaxRanges {
            let parts = range.components(separatedBy: ",")
            guard parts.count == 2 else { continue }

            let minStr = parts[0].trimmingCharacters(in: .whitespaces)
            let maxStr = parts[1].trimmingCharacters(in: .whitespaces)

            var failed = false

            if !minStr.isEmpty {
                if let minVal = Double(minStr), numericValue < minVal {
                    failed = true
                }
            }

            if !failed && !maxStr.isEmpty {
                if let maxVal = Double(maxStr), numericValue > maxVal {
                    failed = true
                }
            }

            if failed {
                failedIds.formUnion(eventIds)
            }
        }
    }

    // MARK: - Helpers

    private class func convertValueToString(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }

        if let str = value as? String { return str }

        if let num = value as? NSNumber {
            if CFGetTypeID(num as CFTypeRef) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        }

        return "\(value)"
    }

    private class func buildValidationResult(_ failedIds: Set<String>,
                                              allEventIds: [String]) -> AvoPropertyValidationResult {
        let result = AvoPropertyValidationResult()

        let passedIds = Set(allEventIds).subtracting(failedIds)

        if failedIds.isEmpty && passedIds.isEmpty {
            return result
        }

        if passedIds.count < failedIds.count && !passedIds.isEmpty {
            result.passedEventIds = Array(passedIds)
        } else if !failedIds.isEmpty {
            result.failedEventIds = Array(failedIds)
        }

        return result
    }

    private class func getOrCompileRegex(_ pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = regexCache.object(forKey: key) {
            return cached
        }

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Failed to compile regex '%@'", pattern)
            }
            return nil
        }

        regexCache.setObject(regex, forKey: key)
        return regex
    }

    private class func getOrParseAllowedValues(_ jsonArrayString: String) -> [String]? {
        let key = jsonArrayString as NSString
        if let cached = allowedValuesCache.object(forKey: key) as? [String] {
            return cached
        }

        guard let data = jsonArrayString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }

        let result = parsed.map { "\($0)" }
        allowedValuesCache.setObject(result as NSArray, forKey: key)
        return result
    }
}
