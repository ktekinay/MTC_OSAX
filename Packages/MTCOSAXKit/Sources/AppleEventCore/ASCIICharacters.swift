import Foundation

extension StringProtocol {
	/// Whether the text holds the ASCII character anywhere, byte by byte. `contains(Character)` compares
	/// characters, and `/` followed by a combining mark (or a joiner, or a variation selector) is one character that
	/// isn't `"/"`, though the file system sees a separator: a name of `../\u{301}x` passed the name checks and made
	/// `x́` in the folder above. Checks for syntax characters go through here.
	public func containsASCII(_ character: Unicode.Scalar) -> Bool {
		utf8.contains(UInt8(ascii: character))
	}

	/// Each ASCII `character` replaced by `replacement`, scalar by scalar, for the same reason.
	public func replacingASCII(_ character: Unicode.Scalar, with replacement: Unicode.Scalar) -> String {
		var scalars = String.UnicodeScalarView()
		for scalar in unicodeScalars {
			scalars.append(scalar == character ? replacement : scalar)
		}
		return String(scalars)
	}
}
