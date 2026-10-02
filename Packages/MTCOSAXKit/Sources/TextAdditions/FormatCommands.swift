import AppleEventCore
import Foundation

/// `format`, `printf`, `strftime` and `strptime`. Behavior recorded in `Fixtures/TextAdditions/NumberFormat` and
/// `Fixtures/TextAdditions/Format`.
extension TextAdditions {
	@MainActor
	static func formatCommands(_ context: TextContext) -> [CommandDefinition] {
		[
			CommandDefinition("printf", code: "SATIprtf") { request in
				let arguments = request.descriptor(for: "para").map(Printf.arguments(from:)) ?? []
				guard let format = try request.directParameter(as: String.self) else {
					// With no format, Satimage joins the parameters with spaces.
					return try arguments.map(Printf.text(of:)).joined(separator: " ")
				}
				return try Printf.format(format, arguments: arguments)
			},

			CommandDefinition("format", code: "SATIFORM") { request in
				let value = try request.requiredDirectParameter(as: Double.self)
				let text = try request.requiredParameter("into", as: String.self)
				// Satimage silently reused the previous valid format for an invalid one.
				guard let format = NumberFormat(text) else {
					throw OSAXError(-50, "\"\(text)\" isn't a valid number format.")
				}
				return format.format(value, underflowTest: try request.parameter("ZeTe", default: false))
			},

			CommandDefinition("strftime", code: "SATIstrf") { request in
				let format = try request.requiredParameter("into", as: String.self)
				let gmt = try request.parameter("GMT ", default: false)
				let dates = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
				let formatter = DateFormatting(timeZone: context.timeZone)
				if dates.descriptorType == typeAEList {
					return try (0 ..< dates.numberOfItems).map {
						try formatter.strftime(LocalDateTime(dates.atIndex($0 + 1)!), format: format, gmt: gmt)
					}
				}
				return try formatter.strftime(LocalDateTime(dates), format: format, gmt: gmt)
			},

			CommandDefinition("strptime", code: "SATIstrp") { request in
				let format = try request.requiredParameter("enco", as: String.self)
				let gmt = try request.parameter("GMT ", default: false)
				// `as date` (the default) gives a date; any other class gives seconds since 2001 as a real.
				let asDate = try request.parameter("rtyp", as: AnyDescriptor.self).map {
					$0.descriptor.typeCodeValue == FourCharCode(fourCharString: "ldt ")
				} ?? true
				let parser = DateFormatting(timeZone: context.timeZone)
				return try TextInput(request, keyword: Keyword.directObject).map { string in
					let time = try parser.strptime(string, format: format, gmt: gmt)
					if asDate {
						return parser.localDateTime(for: time).descriptor
					}
					return NSAppleEventDescriptor(double: Double(time) - 978_307_200)
				}
			},
		]
	}
}

// MARK: - printf

/// Satimage's printf: C formatting of each conversion, with its own argument rules.
///
/// - Parameters are a list; a list item makes the format repeat once per element (all such lists must have the
///   same length, else error -1), with other parameters reused on every repetition.
/// - Integer conversions round reals half to even (`%d` of 3.7 is 4) and read text as a number ("abc" is 0).
/// - `%s` uses the Apple Event Manager's text coercion (so 1.0E+20 is " 1e+20"), and pads by characters.
/// - `%c` is a character: a number is its code point, text gives its first character (Satimage failed with error 10).
/// - `%n`, `%@`, the `h` length, a trailing `%`, a missing parameter, a sequential parameter after a positional one,
///   and booleans for numbers, `missing value`, dates and records are error 10.
/// - A width or precision over a million is error 10 (`%2000000000d` would build gigabytes). From `*`, a negative
///   width means left-justified and a negative precision none, as in C.
enum Printf {
	static let error = OSAXError(10)
	static let maximumWidth = 1_000_000

	/// The top-level parameters: a list's items, or a single value.
	static func arguments(from descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
		guard descriptor.descriptorType == typeAEList else {
			return [descriptor]
		}
		return (0 ..< descriptor.numberOfItems).map { descriptor.atIndex($0 + 1)! }
	}

	static func format(_ format: String, arguments: [NSAppleEventDescriptor]) throws -> String {
		let lengths = Set(arguments.filter { $0.descriptorType == typeAEList }.map(\.numberOfItems))
		guard lengths.count <= 1 else {
			throw invalidOptionError
		}
		guard let rows = lengths.first else {
			return try formatRow(format, arguments: arguments)
		}
		var result = ""
		for row in 0 ..< rows {
			let rowArguments = arguments.map { $0.descriptorType == typeAEList ? $0.atIndex(row + 1)! : $0 }
			result += try formatRow(format, arguments: rowArguments)
		}
		return result
	}

