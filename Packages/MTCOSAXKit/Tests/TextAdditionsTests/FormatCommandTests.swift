import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

private func printf(_ format: String, _ arguments: [any AppleEventEncodable]) throws -> String {
	try Printf.format(format, arguments: arguments.map(\.appleEventDescriptor))
}

@MainActor
struct PrintfTests {
	@Test func documentationExamples() throws {
		#expect(try printf(#"integers like %d, floats like %g, strings like "%s"."#, [12, Double.pi, "hello"])
			== #"integers like 12, floats like 3.14159, strings like "hello"."#)
		#expect(try printf("escape %% with %%%% like in %2.f%%", [39.12]) == "escape % with %% like in 39%")
		#expect(try printf("The %2$s %1$s.", ["car", "red"]) == "The red car.")
	}

	@Test func listsRepeatTheFormat() throws {
		#expect(try printf("%d-%s;", [[1, 2], "x"]) == "1-x;2-x;")
		#expect(try printf("%.1g\t%.3g\n", [[0.31, 0.12], [0.846, 0.348]]) == "0.3\t0.846\n0.1\t0.348\n")
	}

	@Test func listsOfDifferentLengths() {
		#expect(throws: OSAXError(-1)) { try printf("%d%d", [[1, 2, 3], [4, 5]]) }
	}

	@Test func integersRoundHalfToEven() throws {
		#expect(try printf("%d %d %d %x", [3.7, 2.5, -3.7, 255.9]) == "4 2 -4 100")
	}

	@Test func textAsNumber() throws {
		#expect(try printf("%d %d %f", ["12", "abc", "2.5"]) == "12 0 2.500000")
	}

	@Test func stringsUseAppleEventCoercion() throws {
		#expect(try printf("[%s][%s][%s]", [3.5, 1e20, true]) == "[3.5][ 1e+20][true]")
	}

	@Test func stringWidthCountsCharacters() throws {
		#expect(try printf("[%5s|%-4s|%.2s]", ["é", "ab", "abcdef"]) == "[    é|ab  |ab]")
	}

	@Test func starWidthAndPrecision() throws {
		#expect(try printf("[%*d][%.*f]", [5, 42, 2, 3.14159]) == "[   42][3.14]")
	}

	/// Negative `*` values as in C; widths and precisions over a million are error 10 (they used to build gigabytes,
	/// or be dropped silently when too long for an Int).
	@Test func widthLimits() throws {
		#expect(try printf("[%*d][%.*f][%*s]", [-5, 42, -2, 3.14159, -4, "ab"]) == "[42   ][3.141590][ab  ]")
		#expect(try printf("[%1000000d]", [1]).count == 1_000_002)
		for format in ["%1000001d", "%.2000000000f", "%99999999999999999999d", "%.99999999999999999999s"] {
			#expect(throws: OSAXError(10), "\(format)") { try printf(format, [1]) }
		}
		#expect(throws: OSAXError(10)) { try printf("%*d", [2_000_000_000, 1]) }
		#expect(throws: OSAXError(10)) { try printf("%.*f", [-2_000_000_000, 1]) }
	}

	@Test func characters() throws {
		#expect(try printf("[%c][%c][%3c]", [65, "Bé", 0x1F600]) == "[A][B][  😀]")
	}

	@Test(arguments: ["%@", "%n", "%hd", "%d %d", "100%"])
	func error10(_ format: String) {
		#expect(throws: OSAXError(10)) { try printf(format, [1]) }
	}

	@Test func sequentialAfterPositionalIsError10() throws {
		#expect(throws: OSAXError(10)) { try printf("%2$s %s", ["a", "b"]) }
		#expect(try printf("%s %1$s", ["a"]) == "a a")
	}

	@Test func unsupportedArguments() {
		#expect(throws: OSAXError(10)) { try printf("%s", [NSAppleEventDescriptor.missingValue]) }
		#expect(throws: OSAXError(10)) { try printf("%d", [true]) }
	}
}

@MainActor
struct DateFormattingTests {
	private let newYork = DateFormatting(timeZone: TimeZone(identifier: "America/New_York")!)

	/// 2007-01-15 16:10:56 on the wall clock.
	private let date = LocalDateTime(seconds: 3_251_722_256)

