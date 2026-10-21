import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// The polynomial commands (recorded from SatimageOSAX in `Fixtures/Arrays`): roots are roots, approximants and fits
/// do what they say, and where Satimage was wrong.
@MainActor
struct PolynomialTests {
	private func coefficients(_ reply: AppleEventReply) -> [Double]? {
		reply.result.flatMap { ArrayOfReal.values(of: $0, type: ArrayOfReal.polynomialType) }
	}

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
		#expect(try Polynomials.formula([1, 0.9999999999999973, 1.0000000000000009], format: RealFormat("%.3g")) == "1+x+x^2")
		#expect(try Polynomials.formula([-2.220446049250313e-16, 4], format: RealFormat("%.4f")) == "4.0000*x")
		#expect(try Polynomials.formula([-1, -1, -1], format: RealFormat("%g")) == "-1-x-x^2")
		#expect(try Polynomials.formula([0.5, -2], format: RealFormat("%+.1e")) == "+5.0e-01-2.0e+00*x")
		for bad in ["%d", "%s", "%n", "%g %g", "%.3g%x", "%lld"] {
			#expect(throws: OSAXError.parameterError, "\(bad)") { try RealFormat(bad) }
		}
		#expect(try RealFormat("%5.2f%%").format(1.5) == " 1.50%")
	}

	/// A coefficient that isn't finite is -50 (an infinite one made the balancing loop forever); one so much larger
	/// than the last that dividing by it overflows is -1.
	@Test func rootsOfNonFiniteCoefficients() {
		#expect(send("SATIRoot", ["----": ArrayOfReal([.infinity, 1, 1])]).error?.number == -50)
		#expect(send("SATIRoot", ["----": ArrayOfReal([1, .nan, 1])]).error?.number == -50)
		#expect(send("SATIRoot", ["----": ArrayOfReal([1e300, 1, 1e-300])]).error?.number == -1)
		#expect(RootFinder.roots([1e300, 1, 1e-300]) == nil)
	}

	/// Limits that keep the slower algorithms to seconds, and the fits' matrices within 100,000,000 numbers.
	@Test func limits() {
		#expect(send("SATIRoot", ["----": ArrayOfReal(Array(repeating: 1, count: 1002))]).error?.number == -50)
		#expect(send("SATIPade", ["----": ArrayOfReal(Array(repeating: 1, count: 2003)), "nume": 1001, "deno": 1]).error?.number == -50)
		#expect(send("SATIPade", ["----": ArrayOfReal(Array(repeating: 1, count: 2003)), "nume": 1, "deno": 1001]).error?.number == -50)
		let x = ArrayOfReal((0 ..< 200).map(Double.init))
		#expect(send("SATIFiPo", ["----": AppleEventList([x, x]), "degr": 101]).error?.number == -50)
		#expect(send("SATIFiPo", ["----": AppleEventList([x, x]), "degr": 3]).error == nil)
		#expect(send("SATIRatF", ["----": AppleEventList([x, x]), "nume": 101, "deno": 1]).error?.number == -50)
		let many = ArrayOfReal((0 ..< 1_000_000).map(Double.init))
		#expect(send("SATIFiPo", ["----": AppleEventList([many, many]), "degr": 100]).error?.number == -50)
		#expect(send("SATICoPo", ["----": ArrayOfReal(Array(repeating: 1, count: 401)), "with": ArrayOfReal(Array(repeating: 1, count: 301))]).error?.number == -50)
		#expect(send("SATICoPo", ["----": ArrayOfReal([1, 1]), "with": ArrayOfReal([0, 2])]).error == nil)
	}

	/// evalpolynomial's coefficients times points at most 10,000,000,000, as for multiplying; composepolynomial with a
	/// Q of degree 0 (or none) is the number P(Q), at once, whatever P's length (the degree limit let any through).
	/// Audit S4.
	@Test func evaluateAndComposeLimits() throws {
		let long = ArrayOfReal(Array(repeating: 1, count: 100_001))
		#expect(send("SATIEvPo", ["----": long, "at  ": ArrayOfReal(Array(repeating: 0.5, count: 100_000))]).error?.number == -50)
		#expect(values(send("SATIEvPo", ["----": ArrayOfReal([1, 2, 3]), "at  ": ArrayOfReal([0, 1, 2])])) == [1, 6, 17])
		#expect(coefficients(send("SATICoPo", ["----": ArrayOfReal([1, 2, 3]), "with": ArrayOfReal([2])])) == [17])
		#expect(coefficients(send("SATICoPo", ["----": ArrayOfReal([1, 2, 3]), "with": AppleEventList([])])) == [1])
		#expect(Polynomials.compose([1, 2, 3], [2]) == [Polynomials.value([1, 2, 3], at: 2)])
		let start = Date()
		#expect(coefficients(send("SATICoPo", ["----": ArrayOfReal(Array(repeating: 0, count: 5_000_000)), "with": ArrayOfReal([2])])) == [0])
		#expect(Date().timeIntervalSince(start) < 5)
	}

	/// Points (and constraints) times the square of the coefficients, for each round, at most 4,000,000,000: the
	/// limit on points times coefficients alone let `fitrational 100/100` run for hours (Audit S1).
	@Test func fitWork() throws {
		#expect(throws: Never.self) { try Polynomials.checkFitSize(392_000, coefficients: 101, degree: 100, rounds: 1, "points") }
		#expect(throws: OSAXError.self) { try Polynomials.checkFitSize(393_000, coefficients: 101, degree: 100, rounds: 1, "points") }
		#expect(throws: Never.self) { try Polynomials.checkFitSize(19_800, coefficients: 201, degree: 100, rounds: 5, "points") }
		#expect(throws: OSAXError.self) { try Polynomials.checkFitSize(19_900, coefficients: 201, degree: 100, rounds: 5, "points") }
		// Through the commands: fitrational's five rounds, and fitpolynomial's constraints counted with its points.
		let x = ArrayOfReal((0 ..< 20_000).map { Double($0) / 20_000 })
		#expect(send("SATIRatF", ["----": AppleEventList([x, x]), "nume": 100, "deno": 100]).error?.number == -50)
		// 392,000 points are allowed alone (392,118 would be); with 200 constraints, not.
		let constraint = AppleEventList(Array(repeating: 0, count: 102))
		let many = ArrayOfReal((0 ..< 392_000).map { Double($0) / 392_000 })
		#expect(send("SATIFiPo", ["----": AppleEventList([many, many]), "degr": 100, "cons": AppleEventList(Array(repeating: constraint, count: 200))]).error?.number == -50)
	}
}

