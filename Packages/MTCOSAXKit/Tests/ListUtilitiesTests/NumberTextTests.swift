import AppleEventCore
import Foundation
import Testing
@testable import ListUtilities

/// `NumberText` against the Apple Event Manager's coercion of numbers to text, which it replaces (and which every
/// Mac has): every decimal exponent, numbers next to powers of ten and the thresholds of its forms, random bits, and
/// integers. (Compared once on 3.2 million numbers when it was written.) On the main actor, as the app makes every
/// Apple Event Manager call: coercing on other threads while the main-actor tests start is the likeliest cause of a
/// crash seen once as this target started (see the README's Tests section and TestCrashBacktrace.m).
@MainActor
struct NumberTextTests {
	private func coerced(_ descriptor: NSAppleEventDescriptor) -> String? {
		descriptor.coerce(toDescriptorType: typeUnicodeText)?.stringValue
	}

	@Test func realsAsTheCoercionWritesThem() {
		var generator = SeededGenerator(seed: 8)
		var values: [Double] = [0, -0.0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0.1 + 0.2, 1e16 - 2, 1e16, 1e16 + 2, 0.000001, 0.00000099999999999999995, 1e-7, 1e15 + 0.5]
		for exponent in -330 ... 308 {
			let power = pow(10.0, Double(exponent))
			values += [power, power.nextUp, power.nextDown, -power, power * 9.9999999999999995, power * 0.99999999999999995, power * 1.5, -power * 1.25]
			values += (0 ..< 20).map { _ in Double.random(in: 1 ..< 10, using: &generator) * power }
		}
		values += (0 ..< 20_000).map { _ in Double(bitPattern: generator.next()) }.filter(\.isFinite)
		values += (0 ..< 5_000).map { _ in Double(Int.random(in: -100_000 ... 100_000, using: &generator)) / [2, 8, 10, 1000, 3, 7].randomElement(using: &generator)! }
		// Products near 1e308 can overflow.
		for value in values where value.isFinite {
			#expect(NumberText.text(value) == coerced(NSAppleEventDescriptor(double: value)), "\(value) (bits \(value.bitPattern))")
		}
	}

	/// As the coercion writes them (recorded outside the tests: in a process that has loaded AppleScript, as the tests
	/// have, it sometimes left out NaN's space on its first call). NaN's payload doesn't show.
	@Test func infinitiesAndNaN() {
		#expect(NumberText.text(Double.infinity) == " INF")
		#expect(NumberText.text(-Double.infinity) == "-INF")
		#expect(NumberText.text(Double.nan) == " NAN(000)")
		#expect(NumberText.text(-Double.nan) == "-NAN(000)")
		#expect(NumberText.text(Double(nan: 0x123, signaling: true)) == " NAN(000)")
	}

	@Test func integersAsTheCoercionWritesThem() {
		var generator = SeededGenerator(seed: 9)
		for value in [Int64.min, .max, -1, 0, 1, Int64(Int32.min), Int64(Int32.max)] + (0 ..< 2_000).map({ _ in Int64(bitPattern: generator.next()) }) {
			var bytes = value
			let descriptor = NSAppleEventDescriptor(descriptorType: typeSInt64, bytes: &bytes, length: 8)!
			#expect(NumberText.text(value) == coerced(descriptor), "\(value)")
		}
	}

	/// What `sortlist`, `exclude items` and `keep items` compare: every number type through `ListUtilities.text`.
	@Test func everyNumberTypeAsText() {
		var short: Int16 = -12, long: Int32 = 123_456, wide: Int64 = 1 << 40, single: Float32 = 1.5
		let descriptors = [
			NSAppleEventDescriptor(descriptorType: typeSInt16, bytes: &short, length: 2)!,
			NSAppleEventDescriptor(descriptorType: typeSInt32, bytes: &long, length: 4)!,
			NSAppleEventDescriptor(descriptorType: typeSInt64, bytes: &wide, length: 8)!,
			NSAppleEventDescriptor(descriptorType: typeIEEE32BitFloatingPoint, bytes: &single, length: 4)!,
			NSAppleEventDescriptor(double: 1e20), NSAppleEventDescriptor(double: .infinity), NSAppleEventDescriptor(double: -2.5e-9),
			NSAppleEventDescriptor(double: -.nan),
		]
		for descriptor in descriptors.dropLast() {
			#expect(ListUtilities.text(descriptor) == coerced(descriptor))
		}
		#expect(descriptors.map { ListUtilities.text($0)! } == ["-12", "123456", "1099511627776", "1.5", " 1e+20", " INF", "-2.5e-9", "-NAN(000)"])
	}
}
