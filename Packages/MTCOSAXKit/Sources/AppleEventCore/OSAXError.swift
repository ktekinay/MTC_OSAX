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

	/// The Apple Event Manager's error, unless `status` is `noErr`.
	public static func check(_ status: OSErr) throws {
		if status != noErr {
			throw OSAXError(Int(status))
		}
	}

	/// -2700: a general failure with a message.
	public static func general(_ message: String) -> OSAXError {
		OSAXError(-2700, message)
	}
}

extension OSAXError {
	/// A file operation that failed: `what` couldn't be done, and why, with the POSIX number underneath (13 for
	/// permission, and so on; -43 for a missing item, as the file commands give) or else `fallback`.
	public static func file(_ error: Error, _ what: String, fallback: Int = -1) -> OSAXError {
		let nsError = error as NSError
		let posix = [nsError, nsError.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap { $0 }
			.first { $0.domain == NSPOSIXErrorDomain }
		let reason = (posix ?? nsError).localizedDescription
		let number = posix.map { $0.code == Int(ENOENT) ? -43 : $0.code } ?? fallback
		return OSAXError(number, "Couldn’t \(what): \(reason)")
	}
}

extension Int32 {
	/// A length for a C function that takes an `int`: error -50 for 2 GB or more, which `Int32(_:)` would trap on.
	public init(length: Int) throws {
		guard let value = Int32(exactly: length) else {
			throw OSAXError(-50, "The text or data is too large (2 GB or more).")
		}
		self = value
	}
}
