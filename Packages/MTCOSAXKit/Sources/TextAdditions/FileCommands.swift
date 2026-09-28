import AppleEventCore
import Foundation

/// `readtext`, `writetext` and `file offset`. Behavior recorded in `Fixtures/TextAdditions/Files`.
extension TextAdditions {
	static func fileCommands() -> [CommandDefinition] {
		[
			CommandDefinition("readtext", code: "SATIRead") { request in
				let source = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
				if let string = try? String(appleEventDescriptor: source), ["http://", "https://"].contains(where: string.lowercased().hasPrefix) {
					throw OSAXError(-1708, "Reading URLs isn't implemented in MTC_OSAX yet.")
				}
				let url = try URL(appleEventDescriptor: source)
				let encoding = try request.parameter("enco", as: String.self).map(FileText.encoding(named:))
				// `redirect` and `timeout` only apply to URLs.
				return try FileText.read(
					url,
					start: request.parameter("strt", as: Int.self),
					length: request.parameter("for ", as: Int.self),
					encoding: encoding
				).text
			},

			CommandDefinition("writetext", code: "SATIWrit") { request in
				let text = try request.requiredDirectParameter(as: String.self)
				// A file reference, or a POSIX or HFS path (Satimage rejected POSIX paths with error 1).
				let url = try request.requiredParameter("to  ", as: URL.self)
				let encoding = try request.parameter("enco", as: String.self).map(FileText.encoding(named:)) ?? .utf8
				let data = try FileText.encode(text, encoding: encoding, missingCharacter: request.parameter("Lssb", as: String.self))
				try FileText.write(data, to: url, append: request.parameter("appe", default: false))
				return nil
			},

			// Never worked in SatimageOSAX (it replied -1708); implemented from its documentation.
			CommandDefinition("file offset", code: "SATIFoff") { request in
				let needle = try request.requiredDirectParameter(as: String.self)
				let url = try request.requiredParameter("in  ", as: URL.self)
				let encoding = try request.parameter("enco", as: String.self).map(FileText.encoding(named:)) ?? .utf8
				return try FileText.offset(
					of: needle,
					in: url,
					from: request.parameter("strt", default: 0),
					encoding: encoding,
					inclusive: request.parameter("incl", default: false)
				)
			},
		]
	}

}
