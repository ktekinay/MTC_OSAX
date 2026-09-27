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

		func matches(_ actual: Reply) -> Bool {
			guard errorNumber == actual.errorNumber, errorMessage == actual.errorMessage else {
				return false
			}
			switch (result, actual.result) {
			case (nil, nil): return true
			case let (expected?, actual?): return expected.matches(actual)
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
	/// empty means the dispatcher behaves as recorded.
	public func replay(using dispatcher: CommandDispatcher, variables current: [String: String] = [:]) -> [String] {
		guard !exchanges.isEmpty else {
			return ["\(name): fixture has no recorded events"]
		}
		// Longest recorded values first, so a path isn't partly replaced by a shorter one it contains.
		var substitutions: [(old: String, new: String)] = []
		for (variable, recorded) in (variables ?? [:]).sorted(by: { $0.value.count > $1.value.count }) {
			guard let value = current[variable] else {
				return ["\(name): replay needs a value for $\(variable)"]
			}
			substitutions.append((recorded, value))
		}
		return exchanges.enumerated().compactMap { index, exchange in
			var event = exchange.event
			var reply = exchange.reply
			for substitution in substitutions {
				event = event.replacingText(substitution.old, with: substitution.new)
				reply = reply.replacingText(substitution.old, with: substitution.new)
			}
			let expected = reply.normalized
			let actual = Reply(dispatcher.dispatch(event.descriptor)).normalized
			guard !expected.matches(actual) else {
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

extension Fixture.Reply {
	public var summary: String {
		if let errorNumber {
			return "error \(errorNumber)" + (errorMessage.map { " \"\($0)\"" } ?? "")
		}
		return result?.summary ?? "no result"
	}
}
