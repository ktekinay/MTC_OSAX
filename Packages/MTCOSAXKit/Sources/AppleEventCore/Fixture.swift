import Foundation

/// A recorded run of a script against an app: the Apple events the script sent and the replies it got.
/// Written by `fixture-recorder`, replayed against a dispatcher by the tests.
public struct Fixture: Codable {
	public var name: String
	/// The script body, without the `use application` line.
	public var script: String
	/// The app the fixture was recorded against, e.g. `"SatimageOSAX"`.
	public var recordedFrom: String
	public var recordedAt: Date
	/// Values substituted for `$NAME` in the script when it was recorded, e.g. `FILES` → the folder of input files.
	/// Replays swap these for their own values.
	public var variables: [String: String]?
	/// The time zone the app ran in when recording (e.g. "America/New_York"), since date results depend on it.
	public var timeZone: String?
	public var exchanges: [Exchange]

	public struct Exchange: Codable {
		public var event: DescriptorSnapshot
		public var reply: Reply

		public init(event: DescriptorSnapshot, reply: Reply) {
			self.event = event
			self.reply = reply
		}
	}

	public struct Reply: Codable, Equatable {
		public var result: DescriptorSnapshot?
		public var errorNumber: Int?
		public var errorMessage: String?

		public init(_ reply: AppleEventReply) {
			result = reply.result.map(DescriptorSnapshot.init)
			errorNumber = reply.error?.number
			errorMessage = reply.error?.message
		}

		func replacingText(_ old: String, with new: String) -> Reply {
			var copy = self
			copy.result = result?.replacingText(old, with: new)
			copy.errorMessage = errorMessage?.replacingOccurrences(of: old, with: new)
			return copy
		}

		func matches(_ actual: Reply, realTolerance: Int = 0, absoluteTolerance: Double = 0) -> Bool {
			guard errorNumber == actual.errorNumber, errorMessage == actual.errorMessage else {
				return false
			}
			switch (result, actual.result) {
			case (nil, nil): return true
			case let (expected?, actual?): return expected.matches(actual, realTolerance: realTolerance, absoluteTolerance: absoluteTolerance)
			default: return false
			}
		}

		var normalized: Reply {
			var copy = self
			copy.result = result?.normalized
			return copy
		}
	}

	public init(
		name: String,
		script: String,
		recordedFrom: String,
		recordedAt: Date,
		variables: [String: String]? = nil,
		timeZone: String? = nil,
		exchanges: [Exchange]
	) {
		self.name = name
		self.script = script
		self.recordedFrom = recordedFrom
		self.recordedAt = recordedAt
		self.variables = variables
		self.timeZone = timeZone
		self.exchanges = exchanges
	}

	// MARK: Files

	public init(contentsOf url: URL) throws {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		self = try decoder.decode(Fixture.self, from: Data(contentsOf: url))
	}

	public func write(to url: URL) throws {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		try encoder.encode(self).write(to: url, options: .atomic)
	}

	// MARK: Replay

	/// Sends each recorded event to the dispatcher, in order, and compares the reply with the recorded one.
	/// `variables` gives this run's value for each variable the fixture was recorded with; recorded values
	/// are replaced in the events and the expected replies. Returns a description of each difference;
	/// empty means the dispatcher behaves as recorded. `realTolerance` lets reals differ by that many units in the
	/// last place (math libraries differ slightly between Intel and Apple silicon), or by `absoluteTolerance`.
	@MainActor
	public func replay(using dispatcher: CommandDispatcher, variables current: [String: String] = [:], realTolerance: Int = 0, absoluteTolerance: Double = 0) -> [String] {
		guard !exchanges.isEmpty else {
			return ["\(name): fixture has no recorded events"]
		}
		// Longest recorded values first, so a path isn't partly replaced by a shorter one it contains.
		var substitutions: [(old: String, new: String)] = []
		for (variable, recorded) in (variables ?? [:]).sorted(by: { $0.value.count > $1.value.count }) {
			guard let value = current[variable] else {
				return ["\(name): replay needs a value for $\(variable)"]
			}
			// Recorded values are replaced in every text, error messages too, so they must be distinctive: a path
			// or a URL, not something as short as "a" that could turn up anywhere.
			guard recorded.hasPrefix("/") || recorded.contains("://") else {
				return ["\(name): $\(variable) was recorded as \"\(recorded)\", which isn't a path or URL to replace safely"]
			}
			substitutions.append((recorded, value))
		}
		// Property list references (CFRefs) differ between apps: each one the app returns in place of a recorded one
		// replaces it in later events and replies.
		var references: [String: DescriptorSnapshot] = [:]
		let volume = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? ""
		return exchanges.enumerated().compactMap { index, exchange in
			var event = exchange.event
			var reply = exchange.reply
			for substitution in substitutions {
				event = event.replacingText(substitution.old, with: substitution.new)
					.replacingHFSPath(substitution.old, with: substitution.new, volume: volume)
				reply = reply.replacingText(substitution.old, with: substitution.new)
			}
			event = event.replacingReferences(references)
			// A command that changes files is given only paths inside this run's folders: a fixture holding a path
			// in another spelling than its variables' (an HFS path, say) would otherwise act on the real place.
			if let outside = event.pathOutside(current.values.map { $0 }) {
				return "\(name) event \(index + 1) (\(exchange.event.eventClass ?? "")\(exchange.event.eventID ?? "")) names \(outside), outside the replay's folders; not sent."
			}
			let actual = Reply(dispatcher.dispatch(event.descriptor)).normalized
			if let recorded = reply.result, let result = actual.result {
				recorded.normalized.collectReferences(from: result, into: &references)
			}
			reply.result = reply.result?.replacingReferences(references)
			let expected = reply.normalized
			guard !expected.matches(actual, realTolerance: realTolerance, absoluteTolerance: absoluteTolerance) else {
				return nil
			}
			return """
				\(name) event \(index + 1) (\(exchange.event.eventClass ?? "")\(exchange.event.eventID ?? "")):
				  expected \(expected.summary)
				  actual   \(actual.summary)
				"""
		}
	}
}