	private static func formatRow(_ format: String, arguments: [NSAppleEventDescriptor]) throws -> String {
		var result = ""
		var nextArgument = 0
		var usedPosition = false
		var characters = format[...]

		// After a positional parameter (`%2$s`), a sequential one is error 10; the other way round is fine.
		func takeArgument(_ position: Int?) throws -> NSAppleEventDescriptor {
			if position == nil, usedPosition {
				throw error
			}
			usedPosition = usedPosition || position != nil
			let index = position.map { $0 - 1 } ?? nextArgument
			guard index >= 0, index < arguments.count else {
				throw error
			}
			if position == nil { nextArgument += 1 }
			return arguments[index]
		}
		func number(_ characters: inout Substring) throws -> Int? {
			let digits = characters.prefix { $0.isASCII && $0.isNumber }
			characters = characters.dropFirst(digits.count)
			guard !digits.isEmpty else { return nil }
			// Too many digits for an Int used to drop the width silently.
			guard let value = Int(digits), value <= maximumWidth else { throw error }
			return value
		}
		func starValue() throws -> Int {
			let value = try Int(appleEventDescriptor: takeArgument(nil))
			guard abs(value) <= maximumWidth else { throw error }
			return value
		}

		while let percent = characters.firstIndex(of: "%") {
			result += characters[..<percent]
			characters = characters[characters.index(after: percent)...]
			guard !characters.isEmpty else {
				throw error // trailing %
			}
			if characters.first == "%" {
				result += "%"
				characters = characters.dropFirst()
				continue
			}

			// %[position$][flags][width][.precision][length]conversion
			var position: Int?
			var lookahead = characters
			if let value = try? number(&lookahead), lookahead.first == "$" {
				position = value
				characters = lookahead.dropFirst()
			}
			var flags = String(characters.prefix { "-+ #0".contains($0) })
			characters = characters.dropFirst(flags.count)
			var width: Int?
			if characters.first == "*" {
				width = try starValue()
				characters = characters.dropFirst()
				if let value = width, value < 0 {
					flags += "-"
					width = -value
				}
			} else {
				width = try number(&characters)
			}
			var precision: Int?
			if characters.first == "." {
				characters = characters.dropFirst()
				if characters.first == "*" {
					let value = try starValue()
					precision = value < 0 ? nil : value
					characters = characters.dropFirst()
				} else {
					precision = try number(&characters) ?? 0
				}
			}
			let length = String(characters.prefix { "hlqLjzt".contains($0) })
			characters = characters.dropFirst(length.count)
			guard !length.contains("h") else {
				throw error
			}
			var conversion = characters.first
			if let current = conversion, "diuxXoeEfFgGaAsc".contains(current) {
				characters = characters.dropFirst()
			} else if length.contains("q") {
				conversion = "d" // BSD's %q with no conversion, as Satimage printed it
			} else {
				throw error
			}

			let argument = try takeArgument(position)
			let spec = "%" + flags + (width.map(String.init) ?? "") + (precision.map { ".\($0)" } ?? "")
			switch conversion! {
			case "d", "i", "u", "x", "X", "o":
				let value = try integer(argument)
				result += cFormat(spec + "ll" + String(conversion!), value)
			case "s":
				result += pad(try truncate(text(of: argument), to: precision), to: width, left: flags.contains("-"))
			case "c":
				result += pad(try character(argument), to: width, left: flags.contains("-"))
			default:
				result += cFormat(spec + String(conversion!), try real(argument))
			}
		}
		result += characters
		return result
	}

	/// One C conversion with C's own formatting (`String(format:)`, like SatimageOSAX, cut the output of a
	/// conversion at 512 characters).
	private static func cFormat(_ spec: String, _ value: any CVarArg) -> String {
		let length = withVaList([value]) { vsnprintf(nil, 0, spec, $0) }
		guard length > 0 else { return "" }
		var buffer = [CChar](repeating: 0, count: Int(length) + 1)
		_ = withVaList([value]) { vsnprintf(&buffer, buffer.count, spec, $0) }
		return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
	}

	/// An argument as text, for `%s` and a missing format.
	static func text(of argument: NSAppleEventDescriptor) throws -> String {
		let type = argument.descriptorType.fourCharString
		guard !["type", "ldt ", "reco", "list", "enum"].contains(type) else {
			throw error
		}
		guard let text = try? String(appleEventDescriptor: argument) else {
			throw error
		}
		return text
	}

