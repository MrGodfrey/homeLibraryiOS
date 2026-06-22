// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "home-library-cloudkit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "home-library-cloudkit",
            targets: ["home-library-cloudkit"]
        ),
        .library(
            name: "HomeLibraryCloudKitCore",
            targets: ["HomeLibraryCloudKitCore"]
        )
    ],
    targets: [
        .target(
            name: "HomeLibraryCloudKitCore"
        ),
        .executableTarget(
            name: "home-library-cloudkit",
            dependencies: ["HomeLibraryCloudKitCore"]
        ),
        .testTarget(
            name: "HomeLibraryCloudKitTests",
            dependencies: ["HomeLibraryCloudKitCore"]
        )
    ]
)
