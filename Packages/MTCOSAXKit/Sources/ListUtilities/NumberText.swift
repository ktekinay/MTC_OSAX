import Foundation

/// Numbers as text, as the Apple Event Manager's coercion writes them (what SatimageOSAX compared and returned), without
/// the coercion: it took 5.4 µs a number, most of the time to sort a long list of numbers and text. Its form, found
/// by comparing (`NumberTextTests` compares millions of numbers with it):
///
/// - Integers, and reals that are whole numbers below 1e16, as integers: `1.0` is "1", -0 is "0".
/// - Other reals to 16 significant digits, without trailing zeros: 0.1 + 0.2 is "0.3".
/// - Plain from 1e-6 up to 1e16 ("0.000001", "1234.5"); otherwise with an exponent that has no leading zeros, and a
///   space before the number unless it's negative: " 1e+16", " 1.5e-7", "-2.5e+20".
/// - Infinities " INF" and "-INF", and NaN " NAN(000)" or "-NAN(000)" by its sign. (The coercion sometimes left the
///   space out of NaN's text, in a process that had loaded AppleScript, on its first call.)
enum NumberText {
	static func text(_ value: Int64) -> String {
		String(value)
	}

	static func text(_ value: Double) -> String {
		guard value.isFinite else {
			return (value.sign == .minus ? "-" : " ") + (value.isNaN ? "NAN(000)" : "INF")
		}
		if value.rounded(.towardZero) == value, value.magnitude < 1e16 {
			return String(Int64(value))
		}
		// "-d.ddddddddddddddde-xxx": 16 significant digits, rounded.
		var buffer = (Int64(0), Int64(0), Int64(0), Int64(0))
		let formatted = withUnsafeMutableBytes(of: &buffer) { bytes in
			let characters = bytes.baseAddress!.assumingMemoryBound(to: CChar.self)
			_ = withVaList([value]) { vsnprintf(characters, bytes.count, "%.15e", $0) }
			return Array(UnsafeBufferPointer(start: characters, count: strlen(characters)).map { UInt8(bitPattern: $0) })
		}
		let negative = formatted[0] == UInt8(ascii: "-")
		let mantissa = formatted[(negative ? 1 : 0)...].prefix { $0 != UInt8(ascii: "e") }
		var digits = mantissa.filter { $0 != UInt8(ascii: ".") }
		while digits.count > 1, digits.last == UInt8(ascii: "0") {
			digits.removeLast()
		}
		let exponent = Int(String(decoding: formatted[(formatted.firstIndex(of: UInt8(ascii: "e"))! + 1)...], as: UTF8.self))!
		var result: [UInt8] = []
		if (-6 ... 15).contains(exponent) {
			if negative {
				result.append(UInt8(ascii: "-"))
			}
			if exponent < 0 {
				result += Array("0.".utf8) + Array(repeating: UInt8(ascii: "0"), count: -exponent - 1) + digits
			} else {
				let whole = exponent + 1
				result += digits.prefix(whole) + Array(repeating: UInt8(ascii: "0"), count: max(0, whole - digits.count))
				if digits.count > whole {
					result += [UInt8(ascii: ".")] + digits.dropFirst(whole)
				}
			}
		} else {
			result.append(negative ? UInt8(ascii: "-") : UInt8(ascii: " "))
			result.append(digits[0])
			if digits.count > 1 {
				result += [UInt8(ascii: ".")] + digits.dropFirst()
			}
			result += Array("e\(exponent < 0 ? "-" : "+")\(exponent.magnitude)".utf8)
		}
		return String(decoding: result, as: UTF8.self)
	}
}