	/// `%c`: a number is a code point; text gives its first character.
	private static func character(_ argument: NSAppleEventDescriptor) throws -> String {
		switch argument.descriptorType.fourCharString {
		case "utxt", "ut16", "utf8", "TEXT":
			return String(try String(appleEventDescriptor: argument).prefix(1))
		default:
			guard let scalar = Unicode.Scalar(UInt32(clamping: try integer(argument))) else {
				throw error
			}
			return String(scalar)
		}
	}

	private static func real(_ argument: NSAppleEventDescriptor) throws -> Double {
		switch argument.descriptorType.fourCharString {
		case "utxt", "ut16", "utf8", "TEXT":
			return (try? TextAdditions.parseReal(String(appleEventDescriptor: argument))) ?? 0
		case "long", "shor", "comp", "doub", "sing", "magn":
			return try Double(appleEventDescriptor: argument)
		default:
			throw error
		}
	}

	private static func integer(_ argument: NSAppleEventDescriptor) throws -> Int64 {
		let value = try real(argument).rounded(.toNearestOrEven)
		return value.isFinite ? Int64(clamping: Int(exactly: value) ?? (value < 0 ? .min : .max)) : 0
	}

	private static func truncate(_ text: String, to precision: Int?) -> String {
		precision.map { String(text.prefix($0)) } ?? text
	}

	private static func pad(_ text: String, to width: Int?, left: Bool) -> String {
		guard let width, text.count < width else {
			return text
		}
		let padding = String(repeating: " ", count: width - text.count)
		return left ? text + padding : padding + text
	}
}

// MARK: - Dates

/// An AppleScript date: seconds since 1904-01-01 on the local wall clock (descriptor type `ldt `).
struct LocalDateTime {
	/// Seconds from 1904-01-01 to 1970-01-01.
	static let offsetFrom1970: Int64 = 2_082_844_800

	var seconds: Int64

	init(seconds: Int64) {
		self.seconds = seconds
	}

	/// A date parameter. Anything that isn't a date (or coercible to one) is error -1700.
	init(_ descriptor: NSAppleEventDescriptor) throws {
		let date = try descriptor.coerced(to: "ldt ")
		guard date.data.count == 8 else {
			throw OSAXError.coercionFailed
		}
		seconds = date.data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
		// A raw `ldt ` can hold anything; seconds that overflow as a time since 1970 are no date (they trapped).
		guard !seconds.subtractingReportingOverflow(Self.offsetFrom1970).overflow else {
			throw OSAXError.coercionFailed
		}
	}

	var descriptor: NSAppleEventDescriptor {
		var value = seconds
		return NSAppleEventDescriptor(descriptorType: typeLongDateTime, bytes: &value, length: 8)!
	}

	/// The wall clock as a `tm` (as if the wall clock were UTC).
	var wallClock: tm {
		var time = time_t(seconds - Self.offsetFrom1970)
		var result = tm()
		gmtime_r(&time, &result)
		return result
	}
}

/// The C date functions, run in a given time zone. They read the process-wide `TZ`, so switching zones is
/// serialized; in the app the zone is always the system's, so nothing is switched.
struct DateFormatting {
	/// A `TZ` name. Not a `TimeZone`, since Foundation reports "UTC" as "GMT", which `%Z` would then print.
	let zoneName: String

	init(timeZone: TimeZone) {
		zoneName = timeZone.identifier
	}

	init(zoneName: String) {
		self.zoneName = zoneName
	}

	private static let lock = NSLock()

	private func inTimeZone<T>(_ body: () throws -> T) rethrows -> T {
		try Self.lock.withLock {
			let previous = getenv("TZ").map { String(cString: $0) }
			let needsSwitch = zoneName != TimeZone.current.identifier || previous != nil
			if needsSwitch {
				setenv("TZ", zoneName, 1)
				tzset()
			}
			defer {
				if needsSwitch {
					if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
					tzset()
				}
			}
			return try body()
		}
	}

