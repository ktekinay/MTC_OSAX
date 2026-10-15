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
}
