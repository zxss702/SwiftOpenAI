// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftOpenAI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .macCatalyst(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "SwiftOpenAI",
            targets: ["SwiftOpenAI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0")
    ] + {
        #if os(Windows)
        return []
        #else
        return [
            .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.33.1"),
            .package(url: "https://github.com/apple/swift-nio.git", from: "2.97.1")
        ]
        #endif
    }(),
    targets: [
        .target(
            name: "SwiftOpenAI",
            dependencies: [
                "SwiftOpenAIMacros"
            ] + {
                #if os(Windows)
                return []
                #else
                return [
                    .product(name: "AsyncHTTPClient", package: "async-http-client"),
                    .product(name: "NIOCore", package: "swift-nio"),
                    .product(name: "NIOHTTP1", package: "swift-nio")
                ]
                #endif
            }()
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
