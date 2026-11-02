// swift-tools-version: 5.9
import PackageDescription
// Model, import, PDF/OCR, and encryption checks run on macOS; fictional fixtures are test-only.
let package = Package(name: "HarborCore", platforms: [.macOS(.v13)], products: [.library(name: "HarborCore", targets: ["HarborCore"])], targets: [.target(name: "HarborCore", path: "Harbor/Core"), .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"], path: "HarborTests", resources: [.copy("Fixtures")])])
