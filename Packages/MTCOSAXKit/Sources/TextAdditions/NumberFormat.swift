import Foundation

/// Satimage's `format` number-format language. Recorded from SatimageOSAX (`Fixtures/TextAdditions/NumberFormat` and
/// `NumberFormatRandom`) where it worked, and following its dictionary entry where it didn't
/// (`Fixtures/TextAdditionsFixes`):
///
/// - A format has up to three sections separated by `;`: for numbers ≥ 0 and < 0 with two, or > 0, < 0 and = 0
///   with three. A negative number in its own section is shown without a minus sign. An empty section uses the
///   first one; an empty first section is `#.######`. A zero section with no digit placeholders is just its text. (Satimage rejected three sections and used the first section's layout for all of them.)
/// - A section is literal text, then the number, then literal text. Literal text is any character other than
///   `#`, `0`, `.` and `,`, or anything in single quotes (`''` is a quote). `%` anywhere multiplies by 100.
///   An unquoted `^` is a space, as documented (Satimage printed `^`).
/// - The number: integer placeholders (`#`s then `0`s, with commas for grouping), then optionally `.` and decimal
///   placeholders (`0`s then `#`s), then optionally an exponent `E+0…` or `E0…`. A `0` digit is always shown, a `#`
///   digit only if needed. An `E` after the number with no `0`s is dropped.
/// - Grouping: the last group has as many digits as placeholders after the last comma, the others as many as
///   between the last two commas (so `,,#0,0` groups 143294843 as 14,32,94,84,3).
/// - Values are scaled to the decimals shown and rounded half to even, in double precision.
/// - With one section, a negative value (including -0) gets a leading `-`, even if it rounds to zero.
/// - An empty format is `#.######`. A format that breaks these rules is invalid. (Satimage silently reused the
///   previous valid format.)
/// - With `underflow test`, a nonzero number that would show as zero is shown in scientific notation.
struct NumberFormat: Equatable {
	/// The number's layout, from the first section.
	struct Shape: Equatable {
		/// All integer placeholders, and how many are `0`.
		var integerPlaceholders = 0
		var minimumIntegerDigits = 0
		var lastGroupSize = 0
		var otherGroupSize = 0
		var hasDecimalPoint = false
		/// All decimal placeholders, and how many are `0`.
		var decimalPlaceholders = 0
		var minimumDecimals = 0
		var exponent: Exponent?
	}

	struct Exponent: Equatable {
		/// `E+0`: a `+` for positive exponents; `E0`: a sign only when negative.
		var alwaysSign: Bool
		var minimumDigits: Int
	}

	/// A section's literal text around the number.
	struct Literals: Equatable {
		var prefix = ""
		var suffix = ""
		/// Multiplies by 100.
		var percent: Bool { (prefix + suffix).contains("%") }
	}

	struct Section: Equatable {
		var shape: Shape
		var literals: Literals
		/// Nothing at all between the semicolons: the first section is used instead.
		var isEmpty: Bool
	}

	/// One to three sections: for all values; for ≥ 0 and < 0; or for > 0, < 0 and = 0.
	var sections: [Section]

	/// The format Satimage uses for an empty format string.
	static let empty = NumberFormat("#.######")!

	/// Parses a format; nil if Satimage would reject it.
	init?(_ format: String) {
		guard !format.isEmpty else {
			self = .empty
			return
		}
		guard let parts = Self.sections(of: format), parts.count <= 3 else {
			return nil
		}
		var sections: [Section] = []
		for part in parts {
			guard let (shape, literals) = Self.parse(Array(part)) else {
				return nil
			}
			sections.append(Section(shape: shape, literals: literals, isEmpty: part.isEmpty))
		}
		// An empty first section is the empty format's; it's the fallback for the other empty sections.
		if sections[0].isEmpty, sections.count > 1 {
			sections[0] = NumberFormat.empty.sections[0]
		}
		self.sections = sections
	}

	// MARK: Parsing