	@Test func strftimeLocalAndGMT() throws {
		#expect(try newYork.strftime(date, format: "%FT%T%z", gmt: false) == "2007-01-15T16:10:56-0500")
		#expect(try newYork.strftime(date, format: "%FT%T %z %Z", gmt: true) == "2007-01-15T21:10:56 +0000 UTC")
	}

	/// A result longer than the first buffer used to be "".
	@Test func longResults() throws {
		let one = try newYork.strftime(date, format: "%c", gmt: false)
		#expect(!one.isEmpty)
		#expect(try newYork.strftime(date, format: String(repeating: "%c", count: 100), gmt: false) == String(repeating: one, count: 100))
	}

	/// A raw date whose seconds overflow as a time since 1970 (Int64.min) trapped.
	@Test func rawDatesOutOfRange() throws {
		let raw = try #require(NSAppleEventDescriptor(descriptorType: typeLongDateTime, data: Data([0, 0, 0, 0, 0, 0, 0, 0x80])))
		#expect((#expect(throws: OSAXError.self) { try LocalDateTime(raw) })?.number == -1700)
	}

	@Test func emptyFormat() throws {
		#expect(try newYork.strftime(date, format: "", gmt: false) == "")
	}

	/// Satimage failed before 1900 (error 2); MTC_OSAX works, using the zone's local mean time where it applies.
	@Test func strftimeBefore1900() throws {
		// 1850-06-01 12:00:00 on the wall clock.
		let early = LocalDateTime(seconds: -1_690_891_200)
		#expect(try newYork.strftime(early, format: "%F %T %z %s", gmt: false) == "1850-06-01 12:00:00 -0456 -3773718238")
		#expect(try newYork.strftime(early, format: "%F %T", gmt: true) == "1850-06-01 16:56:02")
	}

	@Test func strptimeRoundTrip() throws {
		let time = try newYork.strptime("2007-01-15T16:10:56+0100", format: "%FT%T%z", gmt: false)
		#expect(time == 1_168_873_856)
		#expect(try newYork.strftime(newYork.localDateTime(for: time), format: "%F %T", gmt: false) == "2007-01-15 10:10:56")
	}

	@Test func strptimeGMT() throws {
		#expect(try newYork.strptime("2007-01-15T16:10:56", format: "%FT%T", gmt: true) == 1_168_877_456)
		#expect(try newYork.strptime("2007-01-15T16:10:56", format: "%FT%T", gmt: false) == 1_168_895_456)
	}

	/// Satimage gave -1 (1969-12-31 23:59:59 UTC) before 1900; MTC_OSAX works.
	/// A literal "%z" (written `%%z`) used to be taken for a zone, ignoring the local one.
	@Test func literalPercentZ() throws {
		#expect(try newYork.strptime("2007-01-15T16:10:56 %z", format: "%FT%T %%z", gmt: false) == 1_168_895_456)
		#expect(DateFormatting.hasDirective("z", in: "%FT%T%z"))
		#expect(!DateFormatting.hasDirective("z", in: "%%z %%%%z"))
		#expect(DateFormatting.hasDirective("z", in: "%%%z"))
	}

	@Test func strptimeBefore1900() throws {
		#expect(try newYork.strptime("1850-06-01", format: "%Y-%m-%d", gmt: true) == -3_773_779_200)
		#expect(try newYork.strftime(newYork.localDateTime(for: newYork.strptime("1850-06-01", format: "%Y-%m-%d", gmt: false)), format: "%F %T", gmt: false) == "1850-06-01 00:00:00")
	}

	@Test func calendarArithmeticMatchesTimegm() {
		for (year, month, day) in [(1970, 1, 1), (2007, 1, 15), (2000, 2, 29), (2038, 1, 20), (2100, 3, 1)] {
			var components = tm()
			components.tm_year = Int32(year - 1900)
			components.tm_mon = Int32(month - 1)
			components.tm_mday = Int32(day)
			var copy = components
			#expect(DateFormatting.utcSeconds(components) == timegm(&copy), "\(year)-\(month)-\(day)")
		}
	}

	@Test func strptimeNoMatch() {
		#expect(throws: OSAXError(-1)) { try newYork.strptime("not a date", format: "%Y-%m-%d", gmt: false) }
	}
}

