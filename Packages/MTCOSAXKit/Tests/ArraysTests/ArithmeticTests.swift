import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// What the fixtures don't show (they're in `Fixtures/Arrays`): polynomials taken apart from `composepolynomial`,
/// dividing one by a number (which Satimage refused), and sizes.
@MainActor
struct ArithmeticTests {
	private func polynomial(_ coefficients: [Double]) throws -> NSAppleEventDescriptor {
		try ArrayOfReal.descriptor(count: coefficients.count, type: ArrayOfReal.polynomialType) { _ = $0.initialize(from: coefficients) }
	}

	private func coefficients(_ reply: AppleEventReply) -> [Double]? {
		reply.result.flatMap { ArrayOfReal.values(of: $0, type: ArrayOfReal.polynomialType) }
	}

	/// Polynomials are added and multiplied as polynomials (recorded: (1 + 2x)² is 1 + 4x + 4x²).
	@Test func polynomials() throws {
		let p = try polynomial([1, 2])
		#expect(coefficients(send("SATILST*", ["----": p, "with": p])) == [1, 4, 4])
		#expect(coefficients(send("SATILST*", ["----": p, "with": AppleEventList([1, 2, 3])])) == [1, 4, 7, 6])
		#expect(coefficients(send("SATILST+", ["----": p, "with": try polynomial([1, 2, 1])])) == [2, 4, 1])
		#expect(coefficients(send("SATILST+", ["----": p, "with": 10])) == [11, 2])
		#expect(coefficients(send("SATILST-", ["----": AppleEventList([5]), "with": p])) == [4, -2])
		#expect(coefficients(send("SATILST*", ["----": try polynomial([]), "with": p])) == [])
	}

	/// SatimageOSAX refused (-50); dividing by a number scales the polynomial. By a polynomial (or a number by one),
	/// the result isn't a polynomial: -50.
	@Test func dividingAPolynomial() throws {
		#expect(coefficients(send("SATILST/", ["----": try polynomial([1, 2]), "with": 2])) == [0.5, 1])
		#expect(send("SATILST/", ["----": try polynomial([1, 2]), "with": try polynomial([1])]).error?.number == -50)
		#expect(send("SATILST/", ["----": 2, "with": try polynomial([1, 2])]).error?.number == -50)
	}

	/// A million numbers, in well under a second.
	@Test func largeArrays() {
		let count = 1_000_000
		let start = Date()
		let array = ArrayOfReal((0 ..< count).map(Double.init))
		#expect(values(send("SATILST+", ["----": array, "with": array]))?.last == Double(2 * (count - 1)))
		#expect(values(send("SATILST*", ["----": array, "with": 2]))?.last == Double(2 * (count - 1)))
		#expect(Date().timeIntervalSince(start) < 5)
	}

	/// Item by item, at any depth, `missing value` for what isn't a finite number.
	@Test func nestedListsAndMissingValues() throws {
		let result = try #require(send("SATILST+", ["----": AppleEventList([1, AppleEventList([2, true])]), "with": 1]).result)
		#expect(result.atIndex(1)?.doubleValue == 2)
		#expect(result.atIndex(2)?.atIndex(1)?.doubleValue == 3)
		#expect(result.atIndex(2)?.atIndex(2)?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		#expect(send("SATILST/", ["----": 1, "with": 0]).result?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		#expect(send("SATILST+", ["----": AppleEventRecord(["abcd": 1]), "with": 1]).error == .coercionFailed)
	}

	/// Lists nested more than 512 levels are -50, as they are for the other commands (deeper ran out of stack).
	@Test func deeplyNestedLists() {
		#expect(send("SATILST+", ["----": nested(NSAppleEventDescriptor.maximumNesting + 1), "with": 1]).error?.number == -50)
		#expect(send("SATILST+", ["----": nested(NSAppleEventDescriptor.maximumNesting), "with": 1]).error == nil)
	}

	/// Matrices count toward the limit too (Audit C2).
	@Test func deeplyNestedMatrices() throws {
		#expect(send("SATILST+", ["----": AppleEventList([try nestedMatrices(300)]), "with": 1]).error?.number == -50)
		#expect(send("SATILST+", ["----": try nestedMatrices(3_000, throughLists: false), "with": 1]).error?.number == -50)
		#expect(send("SATILST+", ["----": AppleEventList([try nestedMatrices(200)]), "with": 1]).error == nil)
	}

	/// Multiplying polynomials takes the product of their lengths: more than 10,000,000,000 is -50.
	@Test func longPolynomials() throws {
		let long = try polynomial(Array(repeating: 1, count: 100_001))
		#expect(send("SATILST*", ["----": long, "with": ArrayOfReal(Array(repeating: 1, count: 100_000))]).error?.number == -50)
		#expect(coefficients(send("SATILST*", ["----": long, "with": try polynomial([2])]))?.count == 100_001)
	}

	/// Lists of every kind of number, and a list as long as a million.
	@Test func lists() throws {
		func typed<Value>(_ value: Value, _ type: DescType) -> NSAppleEventDescriptor {
			withUnsafeBytes(of: value) { NSAppleEventDescriptor(descriptorType: type, bytes: $0.baseAddress, length: $0.count)! }
		}
		let items = [typed(Int16(2), typeSInt16), typed(Int32(3), typeSInt32), typed(Int64(4), typeSInt64), typed(Float32(0.5), typeIEEE32BitFloatingPoint), typed(1.5, typeIEEE64BitFloatingPoint)]
		let result = try #require(send("SATILST*", ["----": AppleEventList(items), "with": 2]).result)
		#expect((1 ... 5).map { result.atIndex($0)!.doubleValue } == [4, 6, 8, 1, 3])
		let count = 1_000_000
		let list = (0 ..< count).map(Double.init).appleEventDescriptor
		let start = Date()
		let sum = try #require(send("SATILST+", ["----": list, "with": list]).result)
		#expect(sum.numberOfItems == count && sum.atIndex(count)?.doubleValue == Double(2 * (count - 1)))
		#expect(Date().timeIntervalSince(start) < 5)
	}
}
