import Foundation
import MTCOSAX
import Testing

/// Codes that belong to MTC_OSAX itself rather than being copied from Satimage: the diagnostics, settings and
/// property list formats suites' event classes, and the settings suite's enumeration and record type (`MTs…`).
private let ownSuitePrefixes = ["MTCd", "MTCs", "MTs", "MTCp"]

/// Parameters MTC_OSAX adds to copied Satimage commands: `dollar references`.
private let extensionParameters: Set = ["DlRf"]

/// Parameters MTC_OSAX adds to one command: `syntax` on `splittext` (for PCRE; Satimage's other regex commands had it),
/// and `in` on `PlistToJSON` (writing a file, like MTC_OSAX's YAML and TOML commands).
private let commandExtensions: [String: Set<String>] = ["SATISplt": ["synt"], "PLSTJSON": ["kfil"]]

/// Commands whose direct parameter takes more than Satimage's: `PlistFromJSON` also takes a file.
private let directParameterExtensions: Set = ["PLSTNOSJ"]

struct SDEFConsistencyTests {
	@Test func everySDEFCommandHasAHandler() throws {
		let sdef = try SDEF(contentsOf: ProjectFiles.appSDEF)
		let handled = Set(CommandCatalog.makeDispatcher().commands.keys.map(\.code))
		let missing = sdef.commands.filter { !handled.contains($0.code) }.map { "\($0.name) (\($0.code))" }
		#expect(missing.isEmpty, "In MTC_OSAX.sdef but not implemented: \(missing)")
	}

	@Test func everyHandlerIsInTheSDEF() throws {
		let sdef = try SDEF(contentsOf: ProjectFiles.appSDEF)
		let defined = Set(sdef.commands.map(\.code))
		let extra = CommandCatalog.makeDispatcher().commands.values
			.filter { !defined.contains($0.key.code) }
			.map { "\($0.name) (\($0.key.code))" }
		#expect(extra.isEmpty, "Implemented but missing from MTC_OSAX.sdef: \(extra)")
	}

	@Test func handlerNamesMatchSDEF() throws {
		let sdef = try SDEF(contentsOf: ProjectFiles.appSDEF)
		for command in CommandCatalog.makeDispatcher().commands.values {
			let entry = sdef.commands.first { $0.code == command.key.code }
			#expect(entry == nil || entry?.name == command.name, "\(command.key.code): handler \"\(command.name)\", SDEF \"\(entry?.name ?? "")\"")
		}
	}

	@Test func copiedSuitesMatchSatimage() throws {
		let ours = try SDEF(contentsOf: ProjectFiles.appSDEF)
		let satimage = try SDEF(contentsOf: ProjectFiles.satimageSDEF)
		let differences = ours.differences(from: satimage, ignoringCodesWithPrefixes: ownSuitePrefixes, extensionParameters: extensionParameters,
		                                   commandExtensions: commandExtensions, directParameterExtensions: directParameterExtensions)
		#expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
	}

	/// A code used twice would send one command's events (or one parameter) to another; the comparison with
	/// Satimage, which looks codes up, wouldn't notice.
	@Test func codesAreUnique() throws {
		let ours = try SDEF(contentsOf: ProjectFiles.appSDEF)
		#expect(ours.repeatedCommandCodes.isEmpty, "\(ours.repeatedCommandCodes)")
		for command in ours.commands {
			#expect(command.repeatedParameterCodes.isEmpty, "\(command.name): \(command.repeatedParameterCodes)")
		}
	}

	@Test func satimageSDEFParses() throws {
		let satimage = try SDEF(contentsOf: ProjectFiles.satimageSDEF)
		#expect(satimage.commands.contains { $0.name == "find text" && $0.code == "SATIFINd" })
		#expect(satimage.recordTypes.contains { $0.name == "matchrecord" && $0.members["mPos"] == "matchPos" })
	}
}

