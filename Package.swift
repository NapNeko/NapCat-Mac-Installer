// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NapCatInstallerNetwork",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "InstallerNetwork", path: "NapCatInstaller", sources: ["Network.swift"]),
        .testTarget(name: "InstallerNetworkTests", dependencies: ["InstallerNetwork"], path: "Tests"),
    ]
)
