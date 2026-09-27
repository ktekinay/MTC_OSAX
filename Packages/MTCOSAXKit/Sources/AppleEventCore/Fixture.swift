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

		var normalized: Reply {
			var copy = self
			copy.result = result?.normalized
			return copy
		}
	}

	public init(name: String, script: String, recordedFrom: String, recordedAt: Date, exchanges: [Exchange]) {
		self.name = name
		self.script = script
		self.recordedFrom = recordedFrom
		self.recordedAt = recordedAt
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

	/// Sends each recorded event to the dispatcher and compares the reply with the recorded one.
	/// Returns a description of each difference; empty means the dispatcher behaves as recorded.
	public func replay(using dispatcher: CommandDispatcher) -> [String] {
		guard !exchanges.isEmpty else {
			return ["\(name): fixture has no recorded events"]
		}
		return exchanges.enumerated().compactMap { index, exchange in
			let expected = exchange.reply.normalized
			let actual = Reply(dispatcher.dispatch(exchange.event.descriptor)).normalized
			guard actual != expected else {
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
