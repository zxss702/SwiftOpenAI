import XCTest
import SwiftParser
import SwiftSyntax

final class EnumRawValueTest: XCTestCase {
    func testExtractRawValue() {
        let source = """
        enum ManagementAgentType: String {
            case critic = "批判家"
            case visionary
        }
        """

        let tree = Parser.parse(source: source)
        if let enumDecl = tree.statements.first?.item.as(EnumDeclSyntax.self) {
            for member in enumDecl.memberBlock.members {
                if let enumCase = member.decl.as(EnumCaseDeclSyntax.self),
                   let element = enumCase.elements.first {
                    print("CASE NAME:", element.name.text)
                    if let rawValue = element.rawValue {
                        if let strExpr = rawValue.value.as(StringLiteralExprSyntax.self) {
                            if let segment = strExpr.segments.first?.as(StringSegmentSyntax.self) {
                                print("EXTRACTED:", segment.content.text)
                            }
                        }
                    }
                }
            }
        }
    }
}
