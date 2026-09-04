// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PalmierPro",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PalmierPro", targets: ["PalmierPro"]),
    ],
    traits: [
        .trait(name: "BundledSpeech", description: "Include on-device speech models and MLX."),
        .trait(name: "ProductionTelemetry", description: "Include Sentry and PostHog telemetry."),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.21.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.64.4"),
        .package(url: "https://github.com/clerk/clerk-convex-swift", from: "0.1.0"),
        .package(url: "https://github.com/clerk/clerk-ios", from: "1.3.9"),
        .package(url: "https://github.com/get-convex/convex-swift", from: "0.8.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.5"),
        .package(url: "https://github.com/airbnb/lottie-ios", from: "4.6.1"),
        .package(url: "https://github.com/soniqo/speech-swift", exact: "0.0.21"),
    ],
    targets: [
        .executableTarget(
            name: "PalmierPro",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(
                    name: "Sentry",
                    package: "sentry-cocoa",
                    condition: .when(traits: ["ProductionTelemetry"])
                ),
                .product(
                    name: "PostHog",
                    package: "posthog-ios",
                    condition: .when(traits: ["ProductionTelemetry"])
                ),
                .product(name: "ClerkConvex", package: "clerk-convex-swift"),
                .product(name: "ClerkKit", package: "clerk-ios"),
                .product(name: "ConvexMobile", package: "convex-swift"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Lottie", package: "lottie-ios"),
                .product(
                    name: "MLX",
                    package: "mlx-swift",
                    condition: .when(traits: ["BundledSpeech"])
                ),
                .product(
                    name: "SpeechEnhancement",
                    package: "speech-swift",
                    condition: .when(traits: ["BundledSpeech"])
                ),
                .product(
                    name: "SpeechVAD",
                    package: "speech-swift",
                    condition: .when(traits: ["BundledSpeech"])
                ),
            ],
            path: "Sources/PalmierPro",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
                "Resources/AppIcon.png",
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/MCPB/metag.mcpb"),
                .copy("Resources/Images"),
                .copy("Resources/Changelog"),
                .process("Resources/Localization"),
                .copy("Resources/Models"),
            ],
            swiftSettings: [
                .define("BUNDLED_SPEECH", .when(traits: ["BundledSpeech"])),
                .define("PRODUCTION_TELEMETRY", .when(traits: ["ProductionTelemetry"])),
            ],
            // **AVKit 要显式链上。**
            //
            // 2026-09-04：打包出来的 app 一启动就 abort（退出码 134）：
            //
            //     failed to demangle superclass of VideoPlayerView
            //     from mangled name 'So12AVPlayerViewC'
            //
            // SwiftUI 的 `VideoPlayer` 住在 `_AVKit_SwiftUI` 里，而它内部那个
            // `VideoPlayerView` 继承 AVKit 的 `AVPlayerView`。
            // 链接表里只有 `_AVKit_SwiftUI`，**没有 AVKit** ——
            // 运行时给那个类建元数据时找不到父类，当场 abort。
            //
            // 0.1.13 没崩是**运气**：那条路上的元数据在启动时还没被要到。
            // 用到 `VideoPlayer` 的地方现在有四处（首屏样片、作品墙、
            // 首映、草案播放），靠"启动时还轮不到它"活着不是个办法。
            //
            // 这个崩溃**两千多条测试和整条门全绿**，是打包脚本里那道
            // 「造完就启一次」拦下来的。
            linkerSettings: [.linkedFramework("AVKit")],
            plugins: ["MetalCIKernelPlugin"]
        ),
        .plugin(name: "MetalCIKernelPlugin", capability: .buildTool()),
        .testTarget(
            name: "PalmierProTests",
            dependencies: [
                "PalmierPro",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Tests/PalmierProTests"
        ),
    ]
)
