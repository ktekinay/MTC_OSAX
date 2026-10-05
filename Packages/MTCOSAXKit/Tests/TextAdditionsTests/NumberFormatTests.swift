import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

/// Examples recorded from SatimageOSAX; the fixtures cover many more.
@MainActor
struct NumberFormatTests {
	private func format(_ value: Double, _ format: String) throws -> String {
		try #require(NumberFormat(format)).format(value)
	}

	@Test(arguments: [
		(3.14159, "##.##", "3.14"), (0.5, "##.##", "0.5"), (5, "##.##", "5"), (5, "00.00", "05.00"),
		(99.995, "##.##", "100"), (12.345, "##.##", "12.34"), (2.5, "#", "2"), (3.5, "#", "4"),
		(1e20, "0.000", "100000000000000000000.000"), (0.15, "#.0", ".2"), (0, ".##", ".0"), (5, "#.", "5."),
	])
	func fixed(_ value: Double, _ format: String, _ expected: String) throws {
		#expect(try self.format(value, format) == expected)
	}

	@Test func grouping() throws {
		#expect(try format(1_234_567, "#,##0") == "1,234,567")
		#expect(try format(12345.6, "#,##") == "1,23,46")
		#expect(try format(143_294_843, ",,#0,0") == "14,32,94,84,3")
	}

	@Test func literalsSignsAndPercent() throws {
		#expect(try format(-3.14159, "'$'##.##") == "-$3.14")
		#expect(try format(-0.0001, "#.##") == "-0")
		#expect(try format(0.123, "#.#%") == "12.3%")
		#expect(try format(5, "'a''b'#") == "a'b5")
		#expect(try format(-5, "#;(#)") == "(5)")
	}

	/// Numbers near a Double's smallest in scientific formats, and formats with hundreds of decimals, trapped: a
	/// power of ten underflowed to 0 or overflowed to infinity, and the logarithm of the result became an Int.
	@Test func extremes() throws {
		#expect(try format(1e-323, "00E0") == "10E-324")
		#expect(try format(1e-323, "#0E0") == "10E-324")
		#expect(try format(1e-322, "##0E0") == "100E-324")
		#expect(try format(5e-324, "0.0E+0") == "4.9E-324")
		#expect(try format(5e-324, ".00E0") == ".49E-323")
		#expect(try format(1.5e-310, "0.00E0") == "1.50E-310")
		let zeros = String(repeating: "0", count: 400)
		#expect(try format(5, "#0." + zeros + "E0") == "5." + zeros + "E0")
		// Many decimals are the Double's exact digits (they were wrong past about 16, and "nan" past 308).
		#expect(try format(1.0 / 3, "0." + zeros) == "0.333333333333333314829616256247390992939472198486328125" + String(repeating: "0", count: 346))
		#expect(try format(1.0 / 3, "0." + String(repeating: "0", count: 30)) == "0.333333333333333314829616256247")
	}

	/// `%` overflowing to infinity used to trap; Satimage shows ∞.
	@Test func percentOverflow() throws {
		#expect(try format(1e307, "00E0%") == "∞%")
		#expect(try format(-1e307, "'x'#,##0.00%") == "-x∞%")
		#expect(try format(.infinity, "0.0") == "∞")
		#expect(try format(.nan, "0.0") == "NaN")
	}

	/// Satimage used the first section's layout for all sections and rejected three.
	@Test func sections() throws {
		#expect(try format(-6_278_518.85, "abcE+00;E##.0##") == "E6278518.85")
		#expect(try format(5, "+#;-#;'zero'") == "+5")
		#expect(try format(-5, "+#;-#;'zero'") == "-5")
		#expect(try format(0, "+#;-#;'zero'") == "zero")
		#expect(try format(0, "0.0;(0.0);'z'0") == "z0")
		#expect(try format(-5, "#;;#") == "-5")
		#expect(try format(12.5, ";#") == "12.5")
		#expect(NumberFormat("#;#;#;#") == nil)
	}

	/// Documented; Satimage printed ^ itself.
	@Test func caretIsSpace() throws {
		#expect(try format(3.14159, "^##.##") == " 3.14")
		#expect(try format(5, "'^'#^") == "^5 ")
	}

	/// Documented; Satimage ignored `underflow test`.
	@Test func underflowTest() throws {
		let format = try #require(NumberFormat("#.##"))
		#expect(format.format(0.0001) == "0")
		#expect(format.format(0.0001, underflowTest: true) == "1E-04")
		#expect(format.format(0.5, underflowTest: true) == "0.5")
		#expect(format.format(0, underflowTest: true) == "0")
		#expect(try #require(NumberFormat("0.000")).format(1e-10, underflowTest: true) == "1.000E-10")
	}

	@Test func scientific() throws {
		#expect(try format(12345, "0.0E+0") == "1.2E+4")
		#expect(try format(0.00123, "#.##E+00") == "1.23E-03")
		#expect(try format(12345, "##0.0E+0") == "12E+3")
		#expect(try format(Double.pi, "#E+0") == "3.141592653589793E+0")
		#expect(try format(2831.03, "abc.000E+0 'u'") == "abc.283E+4 u")
		#expect(try format(2.2617, "E00E00)") == "E23E-01)")
	}

	/// Satimage showed one decimal fewer here, "1E+1" for 9.95 and dropped required decimals for zero.
	@Test func scientificDecimalsFollowPlaceholders() throws {
		#expect(try format(9.941, "#.0#E+0") == "9.94E+0")
		#expect(try format(9.95, "#.0#E+0") == "9.95E+0")
		#expect(try format(0, "#.0#E+0") == "0.0E+0")
	}

	@Test(arguments: ["##^##", "0#.##", "##.##.##", "# ###", "'", "#;#;#;#", "###,", ".#0", "0.00e+00", ",#E0", "(,,#.00#)"])
	func invalid(_ format: String) {
		#expect(NumberFormat(format) == nil)
	}

	@Test func emptyFormat() throws {
		#expect(try format(Double.pi, "") == "3.141593")
	}
}

/// Satimage silently reused the last valid format for an invalid one or a missing `into`; MTC_OSAX doesn't.
@MainActor
struct FormatErrorTests {
	private func send(_ value: Double, into format: String?) -> AppleEventReply {
		let dispatcher = CommandDispatcher()
		dispatcher.register(TextAdditions.commands(context: TextContext()))
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: "SATIFORM"))
		event.setParam(NSAppleEventDescriptor(double: value), forKeyword: keyDirectObject)
		if let format {
			event.setParam(NSAppleEventDescriptor(string: format), forKeyword: FourCharCode(fourCharString: "into"))
		}
		return dispatcher.dispatch(event)
	}

	@Test func missingInto() {
		#expect(send(12.5, into: nil).error == .missingParameter)
	}

	@Test func invalidFormat() {
		let error = send(12.5, into: "##^##").error
		#expect(error?.number == -50)
		#expect(error?.message?.contains("##^##") == true)
	}
}
