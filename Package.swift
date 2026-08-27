// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Screenly",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Screenly", targets: ["Screenly"])
    ],
    targets: [
        .executableTarget(
            name: "Screenly",
            path: "Sources/Screenly"
        )
    ]
)
