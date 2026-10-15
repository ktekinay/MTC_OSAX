import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// `evalformula` (recorded and probed from SatimageOSAX in `Fixtures/Arrays`): the language, where Satimage was
/// wrong, and the special functions against published values.
@MainActor
struct FormulaTests {
	private func evaluate(_ formula: String, _ variables: [Any] = []) -> AppleEventReply {
		send("SATILSOP", ["----": formula, "with": AppleEventList(variables.map { $0 as! any AppleEventEncodable })])
	}

	private func number(_ formula: String, _ variables: [Any] = []) -> Double? {
		evaluate(formula, variables).result?.doubleValue
	}

	/// Precedence and unary operators as SatimageOSAX had them (probed): `^` left to right and tighter than unary
	/// minus, unary operators only where an expression starts.
	@Test func language() {
		#expect(number("2*3^2") == 18)
		#expect(number("2^3^2") == 64)
		#expect(number("-2^2") == -4)
		#expect(number("-2+3") == 1)
		#expect(number("--2") == 2)
		#expect(number("!0+1") == 2)
		#expect(number("1|0&0") == 1)
		#expect(number("2>1>0") == 1)
		#expect(number("abs(-2)") == 2)
		#expect(number("0x10+.5+1e1") == 26.5)
		#expect(number("r=x+1\nr*r", ["x", 2]) == 9)
		#expect(number("X+x", ["x", 1]) == 2)
		#expect(number("COS(0)+PI-pi") == 1)
		#expect(number("count+1", ["count", 2]) == 3)
		#expect(evaluate("1+-2").error?.number == 16)
		#expect(evaluate("x+*2", ["x", 1]).error?.number == 15)
		#expect(evaluate("(1").error?.number == 2)
		#expect(evaluate("foo(1)").error?.number == 5)
		#expect(evaluate("y").error?.number == 7)
		#expect(evaluate("atan2(1)").error?.number == 10)
		#expect(evaluate("cos()").error?.number == 11)
		#expect(evaluate("pi=3").error?.number == 17)
		#expect(evaluate("x+y", ["x", AppleEventList([1, 2]), "y", AppleEventList([1, 2, 3])]).error?.number == 18)
		#expect(evaluate("").error?.number == -50)
	}

	/// SatimageOSAX didn't know `sqr` (error 5), and gave a syntax error (16) for a comment with a space in it or
	/// after an expression; the dictionary has both.
	@Test func sqrAndComments() {
		#expect(number("sqr(3)") == 9)
		#expect(number("x+1// a comment\n", ["x", 2]) == 3)
		#expect(number("x // c", ["x", 2]) == 2)
		#expect(number("r=x;// one\n// two\nr*2", ["x", 2]) == 4)
	}

	/// ∫f dx, as the dictionary says (SatimageOSAX computed ∫x df): ∫1 dx from 0 to 2 is 2.
	@Test func integral() {
		#expect(number("int(f,x)", ["f", AppleEventList([1, 1, 1]), "x", AppleEventList([0, 1, 2])]) == 2)
		#expect(number("int(x,x)", ["x", AppleEventList([0, 1, 3])]) == 4.5)
		#expect(number("int(x,y)", ["x", AppleEventList([1, 2, 4, 8]), "y", AppleEventList([0, 1, 3, 6])]) == 25.5)
		#expect(evaluate("int(2,x)", ["x", AppleEventList([0, 1])]).error?.number == 21)
	}

	/// Abramowitz and Stegun's tables (17.5, 17.9) and Lambert's W by its definition.
	@Test func specialFunctions() {
		func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance * max(1, abs(b)) }
		#expect(close(SpecialFunctions.completeK(0.5), 1.685750354812596))
		#expect(close(SpecialFunctions.completeE(0.5), 1.467462209339427))
		#expect(close(SpecialFunctions.completeK(0), .pi / 2))
		#expect(SpecialFunctions.completeK(1).isNaN)
		#expect(close(SpecialFunctions.incompleteF(.pi / 2, 0.5), SpecialFunctions.completeK(0.5)))
		#expect(close(SpecialFunctions.incompleteE(.pi / 2, 0.5), SpecialFunctions.completeE(0.5)))
		// Each π adds twice the complete integral.
		#expect(close(SpecialFunctions.incompleteF(0.3 + .pi, 0.5), SpecialFunctions.incompleteF(0.3, 0.5) + 2 * SpecialFunctions.completeK(0.5)))
		// Π(k, 0) is K(k); Π(φ, k, 0) is F(φ, k).
		#expect(close(SpecialFunctions.completeP(0.5, 0), SpecialFunctions.completeK(0.5)))
		#expect(close(SpecialFunctions.incompleteP(0.7, 0.5, 0), SpecialFunctions.incompleteF(0.7, 0.5)))
		for x in [-0.3, -0.1, 0.5, 1, 10, 1000] {
			let w = SpecialFunctions.lambertW0(x)
			#expect(close(w * exp(w), x, 1e-14), "W0(\(x))")
		}
		for x in [-0.3, -0.1, -1e-8] {
			let w = SpecialFunctions.lambertWm1(x)
			#expect(w <= -1 && close(w * exp(w), x, 1e-12), "W-1(\(x))")
		}
		#expect(close(SpecialFunctions.lambertW0(1), 0.5671432904097838))
		#expect(SpecialFunctions.lambertW0(-1) == -1)
	}

	/// Arrays of a million, as matrices too, in well under a second.
	@Test func largeArrays() throws {
		let count = 1_000_000
		let start = Date()
		let x = ArrayOfReal((0 ..< count).map(Double.init))
		#expect(values(evaluate("sqrt(x)*2+1", ["x", x]))?.last == sqrt(Double(count - 1)) * 2 + 1)
		#expect(number("sum(x)", ["x", x]) == Double(count) * Double(count - 1) / 2)
		let matrix = try Matrix(columns: 1000, rows: 1000, values: x.values).descriptor()
		let result = send("SATILSOP", ["----": "m*2", "with": AppleEventList(["m", matrix]), "rtyp": NSAppleEventDescriptor(typeCode: Matrix.descriptorType)])
		#expect(try result.result.flatMap { try Matrix($0) }?.rows == 1000)
		#expect(Date().timeIntervalSince(start) < 5)
	}
}
