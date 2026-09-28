import Foundation

/// The parts of an SDEF that must match Satimage's for existing scripts to keep working.
struct SDEF {
	struct Command: Equatable {
		var name: String
		var code: String
		var synonyms: Set<String>
		var hasDirectParameter: Bool
		/// Parameter code → name.
		var parameters: [String: String]
	}

	/// A record type or enumeration: its name and its properties' or enumerators' code → name.
	struct NamedCodes: Equatable {
		var name: String
		var code: String
		var members: [String: String]
	}

	var commands: [Command] = []
	var recordTypes: [NamedCodes] = []
	var enumerations: [NamedCodes] = []

	init(contentsOf url: URL) throws {
		try self.init(data: Data(contentsOf: url))
	}

	init(data: Data) throws {
		let document = try XMLDocument(data: data)
		commands = try document.nodes(forXPath: "//command").compactMap { node in
			guard let element = node as? XMLElement, let code = element.attributeValue("code") else {
				return nil
			}
			return Command(
				name: element.attributeValue("name") ?? "",
				code: code,
				synonyms: Set(element.elements(forName: "synonym").compactMap { $0.attributeValue("name") }),
				hasDirectParameter: !element.elements(forName: "direct-parameter").isEmpty,
				parameters: Self.codes(element.elements(forName: "parameter"))
			)
		}
		recordTypes = try document.nodes(forXPath: "//record-type").compactMap { node in
			(node as? XMLElement).flatMap { Self.namedCodes($0, members: "property") }
		}
		enumerations = try document.nodes(forXPath: "//enumeration").compactMap { node in
			(node as? XMLElement).flatMap { Self.namedCodes($0, members: "enumerator") }
		}
	}

	private static func namedCodes(_ element: XMLElement, members: String) -> NamedCodes? {
		guard let code = element.attributeValue("code") else {
			return nil
		}
		return NamedCodes(name: element.attributeValue("name") ?? "", code: code, members: codes(element.elements(forName: members)))
	}

	private static func codes(_ elements: [XMLElement]) -> [String: String] {
		Dictionary(elements.compactMap { element in
			element.attributeValue("code").map { ($0, element.attributeValue("name") ?? "") }
		}, uniquingKeysWith: { first, _ in first })
	}

	/// Differences between this (MTC_OSAX's) SDEF and the reference (Satimage's) for everything
	/// except the suites whose codes start with one of `ownPrefixes`, and the MTC_OSAX extension
	/// parameters in `extensionParameters` (allowed on copied commands) and `commandExtensions` (allowed on the
	/// command with that code).
	func differences(
		from reference: SDEF,
		ignoringCodesWithPrefixes ownPrefixes: [String],
		extensionParameters: Set<String> = [],
		commandExtensions: [String: Set<String>] = [:]
	) -> [String] {
		func isOwn(_ code: String) -> Bool {
			ownPrefixes.contains { code.hasPrefix($0) }
		}
		var differences: [String] = []

		for command in commands where !isOwn(command.code) {
			guard let original = reference.commands.first(where: { $0.code == command.code }) else {
				differences.append("command \"\(command.name)\" (\(command.code)) isn't in the Satimage SDEF")
				continue
			}
			if command.name != original.name {
				differences.append("command \(command.code) is named \"\(command.name)\"; Satimage: \"\(original.name)\"")
			}
			if command.synonyms != original.synonyms {
				differences.append("command \"\(command.name)\" synonyms \(command.synonyms.sorted()); Satimage: \(original.synonyms.sorted())")
			}
			if command.hasDirectParameter != original.hasDirectParameter {
				differences.append("command \"\(command.name)\" direct parameter presence differs from Satimage")
			}
			let allowed = extensionParameters.union(commandExtensions[command.code] ?? [])
			let parameters = command.parameters.filter { !allowed.contains($0.key) }
			if parameters != original.parameters {
				differences.append("command \"\(command.name)\" parameters \(parameters.sorted { $0.key < $1.key }); Satimage: \(original.parameters.sorted { $0.key < $1.key })")
			}
		}

		for (kind, ours, theirs) in [("record-type", recordTypes, reference.recordTypes), ("enumeration", enumerations, reference.enumerations)] {
			for item in ours where !isOwn(item.code) {
				guard let original = theirs.first(where: { $0.code == item.code }) else {
					differences.append("\(kind) \"\(item.name)\" (\(item.code)) isn't in the Satimage SDEF")
					continue
				}
				if item != original {
					differences.append("\(kind) \"\(item.name)\" (\(item.code)) differs from Satimage's \"\(original.name)\"")
				}
			}
		}
		return differences
	}
}

enum ProjectFiles {
	/// The repository root, found from this source file's location.
	static let root = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent() // SDEFConsistencyTests
		.deletingLastPathComponent() // Tests
		.deletingLastPathComponent() // MTCOSAXKit
		.deletingLastPathComponent() // Packages
		.deletingLastPathComponent()

	static let appSDEF = root.appendingPathComponent("MTC_OSAX/MTC_OSAX.sdef")
	static let satimageSDEF = root.appendingPathComponent("SatImageOSAX SDEF/dictionary.sdef")
}

private extension XMLElement {
	func attributeValue(_ name: String) -> String? {
		attribute(forName: name)?.stringValue
	}
}
