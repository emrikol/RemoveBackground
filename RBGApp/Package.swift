// swift-tools-version:5.9
import PackageDescription

// Release-only size optimization. We use -Osize (optimize for size over speed —
// negligible runtime cost for a UI app). We deliberately OMIT TwinKley's
// -disable-reflection-metadata: this app is entirely SwiftUI, whose view diffing can
// rely on reflection metadata, and the size win would be negligible next to the
// statically-linked ONNX Runtime that dominates the binary — not worth the risk.
let sizeOptimization: [SwiftSetting] = [
    .unsafeFlags(["-Osize"], .when(configuration: .release)),
]

let package = Package(
    name: "RemoveBackground",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.19.0"),
    ],
    targets: [
        .executableTarget(
            name: "RemoveBackground",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: "Sources/RemoveBackground",
            swiftSettings: sizeOptimization
        ),
    ]
)
