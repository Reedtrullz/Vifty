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
        .executable(name: "ViftyDaemon", targets: ["ViftyDaemon"]),
        .executable(name: "ViftyCtl", targets: ["ViftyCtl"]),
        .executable(name: "ViftyAXCollector", targets: ["ViftyAXCollector"])
    ],
    targets: [
        .target(
            name: "ViftyBuildProvenance"
        ),
        .target(
            name: "ViftyCore",
            dependencies: ["ViftyPrivateIOKit"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "ViftyFanControlSafety",
            dependencies: ["ViftyCore"]
        ),
        .target(
            name: "ViftyDaemonSupport",
            dependencies: ["ViftyCore", "ViftyFanControlSafety"]
        ),
        .target(
            name: "ViftyHelperSupport",
            dependencies: ["ViftyCore", "ViftyFanControlSafety"]
        ),
        .target(
            name: "ViftyAXEvidenceCore",
            dependencies: ["ViftyBuildProvenance"]
        ),
        .executableTarget(
            name: "ViftyAXCollector",
            dependencies: ["ViftyAXEvidenceCore", "ViftyBuildProvenance"],
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "Vifty",
            dependencies: ["ViftyCore", "ViftyBuildProvenance"]
        ),
        .executableTarget(
            name: "ViftyHelper",
            dependencies: ["ViftyCore", "ViftyHelperSupport"]
        ),
        .executableTarget(
            name: "ViftyCtl",
            dependencies: ["ViftyCore"]
        ),
        .executableTarget(
            name: "ViftyDaemon",
            dependencies: ["ViftyCore", "ViftyFanControlSafety", "ViftyDaemonSupport"],
            linkerSettings: [
                .linkedLibrary("bsm")
            ]
        ),
        .executableTarget(
            name: "ViftyLockTestHelper",
            dependencies: ["ViftyFanControlSafety"]
        ),
        .testTarget(
            name: "ViftyCoreTests",
            dependencies: [
                "ViftyCore",
                "ViftyFanControlSafety",
                "ViftyDaemonSupport",
                "ViftyHelperSupport",
                "ViftyAXEvidenceCore",
                "ViftyBuildProvenance",
                "ViftyAXCollector",
                "Vifty",
                "ViftyCtl",
                "ViftyLockTestHelper"
            ]
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
