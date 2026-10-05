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

		// PCRE2 10.49 (https://github.com/PCRE2Project/pcre2), MTC_OSAX's alternative regex engine (`syntax "PCRE"`).
		// BSD 3-clause; see LICENCE.md. Only the 16-bit library, without JIT; config.h is set up once from config.h.generic.
		.target(
			name: "CPCRE2",
			exclude: ["LICENCE.md"],
			cSettings: [
				.headerSearchPath("."),
				.headerSearchPath("include"),
				.define("HAVE_CONFIG_H"),
				.define("PCRE2_CODE_UNIT_WIDTH", to: "16"),
				.define("PCRE2_STATIC"),
				.unsafeFlags(["-w"]),
			]
		),

		// libyaml 0.2.5 (https://github.com/yaml/libyaml), for PlistFromYAML. MIT; see License. Only src and include.
		.target(
			name: "CYAML",
			exclude: ["License"],
			cSettings: [
				.define("YAML_VERSION_MAJOR", to: "0"),
				.define("YAML_VERSION_MINOR", to: "2"),
				.define("YAML_VERSION_PATCH", to: "5"),
				.define("YAML_VERSION_STRING", to: "\"0.2.5\""),
				.define("YAML_DECLARE_STATIC"),
				.unsafeFlags(["-w"]),
			]
		),

		// tomlc17 R260821 (https://github.com/cktan/tomlc17, commit e0e8868), for PlistFromTOML. MIT; see LICENSE.
		.target(name: "CTOML", exclude: ["LICENSE"], cSettings: [.unsafeFlags(["-w"])]),

		// Regex (Onigmo, or PCRE2 when asked) and literal text search, shared by every suite that searches text.
		.target(name: "TextMatching", dependencies: ["COnigmo", "CPCRE2"]),

		// Suites. Each implemented Satimage section gets its own module.
		.target(name: "Diagnostics", dependencies: ["AppleEventCore"]),
		.target(name: "TextAdditions", dependencies: ["AppleEventCore", "TextMatching", "Settings"]),
		.target(name: "FilesAndFolders", dependencies: ["AppleEventCore"]),
		.target(name: "FileAdditions", dependencies: ["AppleEventCore"]),
		.target(name: "MathFunctions", dependencies: ["AppleEventCore", "Numerics"]),
		.target(name: "ListUtilities", dependencies: ["AppleEventCore", "Numerics"]),
		.target(name: "Arrays", dependencies: ["AppleEventCore", "Numerics"]),
		.target(name: "PropertyLists", dependencies: ["AppleEventCore", "CYAML", "CTOML"]),
		.target(name: "XML", dependencies: ["AppleEventCore", "CLibXML", "PropertyLists"]),

		// MTC_OSAX's settings and the commands that read and change them (an MTC_OSAX extension).
		.target(name: "Settings", dependencies: ["AppleEventCore", "TextMatching"]),

		// macOS's libxml2 and libxslt, which SatimageOSAX's XML suites were built on.
		.systemLibrary(name: "CLibXML"),

		// Numbers from scripts: numbers, lists and Satimage's `array of real`. Shared by Math, List Utilities and Arrays.
		.target(name: "Numerics", dependencies: ["AppleEventCore"]),

		// Registers every suite with a dispatcher; the app links only this.
		.target(name: "MTCOSAX", dependencies: ["AppleEventCore", "Diagnostics", "TextAdditions", "FilesAndFolders", "FileAdditions", "MathFunctions", "ListUtilities", "Arrays", "PropertyLists", "XML", "Settings"]),

		.executableTarget(name: "FixtureRecorder", dependencies: ["AppleEventCore"]),

		// For tests: defaults kept in memory, and a local HTTP server.
		.target(name: "TestSupport"),
		// For tests: AppleScript loaded before any test runs (see AppleScriptPreload.m), a time limit for each test
		// process (TestTimeLimit.m), and no tests at all outside a sandbox (TestSandbox.m).
		.target(name: "AppleScriptPreload"),

		.testTarget(name: "AppleEventCoreTests", dependencies: ["AppleEventCore", "TestSupport", "AppleScriptPreload"]),
		.testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics", "AppleScriptPreload"]),
		.testTarget(name: "TextMatchingTests", dependencies: ["TextMatching", "CPCRE2", "AppleScriptPreload"]),
		.testTarget(name: "TextAdditionsTests", dependencies: ["TextAdditions", "TestSupport", "AppleScriptPreload"]),
		.testTarget(name: "FilesAndFoldersTests", dependencies: ["FilesAndFolders", "AppleScriptPreload"]),
		.testTarget(name: "FileAdditionsTests", dependencies: ["FileAdditions", "TestSupport", "AppleScriptPreload"]),
		.testTarget(name: "NumericsTests", dependencies: ["Numerics", "AppleScriptPreload"]),
		.testTarget(name: "MathFunctionsTests", dependencies: ["MathFunctions", "AppleScriptPreload"]),
		.testTarget(name: "ListUtilitiesTests", dependencies: ["ListUtilities", "AppleScriptPreload"]),
		.testTarget(name: "ArraysTests", dependencies: ["Arrays", "AppleScriptPreload"]),
		.testTarget(name: "PropertyListsTests", dependencies: ["PropertyLists", "AppleScriptPreload"]),
		.testTarget(name: "XMLTests", dependencies: ["XML", "TestSupport", "AppleScriptPreload"]),
		.testTarget(name: "SettingsTests", dependencies: ["Settings", "TextAdditions", "TestSupport", "AppleScriptPreload"]),
		.testTarget(name: "SDEFConsistencyTests", dependencies: ["MTCOSAX", "AppleScriptPreload"]),
		.testTarget(name: "FixtureReplayTests", dependencies: ["MTCOSAX", "TestSupport", "AppleScriptPreload"]),
	]
)