	/// Splits on `;` outside quotes. Nil if a quote is left open.
	private static func sections(of format: String) -> [String]? {
		var sections: [String] = []
		var current = ""
		var quoted = false
		for character in format {
			if character == "'" {
				quoted.toggle()
			}
			if character == ";" && !quoted {
				sections.append(current)
				current = ""
			} else {
				current.append(character)
			}
		}
		guard !quoted else {
			return nil
		}
		return sections + [current]
	}

	private static let numberCharacters: Set<Character> = ["#", "0", ".", ","]

	private static func parse(_ characters: [Character]) -> (Shape, Literals)? {
		var shape = Shape()
		var literals = Literals()
		var index = 0

		/// Quoted text starting at `index`, which is a quote; `''` inside is a quote. Nil if never closed.
		func readQuoted() -> String? {
			var text = ""
			index += 1
			while index < characters.count {
				if characters[index] == "'" {
					if index + 1 < characters.count, characters[index + 1] == "'" {
						text.append("'")
						index += 2
						continue
					}
					index += 1
					return text
				}
				text.append(characters[index])
				index += 1
			}
			return nil
		}

		// Prefix: literal text up to the first number character.
		while index < characters.count, !numberCharacters.contains(characters[index]) {
			if characters[index] == "'" {
				guard let quoted = readQuoted() else { return nil }
				literals.prefix += quoted
			} else {
				literals.prefix.append(characters[index] == "^" ? " " : characters[index])
				index += 1
			}
		}

		var number = ""
		while index < characters.count, numberCharacters.contains(characters[index]) {
			number.append(characters[index])
			index += 1
		}
		guard applyNumber(number, to: &shape) else {
			return nil
		}

		// After the number, E with an optional + and one or more 0s is the exponent; E alone is dropped.
		if !number.isEmpty, index < characters.count, characters[index] == "E" {
			guard !number.contains(",") else {
				return nil // grouping and an exponent together
			}
			var lookahead = index + 1
			let alwaysSign = lookahead < characters.count && characters[lookahead] == "+"
			if alwaysSign { lookahead += 1 }
			let zeros = characters[min(lookahead, characters.count)...].prefix { $0 == "0" }.count
			if zeros > 0 {
				shape.exponent = Exponent(alwaysSign: alwaysSign, minimumDigits: zeros)
				index = lookahead + zeros
			} else {
				index += 1
			}
		}

		// Suffix: literal text; a number character here makes the format invalid.
		while index < characters.count {
			if characters[index] == "'" {
				guard let quoted = readQuoted() else { return nil }
				literals.suffix += quoted
			} else if numberCharacters.contains(characters[index]) {
				return nil
			} else {
				literals.suffix.append(characters[index] == "^" ? " " : characters[index])
				index += 1
			}
		}
		return (shape, literals)
	}

	/// Reads the placeholders; false if they're out of order.
	private static func applyNumber(_ number: String, to shape: inout Shape) -> Bool {
		let parts = number.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count <= 2 else {
			return false
		}
		// Integer part: #s then 0s; commas anywhere except at the end.
		let integer = parts[0]
		let integerDigits = integer.filter { $0 != "," }
		guard !integer.hasSuffix(","), isOrdered(integerDigits, first: "#", then: "0") else {
			return false
		}
		shape.integerPlaceholders = integerDigits.count
		shape.minimumIntegerDigits = integerDigits.filter { $0 == "0" }.count
		let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
		if groups.count > 1 {
			shape.lastGroupSize = groups[groups.count - 1].count
			shape.otherGroupSize = shape.lastGroupSize
			if groups.count > 2 {
				// Two commas with nothing between them: invalid.
				guard !groups[groups.count - 2].isEmpty else {
					return false
				}
				shape.otherGroupSize = groups[groups.count - 2].count
			}
		}
		// Decimal part: 0s then #s, no commas.
		if parts.count == 2 {
			let decimals = parts[1]
			guard !decimals.contains(","), isOrdered(decimals, first: "0", then: "#") else {
				return false
			}
			shape.hasDecimalPoint = true
			shape.decimalPlaceholders = decimals.count
			shape.minimumDecimals = decimals.filter { $0 == "0" }.count
		}
		return true
	}

	/// Whether `text` is some `first`s followed by some `then`s.
	private static func isOrdered<Text: StringProtocol>(_ text: Text, first: Character, then: Character) -> Bool {
		!text.drop { $0 == first }.contains(first)
	}

