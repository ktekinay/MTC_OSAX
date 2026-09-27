import Foundation

/// An error returned to the calling script as `errn` (and optionally `errs`) in the reply.
///
/// Leave `message` nil for standard Apple event errors so AppleScript supplies its usual
/// text (e.g. "Can’t make some data into the expected type."), as it does for Satimage.
public struct OSAXError: Error, Equatable, CustomStringConvertible {
	public var number: Int
	public var message: String?

	public init(_ number: Int, _ message: String? = nil) {
		self.number = number
		self.message = message
	}

	public var description: String {
		message.map { "\($0) (\(number))" } ?? "error \(number)"
	}

	/// -1700: a parameter couldn't be coerced to the required type.
	public static let coercionFailed = OSAXError(-1700)

	/// -1701: a required parameter is missing.
	public static let missingParameter = OSAXError(-1701)

	/// -1708: no handler is registered for the event.
	public static let eventNotHandled = OSAXError(-1708)

	/// -50: a parameter has an invalid value.
	public static let parameterError = OSAXError(-50)

	/// -2700: a general failure with a message.
	public static func general(_ message: String) -> OSAXError {
		OSAXError(-2700, message)
	}
}