	/// Formats with C `strftime`. `%s`, `%z` and `%+` are filled in here, since macOS computes them with `mktime`
	/// and the process zone, which fail for dates before 1900 (Satimage returned error 2 for those).
	func strftime(_ date: LocalDateTime, format: String, gmt: Bool) throws -> String {
		// The format ends at a NUL, as in SatimageOSAX (C's does, which took the character before it with it:
		// "abc\0def" gave "ab", and a NUL first the error for a result over 16 MB).
		let format = String(String.UnicodeScalarView(format.unicodeScalars.prefix { $0 != "\0" }))
		// An empty format gives empty text (Satimage returned error 1).
		return try inTimeZone {
			var time = Self.time(fromLocal: date.wallClock)
			var broken = tm()
			if gmt {
				gmtime_r(&time, &broken)
			} else {
				localtime_r(&time, &broken)
			}
			// A character at the end, so 0 only means the buffer was too small (a hundred `%c`s): it also meant an
			// empty result, and a result over 16 MB came back as "" with no error.
			let prepared = Self.expandComputedDirectives(format, time: time, offset: gmt ? 0 : Int(broken.tm_gmtoff)) + "|"
			var size = min(256 + prepared.utf8.count * 8, 1 << 24)
			while true {
				var buffer = [CChar](repeating: 0, count: size)
				let count = Foundation.strftime(&buffer, buffer.count, prepared, &broken)
				if count > 0 {
					return String(decoding: buffer.prefix(count - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
				}
				guard size < 1 << 24 else {
					throw OSAXError(-50, "The formatted date would be more than 16 MB.")
				}
				size = min(size * 4, 1 << 24)
			}
		}
	}

	/// Whether `format` has the directive `%<character>` (`%%z` is a literal "%z", not a zone).
	static func hasDirective(_ character: Character, in format: String) -> Bool {
		var characters = format[...]
		while let percent = characters.firstIndex(of: "%") {
			let next = characters.index(after: percent)
			guard next < characters.endIndex else { return false }
			if characters[next] == character { return true }
			characters = characters[characters.index(after: next)...]
		}
		return false
	}

	/// Replaces `%s` (seconds since 1970), `%z` (±hhmm) and `%+` (date(1) format) before calling `strftime`.
	private static func expandComputedDirectives(_ format: String, time: time_t, offset: Int) -> String {
		var result = ""
		var characters = format[...]
		while let percent = characters.firstIndex(of: "%") {
			result += characters[..<percent]
			let directive = characters.index(after: percent)
			guard directive < characters.endIndex else {
				result += "%"
				characters = characters[directive...]
				break
			}
			switch characters[directive] {
			case "s":
				result += String(time)
			case "z":
				let minutes = abs(offset) / 60
				result += String(format: "%@%02d%02d", offset < 0 ? "-" : "+", minutes / 60, minutes % 60)
			case "+":
				result += expandComputedDirectives("%a %b %e %H:%M:%S %Z %Y", time: time, offset: offset)
			default:
				result += "%" + String(characters[directive]) // including %%
			}
			characters = characters[characters.index(after: directive)...]
		}
		return result + characters
	}

	/// Parses with C `strptime` (text after the parsed part is ignored; no match is error -1) and returns a
	/// `time_t`. A `%z` offset wins over `gmt`. Works for any date, unlike Satimage (which used `mktime`).
	func strptime(_ string: String, format: String, gmt: Bool) throws -> time_t {
		try inTimeZone {
			var components = tm()
			guard Foundation.strptime(string, format, &components) != nil else {
				throw invalidOptionError
			}
			if Self.hasDirective("z", in: format) {
				return Self.utcSeconds(components) - time_t(components.tm_gmtoff)
			}
			return gmt ? Self.utcSeconds(components) : Self.time(fromLocal: components)
		}
	}

	// MARK: Calendar arithmetic (mktime and timegm fail before 1900 on macOS)

	/// Seconds since 1970 for a UTC calendar time. Out-of-range fields roll over, as with `timegm`.
	static func utcSeconds(_ components: tm) -> time_t {
		let totalMonths = Int(components.tm_year) * 12 + Int(components.tm_mon)
		let year = 1900 + Int((Double(totalMonths) / 12).rounded(.down))
		let month = totalMonths - (year - 1900) * 12 + 1
		// Days from 1970-01-01 to the first of the month (Howard Hinnant's days_from_civil).
		let y = month <= 2 ? year - 1 : year
		let era = (y >= 0 ? y : y - 399) / 400
		let yearOfEra = y - era * 400
		let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5
		let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
		let days = era * 146_097 + dayOfEra - 719_468 + Int(components.tm_mday) - 1
		return time_t(days * 86400 + Int(components.tm_hour) * 3600 + Int(components.tm_min) * 60 + Int(components.tm_sec))
	}

	/// Like `mktime`: the time at which the current zone's wall clock reads `components`.
	private static func time(fromLocal components: tm) -> time_t {
		let wall = utcSeconds(components)
		func offset(at time: time_t) -> time_t {
			var time = time
			var local = tm()
			localtime_r(&time, &local)
			return time_t(local.tm_gmtoff)
		}
		let guess = wall - offset(at: wall)
		return wall - offset(at: guess)
	}

	/// The local wall clock at `time`, as an AppleScript date.
	func localDateTime(for time: time_t) -> LocalDateTime {
		inTimeZone {
			var time = time
			var local = tm()
			localtime_r(&time, &local)
			return LocalDateTime(seconds: Int64(Self.utcSeconds(local)) + LocalDateTime.offsetFrom1970)
		}
	}
}
