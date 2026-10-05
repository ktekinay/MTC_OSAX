import Foundation

/// The parts of an SDEF that must match Satimage's for existing scripts to keep working.
struct SDEF {
	/// A parameter, the direct parameter or a result: what scripts see of it.
	struct Parameter: Equatable, CustomStringConvertible {
		var name: String
		/// The `type` attribute, or the `<type>` elements (with `list="yes"` as `list of`), joined with " | ".
		var type: String
		var optional: Bool
		var hidden: Bool

		var description: String {
			"\(name.isEmpty ? "" : name + ": ")\(type)\(optional ? " (optional)" : "")\(hidden ? " (hidden)" : "")"
		}
	}

	struct Command: Equatable {
		var name: String
		var code: String
		var synonyms: Set<String>
		var hidden: Bool
		var directParameter: Parameter?
		var result: Parameter?
		/// Parameter code → parameter.
		var parameters: [String: Parameter]
		/// Codes used by more than one of its parameters (the dictionary above keeps the first).
		var repeatedParameterCodes: [String]

		var hasDirectParameter: Bool { directParameter != nil }
	}

	/// A record type or enumeration: its name and its properties' or enumerators' code → name.
	struct NamedCodes: Equatable {
		var name: String
		var code: String
		var members: [String: String]
	}

	var commands: [Command] = []
	/// Codes used by more than one command.
	var repeatedCommandCodes: [String] {
		Dictionary(grouping: commands, by: \.code).filter { $0.value.count > 1 }.keys.sorted()
	}
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
			let parameters = element.elements(forName: "parameter")
			let codes = parameters.compactMap { $0.attributeValue("code") }
			return Command(
				name: element.attributeValue("name") ?? "",
				code: code,
				synonyms: Set(element.elements(forName: "synonym").compactMap { $0.attributeValue("name") }),
				hidden: element.attributeValue("hidden") == "yes",
				directParameter: element.elements(forName: "direct-parameter").first.map(Self.parameter),
				result: element.elements(forName: "result").first.map(Self.parameter),
				parameters: Dictionary(parameters.compactMap { element in element.attributeValue("code").map { ($0, Self.parameter(element)) } },
				                       uniquingKeysWith: { first, _ in first }),
				repeatedParameterCodes: Dictionary(grouping: codes, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
			)
		}
		recordTypes = try document.nodes(forXPath: "//record-type").compactMap { node in
			(node as? XMLElement).flatMap { Self.namedCodes($0, members: "property") }
		}
		enumerations = try document.nodes(forXPath: "//enumeration").compactMap { node in
			(node as? XMLElement).flatMap { Self.namedCodes($0, members: "enumerator") }
		}
	}

	private static func parameter(_ element: XMLElement) -> Parameter {
		let types = element.attributeValue("type").map { [$0] }
			?? element.elements(forName: "type").map { ($0.attributeValue("list") == "yes" ? "list of " : "") + ($0.attributeValue("type") ?? "") }
		return Parameter(
			name: element.attributeValue("name") ?? "",
			type: types.joined(separator: " | "),
			optional: element.attributeValue("optional") == "yes",
			hidden: element.attributeValue("hidden") == "yes"
		)
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
	/// command with that code), and the commands in `directParameterExtensions`, whose direct parameter takes
	/// more than Satimage's. Parameters are compared by name, type, optional and hidden.
	func differences(
		from reference: SDEF,
		ignoringCodesWithPrefixes ownPrefixes: [String],
		extensionParameters: Set<String> = [],
		commandExtensions: [String: Set<String>] = [:],
		directParameterExtensions: Set<String> = []
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
			} else if command.directParameter != original.directParameter, !directParameterExtensions.contains(command.code) {
				differences.append("command \"\(command.name)\" direct parameter \(command.directParameter!); Satimage: \(original.directParameter!)")
			}
			if command.result != original.result {
				differences.append("command \"\(command.name)\" result \(command.result.map(String.init(describing:)) ?? "none"); Satimage: \(original.result.map(String.init(describing:)) ?? "none")")
			}
			if command.hidden != original.hidden {
				differences.append("command \"\(command.name)\" is\(command.hidden ? "" : "n't") hidden; in Satimage it is\(original.hidden ? "" : "n't")")
			}
			let allowed = extensionParameters.union(commandExtensions[command.code] ?? [])
			let parameters = command.parameters.filter { !allowed.contains($0.key) }
			for code in Set(parameters.keys).union(original.parameters.keys).sorted() where parameters[code] != original.parameters[code] {
				differences.append("command \"\(command.name)\" parameter \(code): \(parameters[code].map(String.init(describing:)) ?? "missing"); Satimage: \(original.parameters[code].map(String.init(describing:)) ?? "missing")")
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
