import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct SwiftOpenAIMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SYToolMacro.self,
        SYToolArgsMacro.self,
        AIModelSchemaMacro.self
    ]
}
