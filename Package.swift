// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Vifty",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ViftyCore", targets: ["ViftyCore"]),
        .executable(name: "Vifty", targets: ["Vifty"]),
        .executable(name: "ViftyHelper", targets: ["ViftyHelper"]),
        .executable(name: "ViftyDaemon", targets: ["ViftyDaemon"])
    ],
    targets: [
        .target(
            name: "ViftyCore",
            dependencies: ["ViftyPrivateIOKit"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "Vifty",
            dependencies: ["ViftyCore"]
        ),
        .executableTarget(
            name: "ViftyHelper",
            dependencies: ["ViftyCore"]
        ),
        .executableTarget(
            name: "ViftyDaemon",
            dependencies: ["ViftyCore"]
        ),
        .testTarget(
            name: "ViftyCoreTests",
            dependencies: ["ViftyCore"]
        ),
        .target(
            name: "ViftyPrivateIOKit",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
