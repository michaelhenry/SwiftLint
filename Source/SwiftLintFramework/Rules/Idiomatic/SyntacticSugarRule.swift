import Foundation
import SourceKittenFramework
import SwiftSyntax

private let warnSyntaxParserFailureOnceImpl: Void = {
    queuedPrintError("The syntactic_sugar rule is disabled because the Swift Syntax tree could not be parsed")
}()

private func warnSyntaxParserFailureOnce() {
    _ = warnSyntaxParserFailureOnceImpl
}

public struct SyntacticSugarRule: CorrectableRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.warning)

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
            Example("unsafeBitCast(someType, to: Swift.Array<T>.self)"),
            Example("let a = Swift.Optional<String?>.none"),
            Example("let x = Array<String>.array(of: object)"),
            Example("let x = Swift.Array<String>.array(of: object)"),

            Example("type is Optional<String>.Type"),
            Example("let x: Foo.Optional<String>")
        ],
        triggeringExamples: [
            Example("let x: ↓Array<String>"),
            Example("let x: ↓Dictionary<Int, String>"),
            Example("let x: ↓Optional<Int>"),
            Example("let x: ↓ImplicitlyUnwrappedOptional<Int>"),
            Example("let x: ↓Swift.Array<String>"),

            Example("func x(a: ↓Array<Int>, b: Int) -> [Int: Any]"),
            Example("func x(a: ↓Swift.Array<Int>, b: Int) -> [Int: Any]"),

            Example("func x(a: [Int], b: Int) -> ↓Dictionary<Int, String>"),
            Example("let x = y as? ↓Array<[String: Any]>"),
            Example("let x = Box<Array<T>>()"),
            Example("func x() -> Box<↓Array<T>>"),
            Example("func x() -> ↓Dictionary<String, Any>?"),

            Example("typealias Document = ↓Dictionary<String, T?>"),
            Example("func x(_ y: inout ↓Array<T>)")
        ],
        corrections: [
            Example("let x: Array<String>"): Example("let x: [String]")
//            Example("let x: Array< String >"): Example("let x: [String]"),
//            Example("let x: Dictionary<Int, String>"): Example("let x: [Int: String]"),
//            Example("let x: Dictionary<Int , String>"): Example("let x: [Int : String]"),
//            Example("let x: Optional<Int>"): Example("let x: Int?"),
//            Example("let x: Optional< Int >"): Example("let x: Int?"),
//            Example("let x: ImplicitlyUnwrappedOptional<Int>"): Example("let x: Int!"),
//            Example("let x: ImplicitlyUnwrappedOptional< Int >"): Example("let x: Int!"),
//            Example("func x(a: Array<Int>, b: Int) -> [Int: Any]"): Example("func x(a: [Int], b: Int) -> [Int: Any]"),
//            Example("func x(a: [Int], b: Int) -> Dictionary<Int, String>"):
//                Example("func x(a: [Int], b: Int) -> [Int: String]"),
//            Example("let x = Array<String>.array(of: object)"): Example("let x = [String].array(of: object)"),
//            Example("let x: Swift.Optional<String>"): Example("let x: String?"),
//            Example("let x:Dictionary<String, Dictionary<Int, Int>>"): Example("let x:[String: [Int: Int]]"),
//            Example("let x:Dictionary<Dictionary<Int, Int>, String>"): Example("let x:[[Int: Int]: String]"),
//            Example("""
//                    enum Box<T> {}
//                    let x:Dictionary<Box<String>, Box<Bool>>
//                    """):
//                Example("""
//                        enum Box<T> {}
//                        let x:[Box<String>: Box<Bool>]
//                        """)
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        guard let tree = file.syntaxTree else {
            warnSyntaxParserFailureOnce()
            return []
        }
        let visitor = SyntacticSugarRuleVisitor()
        visitor.walk(tree)
        return visitor.violations.map { violation in
            return StyleViolation(ruleDescription: Self.description,
                                  severity: configuration.severity,
                                  location: Location(file: file, byteOffset: ByteCount(violation.position.utf8Offset)),
                                  reason: message(for: violation.type))
        }
    }

    public func correct(file: SwiftLintFile) -> [Correction] {
        guard let tree = file.syntaxTree else {
            warnSyntaxParserFailureOnce()
            return []
        }
        let visitor = SyntacticSugarRuleVisitor()
        visitor.walk(tree)

        let stringView = file.stringView
        var correctedContents = file.contents

        var corrections: [Correction] = []

        let soredViolations = visitor.violations.sorted(by: { $0.correction.type > $1.correction.type })
        soredViolations.forEach { violation in
            let correction = violation.correction

            guard let violationNSRange = stringView.NSRange(start: correction.left, end: correction.rightEnd),
                  file.ruleEnabled(violatingRange: violationNSRange, for: self) != nil else { return }

            guard let rightRange = stringView.NSRange(start: correction.rightStart, end: correction.rightEnd),
                  let leftRange = stringView.NSRange(start: correction.type, end: correction.leftEnd) else {
                      return
                  }
            correctedContents = correctedContents.replacingCharacters(in: rightRange, with: "]")
            correctedContents = correctedContents.replacingCharacters(in: leftRange, with: "[")

            corrections.append(Correction(ruleDescription: Self.description, location:
                                            Location(file: file, byteOffset: ByteCount(correction.left.utf8Offset))))
        }

        file.write(correctedContents)

        return corrections
    }

    private func message(for originalType: String) -> String {
        let typeString: String
        let sugaredType: String

        switch originalType {
        case "Optional":
            typeString = "Optional<Int>"
            sugaredType = "Int?"
        case "ImplicitlyUnwrappedOptional":
            typeString = "ImplicitlyUnwrappedOptional<Int>"
            sugaredType = "Int!"
        case "Array":
            typeString = "Array<Int>"
            sugaredType = "[Int]"
        case "Dictionary":
            typeString = "Dictionary<String, Int>"
            sugaredType = "[String: Int]"
        default:
            return Self.description.description
        }

        return "Shorthand syntactic sugar should be used, i.e. \(sugaredType) instead of \(typeString)."
    }
}

