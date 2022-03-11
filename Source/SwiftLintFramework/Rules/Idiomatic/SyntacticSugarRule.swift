import Foundation
import SourceKittenFramework
import SwiftSyntax

private let warnSyntaxParserFailureOnceImpl: Void = {
    queuedPrintError("The syntactic_sugar rule is disabled because the Swift Syntax tree could not be parsed")
}()

private func warnSyntaxParserFailureOnce() {
    _ = warnSyntaxParserFailureOnceImpl
}

public struct SyntacticSugarRule: SubstitutionCorrectableRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.warning)

    private let types = ["Optional", "ImplicitlyUnwrappedOptional", "Array", "Dictionary"]

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
            Example("let x = ↓Array<String>.array(of: object)"),
            Example("let x = ↓Swift.Array<String>.array(of: object)")
        ],
        corrections: [:
//            Example("let x: Array<String>"): Example("let x: [String]"),
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
        return visitor.positions.map { position in
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severity,
                           location: Location(file: file, byteOffset: ByteCount(position.utf8Offset)))
        }
    }

    public func violationRanges(in file: SwiftLintFile) -> [NSRange] {
        return []
    }

    private func isValidViolation(range: NSRange, file: SwiftLintFile) -> Bool {
        return true
    }

    public func substitution(for violationRange: NSRange, in file: SwiftLintFile) -> (NSRange, String)? {
        return nil
    }
}

private final class SyntacticSugarRuleVisitor: SyntaxAnyVisitor {
    private let types = ["Swift.Optional", "Swift.ImplicitlyUnwrappedOptional", "Swift.Array", "Swift.Dictionary",
                         "Optional", "ImplicitlyUnwrappedOptional", "Array", "Dictionary"]

    var positions: [AbsolutePosition] = []

    override func visitPost(_ node: TypeAnnotationSyntax) {
        // let x: ↓Swift.Optional<String>
        // let x: ↓Optional<String>
        if let type = isValidTypeSyntax(node.type) {
            positions.append(type.positionAfterSkippingLeadingTrivia)
        }
    }

    override func visitPost(_ node: FunctionParameterSyntax) {
        // func x(a: ↓Array<Int>, b: Int) -> [Int: Any]
        if let type = isValidTypeSyntax(node.type) {
            positions.append(type.positionAfterSkippingLeadingTrivia)
        }
    }

    override func visitPost(_ node: ReturnClauseSyntax) {
        // func x(a: [Int], b: Int) -> ↓Dictionary<Int, String>
        if let type = isValidTypeSyntax(node.returnType) {
            positions.append(type.positionAfterSkippingLeadingTrivia)
        }
    }

    override func visitPost(_ node: SpecializeExprSyntax) {
        // let x = ↓Array<String>.array(of: object)
        let tokens = Array(node.expression.tokens)
        guard let firstToken = tokens.first else { return }

        // Remove Swift. module prefix if needed
        var tokensText = tokens.map { $0.text }.joined( )
        if tokensText.starts(with: "Swift.") {
            tokensText.removeFirst("Swift.".count)
        }

        guard types.contains(tokensText) else { return }

        // Skip case when '.self' is used Optional<T>.self)
        if let parent = node.parent?.as(MemberAccessExprSyntax.self) {
            if parent.name.text == "self" {
                return
            }
        }

        positions.append(firstToken.positionAfterSkippingLeadingTrivia)
    }

    private func isValidTypeSyntax(_ typeSyntax: TypeSyntax?) -> TypeSyntaxProtocol? {
        if let simpleType = typeSyntax?.as(SimpleTypeIdentifierSyntax.self) {
            guard types.contains(simpleType.name.text) else { return nil }
            guard simpleType.genericArgumentClause != nil else { return nil }
            return simpleType
        }

        // Base class is "Swift" for cases like "Swift.Array"
        if let memberType = typeSyntax?.as(MemberTypeIdentifierSyntax.self),
           let baseType = memberType.baseType.as(SimpleTypeIdentifierSyntax.self),
           baseType.name.text == "Swift" {
            guard types.contains(memberType.name.text) else { return nil }

            guard memberType.genericArgumentClause != nil else { return nil }
            return memberType
        }
        return nil
    }

    var level: Int = 0

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
//        print("\(levelS) --> \(node.syntaxNodeType) : \(node)")
        level += 1
        return super.visitAny(node)
    }

    var levelS: String {
        Array(repeating: "  ", count: level).joined()
    }
    override func visitAnyPost(_ node: Syntax) {
        level -= 1
//        print("\(levelS) <-- \(node.syntaxNodeType) : \(node)")
    }
}
