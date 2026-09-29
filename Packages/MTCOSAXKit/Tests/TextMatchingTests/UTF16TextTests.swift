import Foundation
import Testing
@testable import TextMatching

struct UTF16TextTests {
	/// Every kind of character, and lone surrogates (which become U+FFFD, as `String(decoding:as:)` makes them).
	@Test func textMatchesStandardDecoding() {
		let samples: [[UInt16]] = [
			[], Array("abc".utf16), Array("café ☃ 😀 𝄞".utf16), Array("\u{7F}\u{80}\u{7FF}\u{800}\u{FFFF}\u{10000}\u{10FFFF}".utf16),
			[0xD800], [0xDC00], [0x61, 0xD800], [0xD800, 0x62], [0xDC00, 0xD800], [0xD83D, 0xDE00, 0xD83D], [0xD83D, 0xD83D, 0xDE00],
		]
		for units in samples {
			let text = UTF16Text(units: units)
			#expect(text.string == String(decoding: units, as: UTF16.self))
			for start in 0 ... units.count {
				#expect(text[start ..< units.count] == String(decoding: units[start...], as: UTF16.self))
			}
		}
	}
}