	// MARK: Formatting

	/// - Parameter underflowTest: show a nonzero number that would appear as zero in scientific notation.
	func format(_ value: Double, underflowTest: Bool = false) -> String {
		let negative = value.sign == .minus
		let index: Int
		switch sections.count {
		case 3: index = value == 0 ? 2 : (negative ? 1 : 0)
		case 2: index = negative ? 1 : 0
		default: index = 0
		}
		// A negative number in its own section has no minus sign; one that falls back to the first section does.
		let ownSection = index > 0 && !sections[index].isEmpty
		let section = ownSection ? sections[index] : sections[0]
		// A zero section with no digit placeholders is just its text ("#;-#;'zero'").
		if index == 2, ownSection, section.shape.integerPlaceholders == 0, !section.shape.hasDecimalPoint {
			return section.literals.prefix + section.literals.suffix
		}
		let text = Self.format(abs(value), section, underflowTest: underflowTest)
		return negative && !ownSection && !(sections.count == 3 && value == 0) ? "-" + text : text
	}

	private static func format(_ magnitude: Double, _ section: Section, underflowTest: Bool) -> String {
		let value = section.literals.percent ? magnitude * 100 : magnitude
		// `%` can overflow a finite number; Satimage showed the result as ∞ between the section's literals.
		guard value.isFinite else {
			return section.literals.prefix + (value.isNaN ? "NaN" : "∞") + section.literals.suffix
		}
		var shape = section.shape
		if underflowTest, shape.exponent == nil, value != 0, showsAsZero(value, shape) {
			shape.exponent = Exponent(alwaysSign: true, minimumDigits: 2)
			shape.integerPlaceholders = 1
			shape.minimumIntegerDigits = 1
			shape.lastGroupSize = 0
			shape.otherGroupSize = 0
		}
		let number = shape.exponent.map { scientific(value, shape, $0) } ?? fixed(value, shape)
		return section.literals.prefix + number + section.literals.suffix
	}

	/// Whether `value` rounds to zero at the shape's decimals.
	private static func showsAsZero(_ value: Double, _ shape: Shape) -> Bool {
		let (integer, fraction) = roundedDigits(value, decimals: shape.decimalPlaceholders)
		return integer == "0" && !fraction.contains { $0 != "0" }
	}

	// MARK: Fixed notation

	/// The digits of `value` rounded half to even to `decimals` places, split at the point. As Satimage does, the
	/// fraction is rounded from the scaled value minus the scaled integer part (so 99.995 to 2 places is 100.00),
	/// and the integer part is printed exactly (so 1e20 isn't disturbed by scaling past double precision).
	private static func roundedDigits(_ value: Double, decimals: Int) -> (integer: String, fraction: String) {
		let scale = pow(10, Double(decimals))
		// Past 2⁵³ the scaled value has lost digits (and past 10³⁰⁸ it's infinite, which printed "nan"): printf's
		// conversion is exact there.
		guard abs(value) * scale < 9e15 else {
			let text = String(format: "%.\(decimals)f", abs(value))
			let parts = text.split(separator: ".", omittingEmptySubsequences: false)
			return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
		}
		var integer = value.rounded(.towardZero)
		let scaledFraction = value * scale - integer * scale
		var fraction = scaledFraction.rounded(.down)
		// Half to even on the whole number: its last digit is the fraction's, or the integer's with no decimals.
		let remainder = scaledFraction - fraction
		let lastDigit = decimals > 0 ? fraction : integer
		if remainder > 0.5 || (remainder == 0.5 && lastDigit.truncatingRemainder(dividingBy: 2) != 0) {
			fraction += 1
		}
		if fraction >= scale {
			integer += 1
			fraction -= scale
		}
		let fractionDigits = decimals == 0 ? "" : String(format: "%0\(decimals).0f", fraction)
		return (String(format: "%.0f", integer), fractionDigits)
	}