extension DescriptorSnapshot {
	/// Commands that make, change or delete files, whose file parameters a replay keeps inside its folders.
	static let fileChangingCommands: Set<String> = [
		"QuomNewF", "QuomMkDi", "QuomRenF", "Quomchmd", "QuomCopy", "QuomMove", "QuomRemo", "Quommkst", "Quommkdt", "QuomSymL",
		"SATIWrit", "SATISYNC", "XML save", "XML c14n", "XML xslt", "PLSTsave", "PLSTJSON", "MTCpTYML", "MTCpTTML",
	]

	/// For an event of a command that changes files, the first file parameter (a file reference, or text that is an
	/// absolute POSIX, `file:` or HFS path) that isn't inside one of `folders`; nil if every one is, or the command
	/// doesn't change files. Names and relative paths are left to the command's `from`, which is checked itself.
	func pathOutside(_ folders: [String]) -> String? {
		guard let eventClass, let eventID, Self.fileChangingCommands.contains(eventClass + eventID) else { return nil }
		func outside(_ value: DescriptorSnapshot) -> String? {
			if let items = value.items { return items.lazy.compactMap(outside).first }
			if value.hex != nil, ["alis", "fsrf", "bmrk"].contains(value.type) { return "a \(value.type) reference" }
			guard let text = value.text, ["furl", "utxt", "TEXT", "utf8", "ut16"].contains(value.type) else { return nil }
			// As the commands read it: a POSIX, `~`, `file:` or HFS path (on a mounted volume: other text with
			// colons, a JavaScript function say, isn't a path). Anything else is a name for `from`.
			guard value.type == "furl" || !URL.isRelativeScriptPath(text), let path = (try? URL(scriptPath: text))?.path else { return nil }
			let resolved = Self.canonicalPath(path)
			return canonicalFolders.contains { resolved == $0 || resolved.hasPrefix($0 + "/") } ? nil : text
		}
		let canonicalFolders = folders.map(Self.canonicalPath)
		return fields?.lazy.compactMap { outside($0.value) }.first
	}

	/// A path with `.` and `..` taken out and `/private` taken off the front (`/private/tmp` and `/tmp` are one
	/// folder), done by hand: Foundation's standardizing does this for a path that exists and not for one that
	/// doesn't yet.
	static func canonicalPath(_ path: String) -> String {
		var components: [Substring] = []
		for component in path.split(separator: "/") {
			switch component {
			case ".": break
			case "..": if !components.isEmpty { components.removeLast() }
			default: components.append(component)
			}
		}
		if components.first == "private", components.count > 1 { components.removeFirst() }
		return "/" + components.joined(separator: "/")
	}

	/// The same value with the HFS spelling of `old` (`Volume:a:b` for `/a/b`, whatever the volume was called when
	/// it was recorded) replaced by that of `new` on this Mac's startup volume.
	func replacingHFSPath(_ old: String, with new: String, volume: String) -> DescriptorSnapshot {
		var copy = self
		if let text, type != "furl" {
			let oldHFS = ":" + old.split(separator: "/").joined(separator: ":")
			if let range = text.range(of: oldHFS), !text[..<range.lowerBound].isEmpty, !text[..<range.lowerBound].contains(":"),
			   range.upperBound == text.endIndex || text[range.upperBound] == ":"
			{
				copy.text = volume + ":" + new.split(separator: "/").joined(separator: ":") + text[range.upperBound...]
			}
		}
		copy.items = items?.map { $0.replacingHFSPath(old, with: new, volume: volume) }
		copy.fields = fields?.map { Field(key: $0.key, value: $0.value.replacingHFSPath(old, with: new, volume: volume)) }
		return copy
	}
}

extension Fixture.Reply {
	public var summary: String {
		if let errorNumber {
			return "error \(errorNumber)" + (errorMessage.map { " \"\($0)\"" } ?? "")
		}
		return result?.summary ?? "no result"
	}
}

// MARK: Recording

extension Fixture {
	/// Why a case can't have this name (nil if it can): its fixture is `<name>.json` next to the cases file, so it
	/// must be a file name, not a path or hidden, and not the cases file's own (a case named `cases` overwrote
	/// cases.json). On a case-insensitive disk, case doesn't count.
	public static func problem(withCaseName name: String, casesFile: URL) -> String? {
		if name.isEmpty || name.containsASCII("/") || name.hasPrefix(".") {
			return "Case name \"\(name)\" can't be a file name: no \"/\", and not starting with \".\"."
		}
		if name.lowercased() == casesFile.deletingPathExtension().lastPathComponent.lowercased() {
			return "Case name \"\(name)\" would write over \(casesFile.lastPathComponent)."
		}
		return nil
	}

	/// Text as the inside of an AppleScript string literal (a quote or backslash in an app's name or a variable's
	/// value broke the script).
	public static func appleScriptStringContents(_ text: String) -> String {
		text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
	}
}
