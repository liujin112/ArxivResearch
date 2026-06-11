// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArxivResearch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ArxivResearchCore", targets: ["ArxivResearchCore"]),
        .executable(name: "ArxivResearchApp", targets: ["ArxivResearchApp"]),
        .executable(name: "ArxivResearchHelper", targets: ["ArxivResearchHelper"])
    ],
    targets: [
        .target(
            name: "ArxivResearchCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "ArxivResearchApp",
            dependencies: ["ArxivResearchCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
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
        )
    ]
)
