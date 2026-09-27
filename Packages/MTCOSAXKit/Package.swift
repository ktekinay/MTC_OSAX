// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "MTCOSAXKit",
	platforms: [.macOS("26.6")],
	products: [
		.library(name: "MTCOSAX", targets: ["MTCOSAX"]),
		.executable(name: "fixture-recorder", targets: ["FixtureRecorder"]),
	],
	targets: [
		// Apple event plumbing shared by every suite: dispatch, parameters, conversion, errors.
		.target(name: "AppleEventCore"),

		// Suites. Each implemented Satimage section gets its own module.
		.target(name: "Diagnostics", dependencies: ["AppleEventCore"]),

		// Registers every suite with a dispatcher; the app links only this.
		.target(name: "MTCOSAX", dependencies: ["AppleEventCore", "Diagnostics"]),

		.executableTarget(name: "FixtureRecorder", dependencies: ["AppleEventCore"]),

		.testTarget(name: "AppleEventCoreTests", dependencies: ["AppleEventCore"]),
		.testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics"]),
		.testTarget(name: "SDEFConsistencyTests", dependencies: ["MTCOSAX"]),
		.testTarget(name: "FixtureReplayTests", dependencies: ["MTCOSAX"]),
	]
)
