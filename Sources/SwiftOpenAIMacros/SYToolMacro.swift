import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

enum SYToolMacroDiagnostic: String, DiagnosticMessage {
    case requiresStruct = "@SYTool can only be applied to a struct"
    case missingNameProperty = "@SYTool requires a 'name' property of type String"
    case missingDescriptionProperty = "@SYTool requires a 'description' property of type String"
    case missingParametersProperty = "@SYTool requires a 'parameters' property with @SYToolArgs"

    var message: String { rawValue }
    var diagnosticID: MessageID {
        MessageID(domain: "SwiftOpenAIMacros", id: "SYToolMacro.\(self)")
    }
    var severity: DiagnosticSeverity { .error }
}

public struct SYToolMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: node, message: SYToolMacroDiagnostic.requiresStruct))
            return []
        }
        
        // 验证必需的属性
        var hasName = false
        var hasDescription = false
        var parametersTypeName: String?
        
        for member in structDecl.memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = variableDecl.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                
                switch propertyName {
                case "name":
                    hasName = true
                case "description":
                    hasDescription = true
                case "parameters":
                    // 支持的参数定义形式：
                    // let parameters = TypeName.self
                    
                    // 仅支持 TypeName.self 形式
                    if let initializer = binding.initializer,
                       let memberAccess = initializer.value.as(MemberAccessExprSyntax.self),
                       memberAccess.declName.baseName.text == "self",
                       let baseExpr = memberAccess.base {
                        parametersTypeName = baseExpr.trimmedDescription
                    }
                default:
                    break
                }
            }
        }
        
        if !hasName {
            context.diagnose(
                Diagnostic(node: node, message: SYToolMacroDiagnostic.missingNameProperty))
        }
        
        if !hasDescription {
            context.diagnose(
                Diagnostic(node: node, message: SYToolMacroDiagnostic.missingDescriptionProperty))
        }
        
        // parameters 是可选的，工具可以没有参数
        
        guard hasName && hasDescription else {
            return []
        }
        
        // 生成ChatCompletionToolParam转换方法
        let extensionDecl = try ExtensionDeclSyntax("extension \(type.trimmed): OpenAIToolConvertible") {
            """
            \(structDecl.modifiers)var asChatCompletionTool: SwiftOpenAI.ChatQuery.ChatCompletionToolParam {
                let paramsDict: [String: Any]
                
                \(raw: parametersTypeName != nil ? 
                    "paramsDict = \(parametersTypeName!).parametersSchema" :
                    """
                    // 无参数时使用空的对象schema
                    paramsDict = [
                        "type": "object",
                        "properties": [:],
                        "required": [],
                        "additionalProperties": false
                    ]
                    """
                )
                
                // 直接传递字典对象，而不是JSON字符串
                return SwiftOpenAI.ChatQuery.ChatCompletionToolParam(
                    type: "function",
                    function: SwiftOpenAI.ChatQuery.ChatCompletionToolParam.Function(
                        name: self.name,
                        description: self.description,
                        parameters: paramsDict  // 使用字典而不是字符串
                    )
                )
            }
            """
        }
        
        return [extensionDecl]
    }
}

// MARK: - SYToolArgs Macro
enum SYToolArgsMacroDiagnostic: String, DiagnosticMessage {
    case requiresStruct = "@SYToolArgs can only be applied to a struct"

    var message: String { rawValue }
    var diagnosticID: MessageID {
        MessageID(domain: "SwiftOpenAIMacros", id: "SYToolArgsMacro.\(self)")
    }
    var severity: DiagnosticSeverity { .error }
}

public struct SYToolArgsMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: node, message: SYToolArgsMacroDiagnostic.requiresStruct))
            return []
        }
        
        // 生成JSON Schema
        var properties: [String: String] = [:]
        var required: [String] = []
        
        for member in structDecl.memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = variableDecl.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                let isOptional = binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) == true
                
                if !isOptional {
                    required.append(propertyName)
                }
                
                let propertyType = extractPropertyType(from: binding.typeAnnotation?.type)
                properties[propertyName] = propertyType
            }
        }
        
        // 构建properties字典字符串
        let propertiesString = properties.map { key, value in
            "\"\(key)\": [\"type\": \"\(value)\"]"
        }.joined(separator: ", ")
        
        let requiredString = required.map { "\"\($0)\"" }.joined(separator: ", ")
        
        let extensionDecl = try ExtensionDeclSyntax("extension \(type.trimmed): SYToolArgsConvertible") {
            """
            \(structDecl.modifiers)static var parametersSchema: [String: Any] {
                return [
                    "type": "object",
                    "properties": [\(raw: propertiesString)],
                    "required": [\(raw: requiredString)],
                    "additionalProperties": false
                ]
            }
            """
        }
        
        return [extensionDecl]
    }
    
    private static func extractPropertyType(from type: TypeSyntax?) -> String {
        guard let type = type else { return "string" }
        
        let typeText = type.trimmedDescription
        
        // 处理可选类型
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return extractPropertyType(from: optionalType.wrappedType)
        }
        
        // 基本类型映射
        switch typeText.lowercased() {
        case "string":
            return "string"
        case "int", "int32", "int64":
            return "integer"
        case "double", "float":
            return "number"
        case "bool":
            return "boolean"
        default:
            if typeText.hasPrefix("[") && typeText.hasSuffix("]") {
                return "array"
            }
            return "object"
        }
    }
}

// MARK: - Protocols  
public protocol OpenAIToolConvertible {
    // 协议在SwiftOpenAI模块中定义，这里只是引用
}

public protocol SYToolArgsConvertible {
    static var parametersSchema: [String: Any] { get }
}
