import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

enum AIModelSchemaMacroDiagnostic: String, DiagnosticMessage {
    case requiresStructOrEnum = "@AIModelSchema can only be applied to a struct or an enum"

    var message: String { rawValue }
    var diagnosticID: MessageID {
        MessageID(domain: "SwiftOpenAIMacros", id: "AIModelSchemaMacro.\(self)")
    }
    var severity: DiagnosticSeverity { .error }
}

public struct AIModelSchemaMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: node, message: AIModelSchemaMacroDiagnostic.requiresStructOrEnum))
            return []
        }

        guard
            let jsonSchema = declaration.as(EnumDeclSyntax.self)?.outputModelSchema
                ?? declaration.as(StructDeclSyntax.self)?.outputModelSchema
        else { return [] }
        
        let result: DeclSyntax =
            #"""
            """
            \#(raw: jsonSchema.compactJson)
            """
            """#
        
        let extensionDecl = try ExtensionDeclSyntax("extension \(type.trimmed): AIModelSchema") {
            """
            \(declaration.modifiers)static var outputSchema: String { \(raw: result) }
            """
        }

        return [extensionDecl]
    }
}

// MARK: - JSON Schema Generation
extension StructDeclSyntax {
    var outputModelSchema: JSONSchemaModel? {
        _ = name.text // structName not used currently
        var properties: [String: JSONSchemaProperty] = [:]
        var required: [String] = []
        
        // 解析结构体级别的文档注释
        let structDescription = extractDocumentationComment()
        
        for member in memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self),
               let binding = variableDecl.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                let isOptional = binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) == true
                
                if !isOptional {
                    required.append(propertyName)
                }
                
                // 解析属性的文档注释
                let propertyDescription = member.extractDocumentationComment()
                
                // 获取属性类型信息
                let propertyTypeInfo = extractPropertyTypeInfo(from: binding.typeAnnotation?.type)
                
                properties[propertyName] = JSONSchemaProperty(
                    type: propertyTypeInfo.type,
                    description: propertyDescription,
                    items: propertyTypeInfo.items
                )
            }
        }
        
        return JSONSchemaModel(
            type: "object",
            description: structDescription,
            enumValues: nil,
            properties: properties,
            required: required.isEmpty ? nil : required,
            additionalProperties: false
        )
    }
    
    private func extractPropertyTypeInfo(from type: TypeSyntax?) -> (type: String, items: String?) {
        guard let type = type else { return ("string", nil) }
        
        let typeText = type.trimmedDescription
        
        // 处理可选类型
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return extractPropertyTypeInfo(from: optionalType.wrappedType)
        }
        
        // 处理数组类型
        if typeText.hasPrefix("[") && typeText.hasSuffix("]") {
            let innerType = String(typeText.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            
            // 检查是否是自定义类型（可能需要引用其outputSchema）
            if isCustomType(innerType) {
                return ("array", "\\(\(innerType).outputSchema)")
            } else {
                return ("array", "{\"type\":\"\(mapBasicType(innerType))\"}")
            }
        }
        
        // 基本类型映射
        let mappedType = mapBasicType(typeText)
        
        // 检查是否是自定义类型
        if mappedType == "object" && isCustomType(typeText) {
            return ("object", nil) // 自定义对象类型将在生成时处理
        }
        
        return (mappedType, nil)
    }
    
    private func mapBasicType(_ typeText: String) -> String {
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
            return "object"
        }
    }
    
    private func isCustomType(_ typeText: String) -> Bool {
        // 检查是否是自定义类型（首字母大写，且不是基本类型）
        guard let firstChar = typeText.first else { return false }
        
        let basicTypes = ["String", "Int", "Int32", "Int64", "Double", "Float", "Bool"]
        
        return firstChar.isUppercase && !basicTypes.contains(typeText)
    }
}

extension EnumDeclSyntax {
    var outputModelSchema: JSONSchemaModel? {
        let enumDescription = extractDocumentationComment()
        
        let enumValues = memberBlock.members.compactMap { member -> String? in
            if let enumCase = member.decl.as(EnumCaseDeclSyntax.self),
               let element = enumCase.elements.first {
                return element.name.text
            }
            return nil
        }
        
        return JSONSchemaModel(
            type: "string",
            description: enumDescription,
            enumValues: enumValues.isEmpty ? nil : enumValues,
            properties: nil,
            required: nil,
            additionalProperties: nil
        )
    }
}

// MARK: - Documentation Comment Parsing
extension DeclGroupSyntax {
    func extractDocumentationComment() -> String? {
        // 查找文档注释，通常在声明之前
        return leadingTrivia.extractDocumentationComment()
    }
}

extension MemberBlockItemSyntax {
    func extractDocumentationComment() -> String? {
        // 查找属性的文档注释
        return leadingTrivia.extractDocumentationComment()
    }
}

extension Trivia {
    func extractDocumentationComment() -> String? {
        var comments: [String] = []
        
        for piece in self {
            switch piece {
            case .docLineComment(let text):
                // 提取 /// 注释
                let cleanText = text.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !cleanText.isEmpty {
                    comments.append(cleanText)
                }
            case .docBlockComment(let text):
                // 提取 /** */ 注释
                let cleanText = text
                    .dropFirst(3)
                    .dropLast(2)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanText.isEmpty {
                    comments.append(cleanText)
                }
            default:
                break
            }
        }
        
        return comments.isEmpty ? nil : comments.joined(separator: " ")
    }
}

// MARK: - JSON Schema Models
struct JSONSchemaModel {
    let type: String
    let description: String?
    let enumValues: [String]?
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let additionalProperties: Bool?
    
    var compactJson: String {
        var dict: [String: Any] = ["type": type]
        
        if let description = description {
            dict["description"] = description
        }
        
        if let enumValues = enumValues {
            dict["enum"] = enumValues
        }
        
        if let properties = properties {
            var propertiesDict: [String: [String: Any]] = [:]
            
            for (key, prop) in properties {
                var propDict: [String: Any] = ["type": prop.type]
                
                if let description = prop.description {
                    propDict["description"] = description
                }
                
                if let items = prop.items {
                    if items.hasPrefix("\\(") && items.hasSuffix(".outputSchema)") {
                        // 这是一个嵌套类型引用，我们需要在生成时处理
                        propDict["items"] = "NESTED_TYPE_REFERENCE:\(items)"
                    } else if let itemsData = items.data(using: .utf8),
                              let itemsJson = try? JSONSerialization.jsonObject(with: itemsData) {
                        propDict["items"] = itemsJson
                    } else {
                        propDict["items"] = items
                    }
                }
                
                propertiesDict[key] = propDict
            }
            
            dict["properties"] = propertiesDict
        }
        
        if let required = required {
            dict["required"] = required
        }
        
        if let additionalProperties = additionalProperties {
            dict["additionalProperties"] = additionalProperties
        }
        
        do {
            var jsonString = try jsonStringFromDict(dict)
            
            // 处理嵌套类型引用
            jsonString = processNestedTypeReferences(jsonString)
            
            return jsonString
        } catch {
            return "{}"
        }
    }
    
    private func jsonStringFromDict(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    private func processNestedTypeReferences(_ jsonString: String) -> String {
        // 将嵌套类型引用替换为实际的插值表达式
        var result = jsonString
        
        // 简单的字符串替换，避免正则表达式的转义问题
        let searchPattern = "\"NESTED_TYPE_REFERENCE:"
        let endPattern = "\""
        
        while let startRange = result.range(of: searchPattern) {
            let searchStart = startRange.upperBound
            guard let endRange = result.range(of: endPattern, range: searchStart..<result.endIndex) else {
                break
            }
            
            let fullRange = startRange.lowerBound..<endRange.upperBound
            let interpolationContent = String(result[searchStart..<endRange.lowerBound])
            
            // 替换为插值表达式
            result.replaceSubrange(fullRange, with: interpolationContent)
        }
        
        // 修复转义问题 - 将 \/ 替换为 /
        result = result.replacingOccurrences(of: "\\/", with: "/")
        
        return result
    }
}

struct JSONSchemaProperty {
    let type: String
    let description: String?
    let items: String? // 用于数组类型的items定义
}