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
    )
  ],
  targets: [
    .executableTarget(
      name: "ParaDict",
      dependencies: [
        "FluidAudio"
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
