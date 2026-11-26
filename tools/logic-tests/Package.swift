// swift-tools-version: 6.0
import PackageDescription

// Portable logic harness for Velura.
//
// SwiftUI/CoreLocation/Combine cannot compile off Apple platforms, so this package
// compiles only the dependency-free slice of the app (models, storage, GPX export,
// insights math) and runs it as real Swift on any host with a toolchain installed:
//
//     python tools/logic-tests/prepare.py && swift test --package-path tools/logic-tests
//
// The sources are copied in by prepare.py; never edit Sources/ by hand.
let package = Package(
    name: "VeluraCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VeluraCore", path: "Sources/VeluraCore"),
        .testTarget(name: "VeluraCoreTests", dependencies: ["VeluraCore"], path: "Tests/VeluraCoreTests"),
    ]
)
