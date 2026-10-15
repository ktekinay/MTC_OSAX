import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// The polynomial commands (recorded from SatimageOSAX in `Fixtures/Arrays`): roots are roots, approximants and fits
/// do what they say, and where Satimage was wrong.
@MainActor
struct PolynomialTests {
	private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
		abs(a - b) <= tolerance * max(1, abs(b))
	}

	/// Every root makes the polynomial (nearly) 0, real or complex, at degrees up to 12.
	@Test func rootsAreRoots() throws {
		var generator = SystemRandomNumberGenerator()
		for degree in 1 ... 12 {
			let p = (0 ... degree).map { _ in Double.random(in: -5 ... 5, using: &generator) }
			let roots = try #require(RootFinder.roots(p))
			#expect(roots.count == degree)
			for root in roots {
				// P(z) by Horner's rule in complex numbers.
				var (re, im) = (0.0, 0.0)
				for coefficient in p.reversed() {
					(re, im) = (re * root.real - im * root.imaginary + coefficient, re * root.imaginary + im * root.real)
				}
				let scale = p.map(abs).reduce(0, +) * pow(max(1, hypot(root.real, root.imaginary)), Double(degree))
				#expect(hypot(re, im) <= 1e-9 * scale, "degree \(degree), root \(root)")
			}
		}
	}

	/// The order SatimageOSAX recorded: hqr's, with + before - in a pair.
	@Test func rootOrder() throws {
		#expect(try #require(RootFinder.roots([-6, 11, -6, 1])).map { $0.real.rounded() } == [3, 2, 1])
		let pair = try #require(RootFinder.roots([1, 0, 1]))
		#expect(pair.map(\.imaginary) == [1, -1])
	}

	/// NUM/DEN matches the series to the order asked: [2/2] of eˣ is (1 + x/2 + x²/12)/(1 - x/2 + x²/12).
	@Test func padeApproximant() throws {
		let series = [1, 1, 0.5, 1.0 / 6, 1.0 / 24]
		let reply = try #require(send("SATIPade", ["----": AppleEventList(series), "nume": 2, "deno": 2]).result)
		let numerator = try #require(ArrayOfReal.values(of: reply.atIndex(1)!, type: ArrayOfReal.polynomialType))
		let denominator = try #require(ArrayOfReal.values(of: reply.atIndex(2)!, type: ArrayOfReal.polynomialType))
		for (value, expected) in zip(numerator + denominator, [1, 0.5, 1.0 / 12, 1, -0.5, 1.0 / 12]) {
			#expect(close(value, expected))
		}
	}

	/// SatimageOSAX returned nothing; P(Q) of the empty P is the empty polynomial.
	@Test func composeTheEmptyPolynomial() throws {
		let reply = try #require(send("SATICoPo", ["----": AppleEventList([]), "with": AppleEventList([1, 2])]).result)
		#expect(ArrayOfReal.values(of: reply, type: ArrayOfReal.polynomialType) == [])
		#expect(Polynomials.compose([1, -2, 0, 3], [2, 1, 1]) == [21, 34, 52, 39, 27, 9, 3])
	}

	/// Constraints are met; an exact fit's error is about 0 (SatimageOSAX's was 3.8e-8 for a line).
	@Test func polynomialFits() throws {
		let x = (0 ..< 30).map { Double($0) / 6 }
		let y = x.map { sin($0) }
		let reply = try #require(send("SATIFiPo", ["----": AppleEventList([ArrayOfReal(x), ArrayOfReal(y)]), "degr": 3, "cons": AppleEventList([AppleEventList([1, 0, 0, 0, 0.5]), AppleEventList([0, 1, 1, 1, 0])])]).result)
		let list = try #require(RecordFields(reply)?[.code("FRes")])
		let c = (1 ... list.numberOfItems).map { list.atIndex($0)!.doubleValue }
		#expect(close(c[0], 0.5) && close(c[1] + c[2] + c[3], 0, 1e-12))
		let lineReply = try #require(send("SATIFiPo", ["----": AppleEventList([ArrayOfReal([0, 1, 2, 3, 4]), ArrayOfReal([1, 3, 5, 7, 9])]), "degr": 1]).result)
		#expect(try #require(RecordFields(lineReply)?[.code("Ferr")]).doubleValue < 1e-14)
	}

	/// A minimax fit: exact data gives an error of about 0; the largest error is reported.
	@Test func rationalFits() throws {
		let x = (0 ..< 20).map { Double($0) / 4 }
		let y = x.map { (1 + 2 * $0) / (1 + 0.5 * $0) }
		let reply = try #require(send("SATIRatF", ["----": AppleEventList([ArrayOfReal(x), ArrayOfReal(y)]), "nume": 1, "deno": 1, "Form": "%.3g"]).result)
		let fit = try #require(RecordFields(reply))
		#expect(try #require(fit[.code("Ferr")]).doubleValue < 1e-12)
		#expect(fit[.code("FStr")]?.stringValue == "(1+2*x)/(1+0.5*x)")
	}

	/// The fit string: coefficients by the format, "1" and "-1" written as x, zeros left out; a format with another
	/// conversion than a real's, or two, is -50 (they'd read past the coefficient).
	@Test func formulas() throws {
		#expect(try Polynomials.formula([1, 0.9999999999999973, 1.0000000000000009], format: "%.3g") == "1+x+x^2")
		#expect(try Polynomials.formula([-2.220446049250313e-16, 4], format: "%.4f") == "4.0000*x")
		#expect(try Polynomials.formula([-1, -1, -1], format: "%g") == "-1-x-x^2")
		#expect(try Polynomials.formula([0.5, -2], format: "%+.1e") == "+5.0e-01-2.0e+00*x")
		for bad in ["%d", "%s", "%n", "%g %g", "%.3g%x", "%lld"] {
			#expect(throws: OSAXError.parameterError, "\(bad)") { try RealFormat(bad) }
		}
		#expect(try RealFormat("%5.2f%%").format(1.5) == " 1.50%")
	}
}
