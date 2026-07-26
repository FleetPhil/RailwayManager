// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RailwayManager",
    platforms: [.macOS(.v15), .iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "RailwayManager",
            targets: ["RailwayManager"]),
    ],
    
    dependencies: [
        .package(url: "https://github.com/mredig/SwiftSerial", .upToNextMajor(from: "0.1.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/Timac/SunCalc.git", from: "1.0.0"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", branch: "master"),
        .package(url: "https://github.com/swift-server-community/mqtt-nio.git", .upToNextMajor(from: "2.7.0")),
//        .package(url: "https://github.com/FleetPhil/ModelRailwayHardware.git", .upToNextMajor(from: "0.0.1"))
    ],
    
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "RailwayManager",
        dependencies: [
            "SwiftyBeaver",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "SunCalc",
            "SwiftGraph",
            .product(name: "MQTTNIO", package: "mqtt-nio"),
            "SwiftSerial"
//            "ModelRailwayHardware",
        ],
        resources: [.process("Resources")]
            ),
    ],
    
    swiftLanguageModes: [.v6]
)
