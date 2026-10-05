import Foundation

extension FourCharCode {
	/// Creates a code from its four-character form, e.g. `"SATI"` or `"$in "`.
	public init(fourCharString string: String) {
		let bytes = Array(string.data(using: .macOSRoman) ?? Data())
		precondition(bytes.count == 4, "Four-character code must be exactly 4 Mac OS Roman characters: \"\(string)\"")
		self = bytes.reduce(0) { $0 << 8 | FourCharCode($1) }
	}

	/// The four-character form of the code, e.g. `"SATI"`.
	public var fourCharString: String {
		let bytes = [24, 16, 8, 0].map { UInt8((self >> FourCharCode($0)) & 0xFF) }
		return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", self)
	}
}

/// Common parameter keywords.
public enum Keyword {
	public static let directObject = "----"
	public static let errorNumber = "errn"
	public static let errorString = "errs"
}