private struct SyntacticSugarRuleViolation {
    struct Correction {
        let type: AbsolutePosition
        let left: AbsolutePosition
        let right: AbsolutePosition
        let correction: CorrectionType

        var rightStart: AbsolutePosition { right }
        var rightEnd: AbsolutePosition { AbsolutePosition(utf8Offset: right.utf8Offset + 1) }

        var leftStart: AbsolutePosition { left }
        var leftEnd: AbsolutePosition { AbsolutePosition(utf8Offset: left.utf8Offset + 1) }
    }
    enum CorrectionType {
        case optional
        case dictionary
        case array
    }

    //
    let position: AbsolutePosition
    let type: String

    let correction: Correction
}

private final class SyntacticSugarRuleVisitor: SyntaxAnyVisitor {
    private let types = ["Optional", "ImplicitlyUnwrappedOptional", "Array", "Dictionary"]

    var violations: [SyntacticSugarRuleViolation] = []

    override func visitPost(_ node: TypeAnnotationSyntax) {
        // let x: ↓Swift.Optional<String>
        // let x: ↓Optional<String>
        if let violation = violation(in: node.type) {
            violations.append(violation)
        }
    }

    override func visitPost(_ node: FunctionParameterSyntax) {
        // func x(a: ↓Array<Int>, b: Int) -> [Int: Any]
        if let violation = violation(in: node.type) {
            violations.append(violation)
        }
    }

    override func visitPost(_ node: ReturnClauseSyntax) {
        // func x(a: [Int], b: Int) -> ↓Dictionary<Int, String>
        if let violation = violation(in: node.returnType) {
            violations.append(violation)
        }
    }

    override func visitPost(_ node: AsExprSyntax) {
        // json["recommendations"] as? ↓Array<[String: Any]>
        if let violation = violation(in: node.typeName) {
            violations.append(violation)
        }
    }

    override func visitPost(_ node: TypeInitializerClauseSyntax) {
        // typealias Document = ↓Dictionary<String, AnyBSON?>
        if let violation = violation(in: node.value) {
            violations.append(violation)
        }
    }

