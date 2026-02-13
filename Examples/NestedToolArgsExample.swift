import SwiftOpenAI

// 嵌套的工具参数示例

@SYToolArgs
struct PersonInfo {
    /// 人的名字
    let name: String
    
    /// 人的年龄
    let age: Int
    
    /// 人的邮箱地址
    let email: String?
}

@SYToolArgs
struct AddressInfo {
    /// 街道地址
    let street: String
    
    /// 城市
    let city: String
    
    /// 邮政编码
    let zipCode: String
}

@SYToolArgs
struct CreateUserArgs {
    /// 用户的个人信息
    let personalInfo: PersonInfo
    
    /// 用户的地址信息
    let address: AddressInfo
    
    /// 用户的标签列表
    let tags: [String]
    
    /// 是否激活用户
    let isActive: Bool
}

// 使用示例
func exampleUsage() {
    // 打印生成的 toolProperties
    print("PersonInfo.toolProperties:")
    print(PersonInfo.toolProperties)
    print("\n")
    
    print("CreateUserArgs.toolProperties:")
    print(CreateUserArgs.toolProperties)
    print("\n")
    
    // 打印生成的 parametersSchema
    print("CreateUserArgs.parametersSchema:")
    print(CreateUserArgs.parametersSchema.toAnyDictionary())
}
