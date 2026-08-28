// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ParaDict",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "ParaDict", targets: ["ParaDict"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/FluidInference/FluidAudio.git",
      .upToNextMinor(from: "0.12.6")
    ),
    .package(
      url: "https://github.com/apple/swift-atomics.git",
      from: "1.3.0"
    ),
    .package(
      url: "https://github.com/ml-explore/mlx-swift-lm",
      .upToNextMinor(from: "2.31.3")
    ),
  ],
  targets: [
    .executableTarget(
      name: "ParaDict",
      dependencies: [
        "FluidAudio",
        .product(name: "Atomics", package: "swift-atomics"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
      ],
      path: "Sources/ParaDict",
      exclude: ["Resources"],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "ParaDictTests",
      dependencies: ["ParaDict"],
      path: "Tests/ParaDictTests",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ]
    ),
  ]
)