    override func visitPost(_ node: AttributedTypeSyntax) {
        // func x(_ y: inout ↓Array<T>)
        if let violation = violation(in: node.baseType) {
            violations.append(violation)
        }
    }

    override func visitPost(_ node: SpecializeExprSyntax) {
        // let x = ↓Array<String>.array(of: object)
        let tokens = Array(node.expression.tokens)
        guard let firstToken = tokens.first else { return }

        // Remove Swift. module prefix if needed
        var tokensText = tokens.map { $0.text }.joined()
        if tokensText.starts(with: "Swift.") {
            tokensText.removeFirst("Swift.".count)
        }

        if types.contains(tokensText) {
            // Skip cases when method is called. like Optional<T>.none, Optional<T>.self
            if node.parent?.as(MemberAccessExprSyntax.self) != nil {
                return
            }

            violations.append(SyntacticSugarRuleViolation(
                position: firstToken.positionAfterSkippingLeadingTrivia,
                type: tokensText,
                correction: .init(type: .init(utf8Offset: 0),
                                  left: .init(utf8Offset: 0),
                                  right: .init(utf8Offset: 0),
                                  correction: .optional)
            ))
            return
        }

        // If there's no type let's check all inner generics like in case of Box<Array<T>>
        node.genericArgumentClause.arguments
            .compactMap { violation(in: $0.argumentType) }
            .first
            .map { violations.append($0) }
    }

    private func violation(in typeSyntax: TypeSyntax?) -> SyntacticSugarRuleViolation? {
        if let optionalType = typeSyntax?.as(OptionalTypeSyntax.self) {
            return violation(in: optionalType.wrappedType)
        }

        if let simpleType = typeSyntax?.as(SimpleTypeIdentifierSyntax.self) {
            if types.contains(simpleType.name.text) {
                guard let generic = simpleType.genericArgumentClause else { return nil }
                return SyntacticSugarRuleViolation(
                    position: simpleType.positionAfterSkippingLeadingTrivia,
                    type: simpleType.name.text,
                    correction: .init(type: simpleType.position,
                                      left: generic.leftAngleBracket.position,
                                      right: generic.rightAngleBracket.position,
                                      correction: .array)
                )
            }

            // If there's no type let's check all inner generics like in case of Box<Array<T>>
            guard let genericArguments = simpleType.genericArgumentClause else { return nil }
            let innerTypes = genericArguments.arguments.compactMap { violation(in: $0.argumentType) }
            return innerTypes.first
        }

        // Base class is "Swift" for cases like "Swift.Array"
        if let memberType = typeSyntax?.as(MemberTypeIdentifierSyntax.self),
           let baseType = memberType.baseType.as(SimpleTypeIdentifierSyntax.self),
           baseType.name.text == "Swift" {
            guard types.contains(memberType.name.text) else { return nil }

            guard memberType.genericArgumentClause != nil else { return nil }
            return SyntacticSugarRuleViolation(
                position: memberType.positionAfterSkippingLeadingTrivia,
                type: memberType.name.text,
                correction: .init(type: .init(utf8Offset: 0),
                                  left: .init(utf8Offset: 0),
                                  right: .init(utf8Offset: 0),
                                  correction: .optional)
            )
        }
        return nil
    }

    var level: Int = 0

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        level += 1
        return super.visitAny(node)
    }

    var levelS: String {
        Array(repeating: "  ", count: level).joined()
    }
    override func visitAnyPost(_ node: Syntax) {
        level -= 1
    }
}

private extension StringView {
    func NSRange(start: AbsolutePosition, end: AbsolutePosition) -> NSRange? {
        return NSRange(start: start, length: end.utf8Offset - start.utf8Offset)
    }

    private func NSRange(start: AbsolutePosition, length: Int) -> NSRange? {
        let byteRange = ByteRange(location: ByteCount(start.utf8Offset), length: ByteCount(length))
        return byteRangeToNSRange(byteRange)
    }
}

private extension String {
    func replacingCharacters(in range: NSRange, with replacement: String) -> String {
        return (self.bridge()).replacingCharacters(in: range, with: replacement)
    }
}