	private static func fixed(_ value: Double, _ shape: Shape) -> String {
		let (integerDigits, allDecimals) = roundedDigits(value, decimals: shape.decimalPlaceholders)
		// With no integer placeholders, at least one decimal is shown.
		let minimumDecimals = shape.integerPlaceholders == 0 && shape.decimalPlaceholders > 0
			? max(shape.minimumDecimals, 1) : shape.minimumDecimals
		var decimals = Substring(allDecimals)
		while decimals.count > minimumDecimals, decimals.last == "0" {
			decimals = decimals.dropLast()
		}
		// A zero integer part is left out when decimals are always shown ("#.0" gives ".5").
		var integer = integerDigits
		if integer == "0", shape.minimumIntegerDigits == 0, minimumDecimals > 0, !decimals.isEmpty {
			integer = ""
		}
		if integer.count < shape.minimumIntegerDigits {
			integer = String(repeating: "0", count: shape.minimumIntegerDigits - integer.count) + integer
		}
		integer = grouped(integer, last: shape.lastGroupSize, others: shape.otherGroupSize)
		return withPoint(integer, decimals, shape)
	}

	/// The integer and decimals joined; a format's point with no decimal placeholders is always shown.
	private static func withPoint<Decimals: StringProtocol>(_ integer: String, _ decimals: Decimals, _ shape: Shape) -> String {
		if !decimals.isEmpty {
			return integer + "." + decimals
		}
		return shape.hasDecimalPoint && shape.decimalPlaceholders == 0 ? integer + "." : integer
	}

	private static func grouped(_ digits: String, last: Int, others: Int) -> String {
		guard last > 0, digits.count > last else {
			return digits
		}
		var groups = [digits.suffix(last)]
		var rest = digits.dropLast(last)
		while !rest.isEmpty {
			groups.insert(rest.suffix(others), at: 0)
			rest = rest.dropLast(others)
		}
		return groups.joined(separator: ",")
	}

	// MARK: Scientific notation

	private static func scientific(_ value: Double, _ shape: Shape, _ format: Exponent) -> String {
		let mantissa: String
		var exponent: Int
		// Significant digits: the 0 placeholders plus decimal #s. With none, every digit is shown.
		let significant = shape.minimumIntegerDigits + shape.decimalPlaceholders

		if significant == 0 {
			let step = max(shape.integerPlaceholders, 1)
			exponent = value == 0 ? 0 : floorDivide(decimalExponent(value), by: step) * step
			let digits = shortestDigits(value, pointAfter: value == 0 ? 1 : decimalExponent(value) - exponent + 1)
			mantissa = withPoint(digits.integer, digits.fraction, shape)
		} else if shape.integerPlaceholders == 0 {
			// No integer placeholders: the mantissa is 0.xxx.
			exponent = value == 0 ? 0 : decimalExponent(value) + 1
			var scaled = scaledDown(value, exponent)
			if value != 0, roundedDigits(scaled, decimals: shape.decimalPlaceholders).integer != "0" {
				exponent += 1
				scaled /= 10
			}
			mantissa = fixed(scaled, shape)
		} else if shape.integerPlaceholders == 1 {
			var plain = shape
			plain.minimumIntegerDigits = 1
			exponent = value == 0 ? 0 : decimalExponent(value)
			var scaled = scaledDown(value, exponent)
			if roundedDigits(scaled, decimals: plain.decimalPlaceholders).integer == "10" {
				exponent += 1
				scaled /= 10
			}
			mantissa = fixed(scaled, plain)
		} else if shape.minimumIntegerDigits == shape.integerPlaceholders {
			// Only 0 integer placeholders ("00E00"): exactly that many integer digits, rounded to significant digits.
			let digits = shape.integerPlaceholders
			exponent = value == 0 ? 0 : decimalExponent(value) - digits + 1
			var scaled = scaledDown(value, exponent)
			if roundToSignificant(scaled, significant) >= pow(10, Double(digits)) {
				exponent += 1
				scaled /= 10
			}
			let (integer, fraction) = roundedDigits(scaled, decimals: max(significant - digits, 0))
			mantissa = withPoint(integer, fraction, shape)
		} else {
			// Engineering: exponents in steps of the integer placeholder count, rounded to significant digits
			// (showing decimals for them even with no decimal placeholders).
			let step = shape.integerPlaceholders
			exponent = value == 0 ? 0 : floorDivide(decimalExponent(value), by: step) * step
			var scaled = scaledDown(value, exponent)
			var rounded = roundToSignificant(scaled, significant)
			if rounded >= pow(10, Double(step)) {
				exponent += step
				scaled /= pow(10, Double(step))
				rounded = roundToSignificant(scaled, significant)
			}
			let integerCount = rounded < 1 || !rounded.isFinite ? 1 : Int(floor(log10(rounded))) + 1
			let decimalCount = max(significant - integerCount, 0)
			let (integer, allDecimals) = roundedDigits(rounded, decimals: decimalCount)
			var decimals = Substring(allDecimals)
			while decimals.count > shape.minimumDecimals, decimals.last == "0" {
				decimals = decimals.dropLast()
			}
			mantissa = withPoint(integer, decimals, shape)
		}

		let sign = exponent < 0 ? "-" : (format.alwaysSign ? "+" : "")
		let digits = String(abs(exponent))
		let padding = String(repeating: "0", count: max(format.minimumDigits - digits.count, 0))
		return mantissa + "E" + sign + padding + digits
	}