/// Checks the comparison itself, since with only the Diagnostics suite it has nothing to compare yet.
struct SDEFComparisonTests {
	private let satimage = """
		<dictionary>
		<suite name="Text" code="SATI">
			<record-type name="matchrecord" code="mRec"><property name="matchPos" code="mPos"/></record-type>
			<command name="find text" code="SATIFINd">
				<synonym name="ufind text"/>
				<direct-parameter type="text"/>
				<parameter name="in" code="$in "/>
				<parameter name="regexp" code="UsGR"/>
			</command>
		</suite>
		</dictionary>
		"""

	private func differences(_ ours: String) throws -> [String] {
		try SDEF(data: Data(ours.utf8)).differences(from: SDEF(data: Data(satimage.utf8)), ignoringCodesWithPrefixes: ["MTCd"])
	}

	@Test func identicalCopyMatches() throws {
		#expect(try differences(satimage).isEmpty)
	}

	@Test func ownSuiteIsIgnored() throws {
		#expect(try differences(#"<dictionary><command name="mtc_ping" code="MTCdping"/></dictionary>"#).isEmpty)
	}

	@Test func detectsRenamedCommand() throws {
		let ours = satimage.replacingOccurrences(of: #"name="find text""#, with: #"name="findtext""#)
		#expect(try differences(ours).count == 1)
	}

	@Test func allowsExtensionParameters() throws {
		let ours = satimage.replacingOccurrences(of: #"<parameter name="regexp" code="UsGR"/>"#, with: #"<parameter name="regexp" code="UsGR"/><parameter name="dollar references" code="DlRf"/>"#)
		let sdef = try SDEF(data: Data(ours.utf8))
		let reference = try SDEF(data: Data(satimage.utf8))
		#expect(sdef.differences(from: reference, ignoringCodesWithPrefixes: ["MTCd"]).count == 1)
		#expect(sdef.differences(from: reference, ignoringCodesWithPrefixes: ["MTCd"], extensionParameters: ["DlRf"]).isEmpty)
	}

	@Test func detectsChangedParameterCode() throws {
		let ours = satimage.replacingOccurrences(of: #"code="UsGR""#, with: #"code="UsRE""#)
		// Satimage's parameter is missing, and there's one it doesn't have.
		#expect(try differences(ours).count == 2)
	}

	@Test func detectsChangedTypesAndOptionality() throws {
		#expect(try differences(satimage.replacingOccurrences(of: #"<direct-parameter type="text"/>"#, with: #"<direct-parameter type="file"/>"#)).count == 1)
		#expect(try differences(satimage.replacingOccurrences(of: #"code="UsGR"/>"#, with: #"code="UsGR" type="boolean"/>"#)).count == 1)
		#expect(try differences(satimage.replacingOccurrences(of: #"code="$in "/>"#, with: #"code="$in " optional="yes"/>"#)).count == 1)
		#expect(try differences(satimage.replacingOccurrences(of: #"code="SATIFINd">"#, with: #"code="SATIFINd" hidden="yes">"#)).count == 1)
	}

	@Test func findsRepeatedCodes() throws {
		let sdef = try SDEF(data: Data(satimage.replacingOccurrences(of: #"code="UsGR""#, with: #"code="$in ""#).utf8))
		#expect(sdef.commands.first?.repeatedParameterCodes == ["$in "])
		let twice = try SDEF(data: Data(#"<dictionary><command name="a" code="XXXXaaaa"/><command name="b" code="XXXXaaaa"/></dictionary>"#.utf8))
		#expect(twice.repeatedCommandCodes == ["XXXXaaaa"])
	}

	@Test func detectsMissingSynonym() throws {
		let ours = satimage.replacingOccurrences(of: #"<synonym name="ufind text"/>"#, with: "")
		#expect(try differences(ours).count == 1)
	}

	@Test func detectsUnknownCommand() throws {
		#expect(try differences(#"<dictionary><command name="uppercase" code="SATIUPPX"/></dictionary>"#).count == 1)
	}

	@Test func detectsChangedRecordProperty() throws {
		let ours = satimage.replacingOccurrences(of: #"name="matchPos""#, with: #"name="matchPosition""#)
		#expect(try differences(ours).count == 1)
	}
}
