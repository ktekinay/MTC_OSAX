import AppleEventCore
import Foundation

/// `evalpolynomial`, `roots of`, `composepolynomial`, `pade approximant`, `fitpolynomial` and `fitrational`, as
/// recorded from SatimageOSAX. Polynomials are their coefficients, constant term first: a list, an array or a
/// `polynomial`; results that are polynomials are `polynomial`s.
enum Polynomials {
	@MainActor
	static func commands() -> [CommandDefinition] {
		[
			CommandDefinition("evalpolynomial", code: "SATIEvPo", handler: evaluate),
			CommandDefinition("roots of", code: "SATIRoot", handler: roots),
			CommandDefinition("composepolynomial", code: "SATICoPo") { request in
				let p = try coefficients(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
				guard let with = request.descriptor(for: "with") else {
					throw OSAXError.missingParameter
				}
				let q = try coefficients(with)
				// Its time grows as the square of the result's degree.
				try Arrays.check(max(0, p.count - 1).multipliedReportingOverflow(by: max(0, q.count - 1)), atMost: maximumComposedDegree, "The composed polynomial's degree")
				return try descriptor(compose(p, q))
			},
			CommandDefinition("pade approximant", code: "SATIPade", handler: pade),
			CommandDefinition("fitpolynomial", code: "SATIFiPo", handler: fitPolynomial),
			CommandDefinition("fitrational", code: "SATIRatF", handler: fitRational),
		]
	}

	// Limits that keep the slower algorithms to seconds (and their matrices to megabytes): their time grows as the
	// cube of the degree, or as the product of the polynomials' lengths.
	static let maximumRootsDegree = 1000
	static let maximumPadeDegree = 1000
	static let maximumFitDegree = 100
	static let maximumComposedDegree = 100_000
	static let maximumProducts = 10_000_000_000

	static func coefficients(_ descriptor: NSAppleEventDescriptor) throws -> [Double] {
		try Values.numbers(descriptor)
	}

	static func descriptor(_ coefficients: [Double]) throws -> NSAppleEventDescriptor {
		try ArrayOfReal.descriptor(count: coefficients.count, type: ArrayOfReal.polynomialType) { _ = $0.initialize(from: coefficients) }
	}

	/// P(x) by Horner's rule; the empty polynomial is 0.
	static func value(_ p: [Double], at x: Double) -> Double {
		p.reversed().reduce(0) { $0 * x + $1 }
	}

	// MARK: evalpolynomial, composepolynomial

	/// At a number, a number; at a list or an array, an array.
	static func evaluate(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let p = try coefficients(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		guard let at = request.descriptor(for: "at  ") else {
			throw OSAXError.missingParameter
		}
		if Values.isSeveral(at) {
			return try Values.array(Values.numbers(at).map { value(p, at: $0) })
		}
		return NSAppleEventDescriptor(double: value(p, at: try Values.number(at)))
	}

	/// P(Q(x)), by Horner's rule on polynomials. The empty P is the empty polynomial (SatimageOSAX returned nothing).
	static func compose(_ p: [Double], _ q: [Double]) -> [Double] {
		var result: [Double] = []
		for coefficient in p.reversed() {
			result = add(multiply(result, q), [coefficient])
		}
		return result
	}

	/// The product of two polynomials (their lengths' product is the time it takes).
	static func multiply(_ p: [Double], _ q: [Double]) -> [Double] {
		guard !p.isEmpty, !q.isEmpty else {
			return []
		}
		var product = [Double](repeating: 0, count: p.count + q.count - 1)
		for (i, a) in p.enumerated() {
			for (j, b) in q.enumerated() {
				product[i + j] += a * b
			}
		}
		return product
	}

	static func add(_ p: [Double], _ q: [Double]) -> [Double] {
		termwise(p, q, +)
	}

	/// Coefficient by coefficient, the shorter padded with zeros.
	static func termwise(_ p: [Double], _ q: [Double], _ operation: (Double, Double) -> Double) -> [Double] {
		(0 ..< max(p.count, q.count)).map { operation($0 < p.count ? p[$0] : 0, $0 < q.count ? q[$0] : 0) }
	}

	// MARK: roots of

	/// The roots, in the order SatimageOSAX found them (see `RootFinder`): real roots as reals, and `with complex`
	/// complex ones as `{real, imaginary}`. Zero leading coefficients are left out; a polynomial of degree 0, or with
	/// a coefficient that isn't finite (one infinite made the balancing loop forever), is -50; QR that doesn't
	/// converge is -1.
	static func roots(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		var p = try coefficients(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		while let last = p.last, last == 0 {
			p.removeLast()
		}
		guard p.count >= 2, p.allSatisfy(\.isFinite) else {
			throw OSAXError.parameterError
		}
		try Arrays.check((p.count - 1, false), atMost: maximumRootsDegree, "The degree")
		let complex = try request.parameter("Comp", default: false)
		guard let roots = RootFinder.roots(p) else {
			throw OSAXError(-1)
		}
		return roots.compactMap { root -> NSAppleEventDescriptor? in
			if root.imaginary == 0 {
				return NSAppleEventDescriptor(double: root.real)
			}
			return complex ? [NSAppleEventDescriptor(double: root.real), NSAppleEventDescriptor(double: root.imaginary)].appleEventDescriptor : nil
		}.appleEventDescriptor
	}

	// MARK: pade approximant

	/// {NUM, DEN} with NUM/DEN matching P to its first `numerator + denominator + 1` coefficients and DEN's constant
	/// term 1. Fewer coefficients than that, or no solution, is -1.
	static func pade(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let c = try coefficients(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		guard let numeratorDescriptor = request.descriptor(for: "nume"), let denominatorDescriptor = request.descriptor(for: "deno") else {
			throw OSAXError.missingParameter
		}
		let (m, n) = (try Values.integer(numeratorDescriptor), try Values.integer(denominatorDescriptor))
		guard m >= 0, n >= 0, c.count >= m + n + 1 else {
			throw OSAXError(-1)
		}
		try Arrays.check((max(m, n), false), atMost: maximumPadeDegree, "The numerator's and denominator's degrees")
		func coefficient(_ index: Int) -> Double {
			index >= 0 ? c[index] : 0
		}
		// The denominator's q₁ … qₙ: Σⱼ qⱼ c[k - j] = -c[k] for k = m + 1 … m + n.
		var q = [1.0]
		if n > 0 {
			let matrix = (0 ..< n).map { row in (1 ... n).map { coefficient(m + 1 + row - $0) } }
			let right = (0 ..< n).map { -coefficient(m + 1 + $0) }
			guard let solution = LinearAlgebra.solve(matrix, right) else {
				throw OSAXError(-1)
			}
			q += solution
		}
		let p = (0 ... m).map { k in (0 ... min(k, n)).reduce(0.0) { $0 + q[$1] * coefficient(k - $1) } }
		return [try descriptor(p), try descriptor(q)].appleEventDescriptor
	}

	// MARK: fitpolynomial, fitrational

	/// The points of `{x, y}`: two lists or arrays as long as each other (-50 otherwise; a list of one is -1700),
	/// leaving out points with a missing value.
	private static func points(_ request: AppleEventRequest) throws -> (x: [Double], y: [Double]) {
		let direct = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard let list = RawList(direct), list.count == 2 else {
			throw OSAXError.coercionFailed
		}
		let (x, y) = (try Values.numbers(list.descriptor(0)), try Values.numbers(list.descriptor(1)))
		guard x.count == y.count else {
			throw OSAXError.parameterError
		}
		let kept = x.indices.filter { !x[$0].isNaN && !y[$0].isNaN }
		return (kept.map { x[$0] }, kept.map { y[$0] })
	}

	/// The root-mean-square difference between y and the fit at each point (SatimageOSAX's computation gave about
	/// 1e-8 for some exact fits).
	private static func error(_ points: (x: [Double], y: [Double]), _ fit: (Double) -> Double) -> Double {
		guard !points.x.isEmpty else { return 0 }
		let sum = zip(points.x, points.y).reduce(0.0) { sum, point in
			let difference = point.1 - fit(point.0)
			return sum + difference * difference
		}
		return sqrt(sum / Double(points.x.count))
	}

	/// `{fit error, fit result: coefficients, fit string}`: least squares (the degree at most one less than the
	/// number of points), meeting each constraint {a₀, …, aₙ, b} (a₀c₀ + … + aₙcₙ = b; another size is -1). The fit
	/// string, with `number formatting`, writes each coefficient by the format: "1.2-3.4*x+x^2".
	static func fitPolynomial(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let points = try points(request)
		guard let degreeDescriptor = request.descriptor(for: "degr") else {
			throw OSAXError.missingParameter
		}
		let degree = min(try Values.integer(degreeDescriptor), points.x.count - 1)
		guard degree >= 0 else {
			throw OSAXError(-1)
		}
		try checkFitSize(points.x.count, coefficients: degree + 1, degree: degree)
		let constraints = try request.descriptor(for: "cons").map { descriptor -> [[Double]] in
			guard let list = RawList(descriptor) else { throw OSAXError(-1) }
			return try (0 ..< list.count).map { index in
				let constraint = try Values.numbers(list.descriptor(index))
				guard constraint.count == degree + 2 else { throw OSAXError(-1) }
				return constraint
			}
		} ?? []
		let rows = points.x.map { x in (0 ... degree).map { pow(x, Double($0)) } }
		guard let c = LinearAlgebra.leastSquares(rows, points.y, constraints: constraints) else {
			throw OSAXError(-1)
		}
		var fields: [(RecordFields.Key, NSAppleEventDescriptor)] = [
			(.code("Ferr"), NSAppleEventDescriptor(double: error(points) { value(c, at: $0) })),
			(.code("FRes"), c.map(NSAppleEventDescriptor.init(double:)).appleEventDescriptor),
		]
		if let format = try formatting(request) {
			fields.append((.code("FStr"), NSAppleEventDescriptor(string: formula(c, format: format))))
		}
		return RecordFields(fields).appleEventDescriptor
	}

	/// `{fit error, fit result: {NUM, DEN}, fit string}`: the rational fit with the smallest largest error (DEN's
	/// constant term 1), as SatimageOSAX found it, by Numerical Recipes' `ratlsq` on the points: five rounds of least
	/// squares of y·DEN(x) = NUM(x) (the smallest solution, if there are fewer points than coefficients), each fitting
	/// y plus or minus the mean error so far and weighting each point by its last error, keeping the round whose
	/// largest error is smallest. The fit error is that largest error (recorded: 0.9951 for a fit whose root mean
	/// square error is 0.554). The fit string is "(NUM)/(DEN)".
	static func fitRational(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let points = try points(request)
		guard let numeratorDescriptor = request.descriptor(for: "nume"), let denominatorDescriptor = request.descriptor(for: "deno") else {
			throw OSAXError.missingParameter
		}
		let (m, n) = (try Values.integer(numeratorDescriptor), try Values.integer(denominatorDescriptor))
		guard m >= 0, n >= 0, !points.x.isEmpty else {
			throw OSAXError(-1)
		}
		try checkFitSize(points.x.count, coefficients: m + n + 1, degree: max(m, n))
		let (x, y) = points
		var weights = [Double](repeating: 1, count: x.count)
		var errors = [Double](repeating: 1, count: x.count)
		var meanError = 0.0
		var best: (numerator: [Double], denominator: [Double])?
		var bestError = Double.infinity
		for _ in 0 ..< 5 {
			// Unknowns a₀ … aₘ, b₁ … bₙ: (a₀ + a₁x + …) - b(b₁x + … + bₙxⁿ) = b, with b = y ± the mean error.
			var rows: [[Double]] = []
			var right: [Double] = []
			for i in x.indices {
				let target = weights[i] * (y[i] + (errors[i] < 0 ? -meanError : meanError))
				var power = weights[i]
				var row: [Double] = []
				for _ in 0 ... m {
					row.append(power)
					power *= x[i]
				}
				power = -target
				for _ in 0 ..< n {
					power *= x[i]
					row.append(power)
				}
				rows.append(row)
				right.append(target)
			}
			guard let u = LinearAlgebra.pseudoSolve(rows, right) else {
				throw OSAXError(-1)
			}
			let numerator = Array(u[0 ... m])
			let denominator = [1] + Array(u[(m + 1)...])
			var largest = 0.0, sum = 0.0
			for i in x.indices {
				errors[i] = value(numerator, at: x[i]) / value(denominator, at: x[i]) - y[i]
				weights[i] = abs(errors[i])
				sum += weights[i]
				largest = max(largest, weights[i])
			}
			meanError = sum / Double(x.count)
			if largest <= bestError {
				best = (numerator, denominator)
				bestError = largest
			}
		}
		guard let (numerator, denominator) = best else {
			throw OSAXError(-1)
		}
		var fields: [(RecordFields.Key, NSAppleEventDescriptor)] = [
			(.code("Ferr"), NSAppleEventDescriptor(double: bestError)),
			(.code("FRes"), [try descriptor(numerator), try descriptor(denominator)].appleEventDescriptor),
		]
		if let format = try formatting(request) {
			let text = "(\(formula(numerator, format: format)))/(\(formula(denominator, format: format)))"
			fields.append((.code("FStr"), NSAppleEventDescriptor(string: text)))
		}
		return RecordFields(fields).appleEventDescriptor
	}

	/// A fit's degree at most `maximumFitDegree` (-50), and its matrix of points by coefficients at most
	/// `Arrays.maximumSize` numbers.
	private static func checkFitSize(_ points: Int, coefficients: Int, degree: Int) throws {
		try Arrays.check((degree, false), atMost: maximumFitDegree, "The degree")
		try Arrays.check(points.multipliedReportingOverflow(by: coefficients), atMost: Arrays.maximumSize, "The number of points times the number of coefficients")
	}

	/// The `number formatting`: nil without one (or with an empty one), as SatimageOSAX then gave no fit string.
	private static func formatting(_ request: AppleEventRequest) throws -> RealFormat? {
		guard let descriptor = request.descriptor(for: "Form") else {
			return nil
		}
		let format = try String(appleEventDescriptor: descriptor)
		return format.isEmpty ? nil : try RealFormat(format)
	}

	/// A polynomial as text: each coefficient by the format (but those written without a nonzero digit, "0.0000"),
	/// then `*x` or `*x^k`; a coefficient written "1" leaves out "1*" ("-1" leaves "-"), and terms after the first are
	/// joined with "+" unless they start with "-".
	static func formula(_ c: [Double], format: RealFormat) -> String {
		var text = ""
		for (power, coefficient) in c.enumerated() {
			var number = format.format(coefficient)
			guard number.contains(where: { ("1" ... "9").contains($0) }) else {
				continue
			}
			if power > 0 {
				let variable = power == 1 ? "x" : "x^\(power)"
				number = number == "1" ? variable : number == "-1" ? "-" + variable : number + "*" + variable
			}
			text += text.isEmpty || number.hasPrefix("-") ? number : "+" + number
		}
		return text.isEmpty ? format.format(0) : text
	}
}

/// A C format with one conversion of a real (`%g`, `%.3f`, `%10.4e` …) and any text around it, checked before it's
/// used: another conversion (`%d`, `%s`, `%n`), or more than one, is -50.
struct RealFormat {
	let format: String

	init(_ format: String) throws {
		var conversions = 0
		var characters = Substring(format)
		while let percent = characters.firstIndex(of: "%") {
			characters = characters[characters.index(after: percent)...]
			if characters.first == "%" {
				characters = characters.dropFirst()
				continue
			}
			let specification = characters.prefix { "-+ #0123456789.".contains($0) }
			characters = characters.dropFirst(specification.count)
			guard let conversion = characters.first, "eEfFgGaA".contains(conversion),
			      specification.split(separator: ".", omittingEmptySubsequences: false).count <= 2,
			      specification.filter(\.isNumber).count <= 6
			else {
				throw OSAXError.parameterError
			}
			characters = characters.dropFirst()
			conversions += 1
		}
		guard conversions <= 1 else {
			throw OSAXError.parameterError
		}
		self.format = format
	}

	func format(_ value: Double) -> String {
		let length = withVaList([value]) { vsnprintf(nil, 0, format, $0) }
		guard length > 0 else { return "" }
		var buffer = [CChar](repeating: 0, count: Int(length) + 1)
		_ = withVaList([value]) { vsnprintf(&buffer, buffer.count, format, $0) }
		return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
	}
}