	/// The power of ten of `value`'s first significant digit.
	private static func decimalExponent(_ value: Double) -> Int {
		shortestDecimal(value).exponent
	}

	private static func floorDivide(_ value: Int, by divisor: Int) -> Int {
		Int(floor(Double(value) / Double(divisor)))
	}

	private static func roundToSignificant(_ value: Double, _ significant: Int) -> Double {
		guard value != 0, value.isFinite else { return value }
		let integerDigits = Int(floor(log10(value))) + 1
		let scale = pow(10, Double(significant - integerDigits))
		// More digits than a Double has (hundreds of decimals): it's already that precise. (The scale was infinite,
		// the result NaN, and turning its logarithm into an Int trapped.)
		guard scale.isFinite, scale > 0, (value * scale).isFinite else { return value }
		return (value * scale).rounded(.toNearestOrEven) / scale
	}

	/// `value` ÷ 10^`exponent`. Doubles go down to 10⁻³²⁴ (subnormal), where 10^exponent alone is 0 and the
	/// result was infinite (and turning its logarithm into an Int trapped): such powers are divided in two steps.
	private static func scaledDown(_ value: Double, _ exponent: Int) -> Double {
		guard abs(exponent) > 300 else { return value / pow(10, Double(exponent)) }
		let half = exponent / 2
		return value / pow(10, Double(half)) / pow(10, Double(exponent - half))
	}

	/// `value`'s shortest round-tripping digits (no leading or trailing zeros) and the power of ten of the first.
	private static func shortestDecimal(_ value: Double) -> (digits: String, exponent: Int) {
		var text = "\(value)".lowercased()
		var power = 0
		if let e = text.firstIndex(of: "e") {
			power = Int(text[text.index(after: e)...]) ?? 0
			text = String(text[..<e])
		}
		let parts = text.split(separator: ".", omittingEmptySubsequences: false)
		let whole = String(parts[0])
		let all = whole + (parts.count > 1 ? String(parts[1]) : "")
		let leadingZeros = all.prefix { $0 == "0" }.count
		var digits = String(all.dropFirst(leadingZeros))
		while digits.count > 1, digits.hasSuffix("0") {
			digits.removeLast()
		}
		return (digits.isEmpty ? "0" : digits, whole.count - 1 - leadingZeros + power)
	}

	/// The shortest digits of `value` with the point after `pointAfter` digits (zeros added as needed).
	private static func shortestDigits(_ value: Double, pointAfter: Int) -> (integer: String, fraction: String) {
		guard value != 0 else {
			return ("0", "")
		}
		var digits = shortestDecimal(value).digits
		if digits.count < pointAfter {
			digits += String(repeating: "0", count: pointAfter - digits.count)
		}
		if pointAfter <= 0 {
			return ("0", String(repeating: "0", count: -pointAfter) + digits)
		}
		return (String(digits.prefix(pointAfter)), String(digits.dropFirst(pointAfter)))
	}
}
