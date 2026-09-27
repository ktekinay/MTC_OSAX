import AppleEventCore
import Foundation
import TextMatching

/// A replacement template as used by `change … into`, `find text … using` and `filter text … key/using`.
///
/// Satimage's syntax (recorded in the fixtures):
/// - `\0`–`\9`: the whole match or a numbered group (one digit only; `\10` is group 1 then "0"). An unmatched
///   group gives "". A group number above the pattern's group count is error -207.
/// - `\k<name>`: a named group; `\k<12>`: a numbered group. Unclosed: -208. (Satimage inserted the whole
///   match whatever the name.)
/// - `\t`, `\n`, `\r`, `\\`: tab, linefeed, return, backslash.
/// - `\uXXXX`: the UTF-16 unit with exactly four hex digits.
/// - Any other character after a backslash, or a trailing backslash: error -208.
/// - Everything else, including `$`, is literal.
///
/// With dollar references (an MTC_OSAX extension), also `$0`–`$9`, `${12}` (any group number), `${name}`
/// (a named group) and `$$`.
struct Template {
	enum Part: Equatable {
		case literal(String)
		case group(Int)
		case namedGroup(String)
	}

	let parts: [Part]

	static let tooBigBackreference = OSAXError(-207)
	static let invalidBackreference = OSAXError(-208)

	init(_ template: String, dollarReferences: Bool = false) throws {
		var parts: [Part] = []
		var literal: [UInt16] = []
		let units = Array(template.utf16)
		var index = 0

		func flushLiteral() {
			if !literal.isEmpty {
				parts.append(.literal(String(decoding: literal, as: UTF16.self)))
				literal = []
			}
		}
		func unit(at offset: Int) -> UInt16? {
			offset < units.count ? units[offset] : nil
		}
		func ascii(_ character: Character) -> UInt16 {
			UInt16(character.asciiValue!)
		}
		func digit(_ unit: UInt16?) -> Int? {
			guard let unit, unit >= ascii("0"), unit <= ascii("9") else { return nil }
			return Int(unit - ascii("0"))
		}

		while index < units.count {
			let current = units[index]
			if current == ascii("\\") {
				guard let next = unit(at: index + 1) else {
					throw Self.invalidBackreference
				}
				if let number = digit(next) {
					flushLiteral()
					parts.append(.group(number))
					index += 2
					continue
				}
				switch Character(Unicode.Scalar(next)!) {
				case "t": literal.append(ascii("\t"))
				case "n": literal.append(ascii("\n"))
				case "r": literal.append(ascii("\r"))
				case "\\": literal.append(ascii("\\"))
				case "u":
					let hex = (index + 2 ..< index + 6).compactMap { unit(at: $0) }
					guard hex.count == 4,
					      let value = UInt16(String(decoding: hex, as: UTF16.self), radix: 16)
					else {
						throw Self.invalidBackreference
					}
					literal.append(value)
					index += 6
					continue
				case "k":
					guard unit(at: index + 2) == ascii("<"),
					      let close = units[(index + 3)...].firstIndex(of: ascii(">"))
					else {
						throw Self.invalidBackreference
					}
					flushLiteral()
					let name = String(decoding: units[(index + 3) ..< close], as: UTF16.self)
					if let number = Int(name), name.allSatisfy(\.isASCII) {
						parts.append(.group(number))
					} else {
						parts.append(.namedGroup(name))
					}
					index = close + 1
					continue
				default:
					throw Self.invalidBackreference
				}
				index += 2
			} else if dollarReferences, current == ascii("$"), let next = unit(at: index + 1) {
				if let number = digit(next) {
					flushLiteral()
					parts.append(.group(number))
					index += 2
				} else if next == ascii("$") {
					literal.append(ascii("$"))
					index += 2
				} else if next == ascii("{"), let close = units[(index + 2)...].firstIndex(of: ascii("}")) {
					flushLiteral()
					let name = String(decoding: units[(index + 2) ..< close], as: UTF16.self)
					// `${12}` is a group number (the only way to reach groups above 9), anything else a name.
					if let number = Int(name), name.allSatisfy(\.isASCII) {
						parts.append(.group(number))
					} else {
						parts.append(.namedGroup(name))
					}
					index = close + 1
				} else {
					literal.append(current)
					index += 1
				}
			} else {
				literal.append(current)
				index += 1
			}
		}
		flushLiteral()
		self.parts = parts
	}

	/// The template's text for one match.
	func expand(_ match: TextMatch, in text: UTF16Text, groupCount: Int, namedGroups: [String: [Int]] = [:]) throws -> String {
		var result = ""
		for part in parts {
			switch part {
			case let .literal(string):
				result += string
			case let .group(number):
				guard number <= groupCount else {
					throw Self.tooBigBackreference
				}
				result += match.text(ofGroup: number, in: text)
			case let .namedGroup(name):
				// The last group with that name that took part in the match, as Ruby does.
				guard let numbers = namedGroups[name] else {
					throw OSAXError(-217) // ONIGERR_UNDEFINED_NAME_REFERENCE
				}
				let matched = numbers.last { match.range(ofGroup: $0) != nil }
				result += matched.map { match.text(ofGroup: $0, in: text) } ?? ""
			}
		}
		return result
	}
}
