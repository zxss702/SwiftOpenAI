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
        let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(type.trimmed): OpenAIToolConvertible") {
            """
            public var asChatCompletionTool: SwiftOpenAI.ChatQuery.ChatCompletionToolParam {
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
        
        // 收集属性信息
        var propertiesCode: [String] = []
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
                
                let propertyTypeInfo = extractPropertyType(from: binding.typeAnnotation?.type)
                let propertyDescription = member.extractDocumentationComment()
                
                // 构建属性字典的代码
                let propertyCode = buildPropertyDictCode(
                    name: propertyName,
                    typeInfo: propertyTypeInfo,
                    description: propertyDescription
                )
                propertiesCode.append(propertyCode)
            }
        }
        
        let propertiesString = propertiesCode.joined(separator: ",\n            ")
        let requiredString = required.map { "\"\($0)\"" }.joined(separator: ", ")
        
        let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(type.trimmed): SYToolArgsConvertible") {
            """
            public static var toolProperties: String {
                // 使用 JSONEncoder 生成 JSON 字符串
                let properties: [String: [String: Any]] = [
                    \(raw: propertiesString)
                ]
                
                if let data = try? JSONSerialization.data(withJSONObject: properties),
                   let jsonString = String(data: data, encoding: .utf8) {
                    // 移除外层的大括号，只保留属性内容
                    let trimmed = jsonString.dropFirst().dropLast()
                    return String(trimmed)
                } else {
                    return ""
                }
            }
            
            public static var parametersSchema: [String: Any] {
                let properties: [String: [String: Any]] = [
                    \(raw: propertiesString)
                ]
                
                return [
                    "type": "object",
                    "properties": properties,
                    "required": [\(raw: requiredString)],
                    "additionalProperties": false
                ]
            }
            """
        }
        
        return [extensionDecl]
    }
    
    private struct PropertyTypeInfo {
        let type: String
        let items: [String: Any]?
        let customTypeName: String?
    }
    
    // JSON Schema 的 Codable 结构体
    private struct PropertySchema: Codable {
        let type: String
        let description: String?
        let items: ItemsSchema?
        
        struct ItemsSchema: Codable {
            let type: String
        }
    }
    
    private static func buildPropertyDictCode(
        name: String,
        typeInfo: PropertyTypeInfo,
        description: String?
    ) -> String {
        // 如果是自定义对象类型且有类型名称，引用其 parametersSchema
        if typeInfo.type == "object", let customType = typeInfo.customTypeName {
            var dictCode = "\"type\": \"object\""
            
            if let description = description {
                let escapedDesc = escapeSwiftString(description)
                dictCode += ", \"description\": \"\(escapedDesc)\""
            }
            
            // 引用嵌套类型的 parametersSchema 中的 properties
            dictCode += ", \"properties\": \(customType).parametersSchema[\"properties\"] as! [String: Any]"
            
            return "\"\(name)\": [\(dictCode)]"
        }
        
        // 基本类型
        var dictCode = "\"type\": \"\(typeInfo.type)\""
        
        if let description = description {
            let escapedDesc = escapeSwiftString(description)
            dictCode += ", \"description\": \"\(escapedDesc)\""
        }
        
        if let items = typeInfo.items, let itemType = items["type"] as? String {
            dictCode += ", \"items\": [\"type\": \"\(itemType)\"]"
        }
        
        return "\"\(name)\": [\(dictCode)]"
    }
    
    // 转义 Swift 字符串字面量
    private static func escapeSwiftString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    private static func extractPropertyType(from type: TypeSyntax?) -> PropertyTypeInfo {
        guard let type = type else { return PropertyTypeInfo(type: "string", items: nil, customTypeName: nil) }
        
        // 处理可选类型
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return extractPropertyType(from: optionalType.wrappedType)
        }
        
        // 处理数组类型
        if let arrayType = type.as(ArrayTypeSyntax.self) {
            let elementType = extractElementType(from: arrayType.element)
            return PropertyTypeInfo(type: "array", items: ["type": elementType], customTypeName: nil)
        }
        
        // 处理标识符类型（基本类型和自定义类型）
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            let typeName = identifierType.name.text
            
            // 映射到 JSON Schema 类型
            switch typeName {
            case "String":
                return PropertyTypeInfo(type: "string", items: nil, customTypeName: nil)
            case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
                return PropertyTypeInfo(type: "integer", items: nil, customTypeName: nil)
            case "Double", "Float", "CGFloat":
                return PropertyTypeInfo(type: "number", items: nil, customTypeName: nil)
            case "Bool":
                return PropertyTypeInfo(type: "boolean", items: nil, customTypeName: nil)
            default:
                // 自定义类型 - 保存类型名称
                return PropertyTypeInfo(type: "object", items: nil, customTypeName: typeName)
            }
        }
        
        // 其他类型默认为 object（可能是泛型、元组等复杂类型）
        return PropertyTypeInfo(type: "object", items: nil, customTypeName: type.trimmedDescription)
    }
    
    private static func extractElementType(from type: TypeSyntax) -> String {
        // 递归处理可选类型
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return extractElementType(from: optionalType.wrappedType)
        }
        
        // 处理标识符类型
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            let typeName = identifierType.name.text
            
            switch typeName {
            case "String":
                return "string"
            case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
                return "integer"
            case "Double", "Float", "CGFloat":
                return "number"
            case "Bool":
                return "boolean"
            default:
                return "object"
            }
        }
        
        // 默认为 object
        return "object"
    }
}



// MARK: - Protocols  
nonisolated public protocol OpenAIToolConvertible {
    // 协议在SwiftOpenAI模块中定义，这里只是引用
}

nonisolated public protocol SYToolArgsConvertible {
    static var parametersSchema: [String: Any] { get }
}
