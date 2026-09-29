import AppleEventCore
import Foundation

/// The hidden "MTC Diagnostics" suite (event class `MTCd`), for checking that the app works end to end.
public enum Diagnostics {
	/// - Parameter version: supplies the text `mtc_version` returns.
	@MainActor
	public static func commands(version: @escaping () -> String) -> [CommandDefinition] {
		[
			CommandDefinition("mtc_ping", code: "MTCdping") { _ in
				"pong"
			},

			CommandDefinition("mtc_version", code: "MTCdvers") { _ in
				version()
			},

			// Returns the direct parameter exactly as received.
			CommandDefinition("mtc_echo", code: "MTCdecho") { request in
				try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
			},

			// Describes the descriptor types and keys the script sent.
			CommandDefinition("mtc_describe", code: "MTCddesc") { request in
				request.descriptor(for: Keyword.directObject).map { DescriptorSnapshot($0).summary }
					?? "(no direct parameter)"
			},

			// mtc_raise_error "message" number n. Error 0 would be no error at all to AppleScript: -50.
			CommandDefinition("mtc_raise_error", code: "MTCdrais") { request in
				let number = try request.requiredParameter(Keyword.errorNumber, as: Int.self)
				let message = try request.directParameter(as: String.self)
				guard number != 0 else {
					throw OSAXError(-50, "The error number can't be 0, which means no error.")
				}
				throw OSAXError(number, message)
			},
		]
	}
}
