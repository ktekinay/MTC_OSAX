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
		.target(name: "AppleEventCore", dependencies: ["CFileReferences"]),

		// FSRef file references (`fsrf` descriptors), which Swift can't reach.
		.target(name: "CFileReferences", linkerSettings: [.linkedFramework("CoreServices")]),

		// Onigmo 6.2.0 (https://github.com/k-takata/Onigmo), the regex engine Satimage used. BSD 2-clause; see COPYING.
		// Only the core engine, the Unicode encodings and the ASCII and ISO-8859-1 encodings it refers to are included.
		.target(
			name: "COnigmo",
			exclude: ["COPYING"],
			cSettings: [
				.headerSearchPath("."),
				.headerSearchPath("enc"),
				.headerSearchPath("enc/unicode"),
				.define("HAVE_CONFIG_H"),
				.define("MTC_SATIMAGE_COMPATIBILITY"),
				.unsafeFlags(["-w"]),
			]
		),

		// Regex (Onigmo) and literal text search, shared by every suite that searches text.
		.target(name: "TextMatching", dependencies: ["COnigmo"]),

		// Suites. Each implemented Satimage section gets its own module.
		.target(name: "Diagnostics", dependencies: ["AppleEventCore"]),
		.target(name: "TextAdditions", dependencies: ["AppleEventCore", "TextMatching"]),
		.target(name: "FilesAndFolders", dependencies: ["AppleEventCore"]),
		.target(name: "FileAdditions", dependencies: ["AppleEventCore"]),
		.target(name: "MathFunctions", dependencies: ["AppleEventCore", "Numerics"]),
		.target(name: "ListUtilities", dependencies: ["AppleEventCore", "Numerics"]),
		.target(name: "Arrays", dependencies: ["AppleEventCore", "Numerics"]),
		.target(name: "PropertyLists", dependencies: ["AppleEventCore"]),
		.target(name: "XML", dependencies: ["AppleEventCore", "CLibXML", "PropertyLists"]),

		// macOS's libxml2 and libxslt, which SatimageOSAX's XML suites were built on.
		.systemLibrary(name: "CLibXML"),

		// Numbers from scripts: numbers, lists and Satimage's `array of real`. Shared by Math, List Utilities and Arrays.
		.target(name: "Numerics", dependencies: ["AppleEventCore"]),

		// Registers every suite with a dispatcher; the app links only this.
		.target(name: "MTCOSAX", dependencies: ["AppleEventCore", "Diagnostics", "TextAdditions", "FilesAndFolders", "FileAdditions", "MathFunctions", "ListUtilities", "Arrays", "PropertyLists", "XML"]),

		.executableTarget(name: "FixtureRecorder", dependencies: ["AppleEventCore"]),

		.testTarget(name: "AppleEventCoreTests", dependencies: ["AppleEventCore"]),
		.testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics"]),
		.testTarget(name: "TextMatchingTests", dependencies: ["TextMatching"]),
		.testTarget(name: "TextAdditionsTests", dependencies: ["TextAdditions"]),
		.testTarget(name: "FilesAndFoldersTests", dependencies: ["FilesAndFolders"]),
		.testTarget(name: "FileAdditionsTests", dependencies: ["FileAdditions"]),
		.testTarget(name: "NumericsTests", dependencies: ["Numerics"]),
		.testTarget(name: "MathFunctionsTests", dependencies: ["MathFunctions"]),
		.testTarget(name: "ListUtilitiesTests", dependencies: ["ListUtilities"]),
		.testTarget(name: "ArraysTests", dependencies: ["Arrays"]),
		.testTarget(name: "PropertyListsTests", dependencies: ["PropertyLists"]),
		.testTarget(name: "XMLTests", dependencies: ["XML"]),
		.testTarget(name: "SDEFConsistencyTests", dependencies: ["MTCOSAX"]),
		.testTarget(name: "FixtureReplayTests", dependencies: ["MTCOSAX"]),
	]
)
