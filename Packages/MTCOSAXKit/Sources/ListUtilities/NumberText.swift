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
		// "-d.ddddddddddddddde-xxx": 16 significant digits, rounded, read and rewritten in one buffer (an array for each
		// step took 757 ms for a million reals; this takes about 400, most of it `vsnprintf`'s).
		return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 96) { buffer in
			let formatted = buffer.baseAddress!, digits = formatted + 32, text = formatted + 48
			let length = withVaList([value]) { vsnprintf(UnsafeMutableRawPointer(formatted).assumingMemoryBound(to: CChar.self), 32, "%.15e", $0) }
			let negative = formatted[0] == UInt8(ascii: "-")
			var position = negative ? 1 : 0
			var count = 0
			while formatted[position] != UInt8(ascii: "e") {
				if formatted[position] != UInt8(ascii: ".") {
					digits[count] = formatted[position]
					count += 1
				}
				position += 1
			}
			while count > 1, digits[count - 1] == UInt8(ascii: "0") {
				count -= 1
			}
			let exponentIsNegative = formatted[position + 1] == UInt8(ascii: "-")
			var exponent = 0
			for index in position + 2 ..< Int(length) {
				exponent = exponent * 10 + Int(formatted[index] - UInt8(ascii: "0"))
			}
			if exponentIsNegative {
				exponent = -exponent
			}
			var written = 0
			func write(_ byte: UInt8) {
				text[written] = byte
				written += 1
			}
			func write(digitsIn range: Range<Int>) {
				for index in range { write(digits[index]) }
			}
			if (-6 ... 15).contains(exponent) {
				if negative {
					write(UInt8(ascii: "-"))
				}
				if exponent < 0 {
					write(UInt8(ascii: "0"))
					write(UInt8(ascii: "."))
					for _ in 0 ..< -exponent - 1 { write(UInt8(ascii: "0")) }
					write(digitsIn: 0 ..< count)
				} else {
					let whole = exponent + 1
					write(digitsIn: 0 ..< min(whole, count))
					for _ in count ..< max(count, whole) { write(UInt8(ascii: "0")) }
					if count > whole {
						write(UInt8(ascii: "."))
						write(digitsIn: whole ..< count)
					}
				}
			} else {
				write(negative ? UInt8(ascii: "-") : UInt8(ascii: " "))
				write(digits[0])
				if count > 1 {
					write(UInt8(ascii: "."))
					write(digitsIn: 1 ..< count)
				}
				write(UInt8(ascii: "e"))
				write(exponent < 0 ? UInt8(ascii: "-") : UInt8(ascii: "+"))
				for byte in String(exponent.magnitude).utf8 { write(byte) }
			}
			return String(decoding: UnsafeBufferPointer(start: text, count: written), as: UTF8.self)
		}
	}
}
