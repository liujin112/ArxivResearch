// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArxivResearch",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ArxivResearchCore", targets: ["ArxivResearchCore"]),
        .library(name: "ArxivResearchCloudSync", targets: ["ArxivResearchCloudSync"]),
        .library(name: "ArxivResearchMobileUI", targets: ["ArxivResearchMobileUI"]),
        .executable(name: "ArxivResearchApp", targets: ["ArxivResearchApp"]),
        .executable(name: "ArxivResearchHelper", targets: ["ArxivResearchHelper"]),
        .executable(name: "ArxivResearchMobileApp", targets: ["ArxivResearchMobileApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(
            name: "ArxivResearchCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication")
            ]
        ),
        .executableTarget(
            name: "ArxivResearchApp",
            dependencies: [
                "ArxivResearchCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .target(
            name: "ArxivResearchCloudSync",
            dependencies: ["ArxivResearchCore"],
            linkerSettings: [
                .linkedFramework("CloudKit")
            ]
        ),
        .target(
            name: "ArxivResearchMobileUI",
            dependencies: [
                "ArxivResearchCore",
                "ArxivResearchCloudSync"
            ]
        ),
        .executableTarget(
            name: "ArxivResearchMobileApp",
            dependencies: ["ArxivResearchMobileUI"]
        ),
        .executableTarget(
            name: "ArxivResearchHelper",
            dependencies: ["ArxivResearchCore"]
        ),
        .testTarget(
            name: "ArxivResearchCoreTests",
            dependencies: ["ArxivResearchCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "ArxivResearchCloudSyncTests",
            dependencies: [
                "ArxivResearchCore",
                "ArxivResearchCloudSync"
            ]
        )
    ]
)
