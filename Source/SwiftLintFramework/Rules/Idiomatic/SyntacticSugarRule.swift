import Foundation
import SourceKittenFramework

public struct SyntacticSugarRule: SubstitutionCorrectableRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.warning)

    private var pattern: String {
        let types = ["Swift.Optional", "Swift.ImplicitlyUnwrappedOptional", "Swift.Array", "Swift.Dictionary",
                     "Optional", "ImplicitlyUnwrappedOptional", "Array", "Dictionary"]
        let negativeLookBehind = "(?:(?<!\\.))"
        return negativeLookBehind + "\\b(" + types.joined(separator: "|") + ")\\s*"
        // Open generic
        + "(<\\s*)"

        // Everything but new generic
        + "[^<]*?"

        // Optional inner generic
        + "(?:<[^<]*?>)?"

        // Everything but new generic
        + "[^<]*?"

        // 2nd Optional inner generic (as value type in dictionary)
        + "(?:<[^<]*?>)?"

        // Everything but new generic
        + "[^<]*?"

        // Closed generic
        + "(\\s*>)"
    }

    public init() {}

    public static let description = RuleDescription(
        identifier: "syntactic_sugar",
        name: "Syntactic Sugar",
        description: "Shorthand syntactic sugar should be used, i.e. [Int] instead of Array<Int>.",
        kind: .idiomatic,
        nonTriggeringExamples: [
            Example("let x: [Int]"),
            Example("let x: [Int: String]"),
            Example("let x: Int?"),
            Example("func x(a: [Int], b: Int) -> [Int: Any]"),
            Example("let x: Int!"),
            Example("""
            extension Array {
              func x() { }
            }
            """),
            Example("""
            extension Dictionary {
              func x() { }
            }
            """),
            Example("let x: CustomArray<String>"),
            Example("var currentIndex: Array<OnboardingPage>.Index?"),
            Example("func x(a: [Int], b: Int) -> Array<Int>.Index"),
            Example("unsafeBitCast(nonOptionalT, to: Optional<T>.self)"),
            Example("type is Optional<String>.Type"),
            Example("let x: Foo.Optional<String>")
        ],
        triggeringExamples: [
            Example("let x: ↓Array<String>"),
            Example("let x: ↓Dictionary<Int, String>"),
            Example("let x: ↓Optional<Int>"),
            Example("let x: ↓ImplicitlyUnwrappedOptional<Int>"),
            Example("func x(a: ↓Array<Int>, b: Int) -> [Int: Any]"),
            Example("func x(a: [Int], b: Int) -> ↓Dictionary<Int, String>"),
            Example("func x(a: ↓Array<Int>, b: Int) -> ↓Dictionary<Int, String>"),
            Example("let x = ↓Array<String>.array(of: object)"),
            Example("let x: ↓Swift.Optional<String>")
        ],
        corrections: [
            Example("let x: Array<String>"): Example("let x: [String]"),
            Example("let x: Array< String >"): Example("let x: [String]"),
            Example("let x: Dictionary<Int, String>"): Example("let x: [Int: String]"),
            Example("let x: Dictionary<Int , String>"): Example("let x: [Int : String]"),
            Example("let x: Optional<Int>"): Example("let x: Int?"),
            Example("let x: Optional< Int >"): Example("let x: Int?"),
            Example("let x: ImplicitlyUnwrappedOptional<Int>"): Example("let x: Int!"),
            Example("let x: ImplicitlyUnwrappedOptional< Int >"): Example("let x: Int!"),
            Example("func x(a: Array<Int>, b: Int) -> [Int: Any]"): Example("func x(a: [Int], b: Int) -> [Int: Any]"),
            Example("func x(a: [Int], b: Int) -> Dictionary<Int, String>"):
                Example("func x(a: [Int], b: Int) -> [Int: String]"),
            Example("let x = Array<String>.array(of: object)"): Example("let x = [String].array(of: object)"),
            Example("let x: Swift.Optional<String>"): Example("let x: String?"),
            Example("let x:Dictionary<String, Dictionary<Int, Int>>"): Example("let x:[String: [Int: Int]]"),
            Example("let x:Dictionary<Dictionary<Int, Int>, String>"): Example("let x:[[Int: Int]: String]"),
            Example("""
                    enum Box<T> {}
                    let x:Dictionary<Box<String>, Box<Bool>>
                    """):
                Example("""
                        enum Box<T> {}
                        let x:[Box<String>: Box<Bool>]
                        """)
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        let contents = file.stringView
        return violationResults(in: file).map {
            let typeString = contents.substring(with: $0.range(at: 1))
            return StyleViolation(ruleDescription: Self.description,
                                  severity: configuration.severity,
                                  location: Location(file: file, characterOffset: $0.range.location),
                                  reason: message(for: typeString))
        }
    }

    public func violationRanges(in file: SwiftLintFile) -> [NSRange] {
        return violationResults(in: file).map { $0.range }
    }

    public func substitution(for violationRange: NSRange, in file: SwiftLintFile) -> (NSRange, String)? {
        let contents = file.stringView
        let declaration = contents.substring(with: violationRange)
        let substitutionResult = substitute(declaration)
        return (violationRange, substitutionResult)
    }

    private func substitute(_ declaration: String) -> String {
        let originalRange = NSRange(location: 0, length: declaration.count)
        guard let match = regex(pattern).firstMatch(in: declaration, options: [], range: originalRange) else {
            return declaration
        }

        let typeRange = match.range(at: 1)
        let openBracketRange = match.range(at: 2)
        let closedBracketRange = match.range(at: 3)

        // replace found type
        let substitutionResult: String
        let containerType = declaration.bridge().substring(with: typeRange)
        let prefix = declaration.bridge().substring(to: typeRange.lowerBound)
        switch containerType {
        case "Optional", "Swift.Optional":
            let genericType = declaration.bridge()
                .replacingCharacters(in: closedBracketRange, with: "").bridge()
                .replacingCharacters(in: openBracketRange, with: "")
                .substring(from: typeRange.upperBound)
            substitutionResult = "\(prefix)\(genericType)?"

        case "ImplicitlyUnwrappedOptional", "Swift.ImplicitlyUnwrappedOptional":
            let genericType = declaration.bridge()
                .replacingCharacters(in: closedBracketRange, with: "").bridge()
                .replacingCharacters(in: openBracketRange, with: "")
                .substring(from: typeRange.upperBound)

            substitutionResult = "\(prefix)\(genericType)!"
        case "Array", "Swift.Array":
            let genericType = declaration.bridge()
                .replacingCharacters(in: closedBracketRange, with: "]").bridge()
                .replacingCharacters(in: openBracketRange, with: "[")
                .substring(from: typeRange.upperBound)

            substitutionResult = "\(prefix)\(genericType)"
        case "Dictionary", "Swift.Dictionary":
            let genericType = declaration.bridge()
                .replacingCharacters(in: closedBracketRange, with: "]").bridge()
                .replacingCharacters(in: openBracketRange, with: "[")
                .replacingOccurrences(of: ",", with: ":")
                .substring(from: typeRange.upperBound)

            substitutionResult = "\(prefix)\(genericType)"
        default:
            substitutionResult = declaration
        }

        let finalResult = substitute(substitutionResult)
        return finalResult
    }

    private func violationResults(in file: SwiftLintFile) -> [NSTextCheckingResult] {
        let excludingKinds = SyntaxKind.commentAndStringKinds
        let contents = file.stringView
        return regex(pattern).matches(in: contents).compactMap { result in
            let range = result.range
            guard let byteRange = contents.NSRangeToByteRange(start: range.location, length: range.length) else {
                return nil
            }

            let kinds = file.syntaxMap.kinds(inByteRange: byteRange)
            guard excludingKinds.isDisjoint(with: kinds),
                isValidViolation(range: range, file: file) else {
                    return nil
            }

            return result
        }
    }

    private func isValidViolation(range: NSRange, file: SwiftLintFile) -> Bool {
        let contents = file.stringView

        // avoid triggering when referring to an associatedtype
        let start = range.location + range.length
        let restOfFileRange = NSRange(location: start, length: contents.nsString.length - start)
        if regex("\\s*\\.").firstMatch(in: file.contents, options: [],
                                       range: restOfFileRange)?.range.location == start {
            guard let byteOffset = contents.NSRangeToByteRange(start: range.location,
                                                               length: range.length)?.location else {
                return false
            }

            let kinds = file.structureDictionary.structures(forByteOffset: byteOffset).compactMap { $0.expressionKind }
            guard kinds.contains(.call) else {
                return false
            }

            if let (range, kinds) = file.match(pattern: "\\s*\\.(?:self|Type)", range: restOfFileRange).first,
                range.location == start, kinds == [.keyword] || kinds == [.identifier] {
                return false
            }
        }

        return true
    }

    private func message(for originalType: String) -> String {
        let typeString: String
        let sugaredType: String

        switch originalType {
        case "Optional", "Swift.Optional":
            typeString = "Optional<Int>"
            sugaredType = "Int?"
        case "ImplicitlyUnwrappedOptional", "Swift.ImplicitlyUnwrappedOptional":
            typeString = "ImplicitlyUnwrappedOptional<Int>"
            sugaredType = "Int!"
        case "Array", "Swift.Array":
            typeString = "Array<Int>"
            sugaredType = "[Int]"
        case "Dictionary", "Swift.Dictionary":
            typeString = "Dictionary<String, Int>"
            sugaredType = "[String: Int]"
        default:
            return Self.description.description
        }

        return "Shorthand syntactic sugar should be used, i.e. \(sugaredType) instead of \(typeString)."
    }
}
