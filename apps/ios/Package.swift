// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommandVCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CommandVCore", targets: ["CommandVCore"])],
    targets: [
        .target(name: "CommandVCore", path: "Shared", exclude: ["CommandV.entitlements", "DeviceStore.swift", "Discovery.swift", "MediaImporter.swift", "PrivacyInfo.xcprivacy", "TransferModel.swift"], sources: ["Protocol.swift", "PinnedClient.swift"]),
        .testTarget(name: "ProtocolTests", dependencies: ["CommandVCore"], path: "Tests"),
        .testTarget(name: "TransportTests", dependencies: ["CommandVCore"], path: "CoreTests")
    ]
)