/// Least squares by a QR decomposition first, for more rows than columns (Audit S1): the same answers as without it.
struct LeastSquaresTests {
	/// R is upper triangular with Rᵀ R = Aᵀ A, and Qᵀ y keeps y's length along A's columns.
	@Test func triangular() {
		let rows = (0 ..< 50).map { i in (0 ..< 4).map { j in pow(Double(i) / 10 - 2, Double(j)) } }
		let y = (0 ..< 50).map { sin(Double($0)) }
		let (r, qty) = LinearAlgebra.triangular(rows, y)
		#expect(r.count == 4 && r.allSatisfy { $0.count == 4 } && qty.count == 4)
		for i in 0 ..< 4 {
			for j in 0 ..< 4 {
				if i > j {
					#expect(r[i][j] == 0)
				}
				let ata = rows.reduce(0.0) { $0 + $1[i] * $1[j] }
				let rtr = (0 ..< 4).reduce(0.0) { $0 + r[$1][i] * r[$1][j] }
				#expect(abs(ata - rtr) <= 1e-9 * max(1, abs(ata)), "\(i) \(j)")
			}
			// Aᵀ y = Rᵀ (Qᵀ y).
			let aty = zip(rows, y).reduce(0.0) { $0 + $1.0[i] * $1.1 }
			let rtq = (0 ..< 4).reduce(0.0) { $0 + r[$1][i] * qty[$1] }
			#expect(abs(aty - rtq) <= 1e-9 * max(1, abs(aty)))
		}
	}

	/// An exact polynomial from many points; the smallest solution for a rank-deficient matrix; a zero column; more
	/// constraints than unknowns.
	@Test func solutions() throws {
		let xs = (0 ..< 5_000).map { Double($0) / 1_000 - 2.5 }
		let rows = xs.map { x in (0 ... 5).map { pow(x, Double($0)) } }
		let exact = [1.5, -2, 0.25, 3, -0.5, 0.125]
		let fit = try #require(LinearAlgebra.pseudoSolve(rows, rows.map { row in zip(row, exact).reduce(0.0) { $0 + $1.0 * $1.1 } }))
		#expect(zip(fit, exact).allSatisfy { abs($0 - $1) <= 1e-9 })
		// Two equal columns: of the x with x₀ + x₁ = 2, the smallest.
		let same = try #require(LinearAlgebra.pseudoSolve(Array(repeating: [1, 1], count: 10), Array(repeating: 2, count: 10)))
		#expect(abs(same[0] - 1) <= 1e-12 && abs(same[1] - 1) <= 1e-12)
		let zero = try #require(LinearAlgebra.pseudoSolve((0 ..< 10).map { [Double($0), 0] }, (0 ..< 10).map { 3 * Double($0) }))
		#expect(abs(zero[0] - 3) <= 1e-12 && zero[1] == 0)
		// x₀ = 1, x₁ = 2 and x₀ + x₁ = 3, whatever the points say.
		let constrained = try #require(LinearAlgebra.leastSquares([[1, 0], [0, 1]], [5, 5], constraints: [[1, 0, 1], [0, 1, 2], [1, 1, 3]]))
		#expect(abs(constrained[0] - 1) <= 1e-12 && abs(constrained[1] - 2) <= 1e-12)
	}
}
