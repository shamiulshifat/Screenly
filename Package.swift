// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Framecast",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Framecast", targets: ["Framecast"])
    ],
    targets: [
        .executableTarget(
            name: "Framecast",
            path: "Sources/Framecast"
        )
    ]
)
