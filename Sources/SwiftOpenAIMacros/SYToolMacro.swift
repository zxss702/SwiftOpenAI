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
    case requiresStructOrEnum = "@SYToolArgs can only be applied to a struct or an enum"
    case enumAssociatedValuesNotSupported = "@SYToolArgs does not support enums with associated values"
    case enumRawTypeNotString = "@SYToolArgs enum raw type must be String or omitted"

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
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: node, message: SYToolArgsMacroDiagnostic.requiresStructOrEnum))
            return []
        }
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            let enumDescription = enumDecl.extractDocumentationComment()
            if enumDecl.hasNonStringRawType {
                context.diagnose(
                    Diagnostic(node: node, message: SYToolArgsMacroDiagnostic.enumRawTypeNotString))
                return []
            }
            let enumValues = enumDecl.memberBlock.members.compactMap { member -> String? in
                if let enumCase = member.decl.as(EnumCaseDeclSyntax.self),
                   let element = enumCase.elements.first {
                    if element.parameterClause != nil {
                        context.diagnose(
                            Diagnostic(node: node, message: SYToolArgsMacroDiagnostic.enumAssociatedValuesNotSupported))
                        return nil
                    }
                    return element.name.text
                }
                return nil
            }
            let enumValuesString = enumValues.map { "\"\($0)\"" }.joined(separator: ", ")
            let descriptionLine = enumDescription.map {
                "schema[\"description\"] = \"\(escapeSwiftString($0))\""
            } ?? ""
            
            let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(type.trimmed): SYToolArgsConvertible") {
                """
                public static var toolProperties: String { "" }
                
                public static var parametersSchema: [String: Any] = {
                    var schema: [String: Any] = [
                        "type": "string",
                        "enum": [\(raw: enumValuesString)]
                    ]
                    \(raw: descriptionLine)
                    return schema
                }()
                """
            }
            
            return [extensionDecl]
        }
        
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }
        // 收集属性信息
        var propertiesDictEntries: [String] = []
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
                
                // 构建属性字典（用于 parametersSchema / toolProperties）
                let propertyDictCode = buildPropertyDictCode(
                    name: propertyName,
                    typeInfo: propertyTypeInfo,
                    description: propertyDescription
                )
                propertiesDictEntries.append(propertyDictCode)
            }
        }
        
        let propertiesDictString = propertiesDictEntries.isEmpty ? "[:]" : "[\(propertiesDictEntries.joined(separator: ", "))]"
        let requiredString = required.map { "\"\($0)\"" }.joined(separator: ", ")
        
        let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(type.trimmed): SYToolArgsConvertible") {
            """
            public static var toolProperties: String {
                let properties: [String: Any] = \(raw: propertiesDictString)
                
                if properties.isEmpty {
                    return ""
                }
                
                if let data = try? JSONSerialization.data(withJSONObject: properties),
                   let jsonString = String(data: data, encoding: .utf8) {
                    return jsonString
                }
                
                return ""
            }
            
            public static var parametersSchema: [String: Any] =[
                    "type": "object",
                    "properties": \(raw: propertiesDictString),
                    "required": [\(raw: requiredString)],
                    "additionalProperties": false
            ]
            """
        }
        
        return [extensionDecl]
    }
    
    private struct PropertyTypeInfo {
        let type: String
        let items: ItemTypeInfo?
        let customTypeName: String?
    }
    
    private struct ItemTypeInfo {
        let type: String
        let customTypeName: String?
    }
    
    private static func buildPropertyDictCode(
        name: String,
        typeInfo: PropertyTypeInfo,
        description: String?
    ) -> String {
        if let customType = typeInfo.customTypeName {
            var schemaExpression = "\(customType).parametersSchema"
            if let description = description {
                schemaExpression = "\(schemaExpression).merging([\"description\": \"\(escapeSwiftString(description))\"]) { _, new in new }"
            }
            return "\"\(name)\": \(schemaExpression)"
        }
        
        var propertyDictEntries: [String] = [
            "\"type\": \"\(typeInfo.type)\""
        ]
        
        if let description = description {
            propertyDictEntries.append("\"description\": \"\(escapeSwiftString(description))\"")
        }
        
        if let items = typeInfo.items {
            if let customType = items.customTypeName {
                propertyDictEntries.append("\"items\": \(customType).parametersSchema")
            } else {
                let itemEntries: [String] = [
                    "\"type\": \"\(items.type)\""
                ]
                propertyDictEntries.append("\"items\": [\(itemEntries.joined(separator: ", "))]")
            }
        }
        
        let propertyDictCode = "[\(propertyDictEntries.joined(separator: ", "))]"
        return "\"\(name)\": \(propertyDictCode)"
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
            let elementType = extractElementTypeInfo(from: arrayType.element)
            return PropertyTypeInfo(type: "array", items: elementType, customTypeName: nil)
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
    
    private static func extractElementTypeInfo(from type: TypeSyntax) -> ItemTypeInfo {
        // 递归处理可选类型
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return extractElementTypeInfo(from: optionalType.wrappedType)
        }
        
        // 处理标识符类型
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            let typeName = identifierType.name.text
            
            switch typeName {
            case "String":
                return ItemTypeInfo(type: "string", customTypeName: nil)
            case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
                return ItemTypeInfo(type: "integer", customTypeName: nil)
            case "Double", "Float", "CGFloat":
                return ItemTypeInfo(type: "number", customTypeName: nil)
            case "Bool":
                return ItemTypeInfo(type: "boolean", customTypeName: nil)
            default:
                return ItemTypeInfo(type: "object", customTypeName: typeName)
            }
        }
        
        // 默认为 object
        return ItemTypeInfo(type: "object", customTypeName: nil)
    }
}

private extension EnumDeclSyntax {
    var hasNonStringRawType: Bool {
        guard let inheritanceClause else { return false }
        let rawTypeNames = inheritanceClause.inheritedTypes.map { $0.type.trimmedDescription }
        return rawTypeNames.contains(where: SYToolArgsMacro.isKnownNonStringRawType)
    }
}

private extension SYToolArgsMacro {
    static func isKnownNonStringRawType(_ typeName: String) -> Bool {
        let nonStringRawTypes: Set<String> = [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "CGFloat",
            "Bool", "Character",
            "Swift.Int", "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
            "Swift.UInt", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
            "Swift.Double", "Swift.Float", "Swift.Bool", "Swift.Character",
            "CoreGraphics.CGFloat"
        ]
        if typeName == "String" || typeName == "Swift.String" {
            return false
        }
        return nonStringRawTypes.contains(typeName)
    }
}



// MARK: - Protocols  
nonisolated public protocol OpenAIToolConvertible {
    // 协议在SwiftOpenAI模块中定义，这里只是引用
}

nonisolated public protocol SYToolArgsConvertible {
    static var parametersSchema: [String: Any] { get }
}
