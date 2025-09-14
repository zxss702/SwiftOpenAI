// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftOpenAI",
    platforms: [
        .macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftOpenAI",
            targets: ["SwiftOpenAI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0")
    ],
    targets: [
        .target(
            name: "SwiftOpenAI",
            dependencies: ["SwiftOpenAIMacros"]
        ),
        .macro(
            name: "SwiftOpenAIMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "SwiftOpenAITests",
            dependencies: ["SwiftOpenAI"]
        )
    ]
)
