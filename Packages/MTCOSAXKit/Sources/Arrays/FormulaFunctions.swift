import AppleEventCore
import Foundation
import Numerics

extension Formula {
	/// A function a formula can call: on each number (with a number going with every item of an array), or on whole
	/// arrays.
	struct Function: Sendable {
		var arity: ClosedRange<Int>
		var evaluate: @Sendable ([Value]) throws -> Value

		static func each(_ function: @escaping @Sendable (Double) -> Double) -> Function {
			Function(arity: 1 ... 1) { Formula.map($0[0], function) }
		}

		static func each(_ function: @escaping @Sendable (Double, Double) -> Double) -> Function {
			Function(arity: 2 ... 2) { try Formula.combine($0[0], $0[1], function) }
		}

		/// Names in lowercase, as formulas are read.
		static let named: [String: Function] = {
			var functions: [String: Function] = [
				// Algebra
				"cbrt": each(cbrt), "sqr": each { $0 * $0 }, "sqrt": each(sqrt), "hypot": each(hypot), "pow": each(pow),
				"sign": each { $0 > 0 ? 1 : $0 < 0 ? -1 : $0 }, "abs": each(fabs), "ceil": each(ceil), "floor": each(floor),
				"trunc": each(trunc), "mod": each(fmod), "remainder": each(remainder),
				"isnan": each { $0.isNaN ? 1 : 0 }, "replacenan": each { $0.isNaN ? $1 : $0 },
				// Transcendental
				"ln": each(log), "log": each(log), "log10": each(log10), "log1p": each(log1p), "exp": each(exp),
				"expm1": each(expm1), "cos": each(cos), "sin": each(sin), "tan": each(tan), "acos": each(acos),
				"asin": each(asin), "atan": each(atan), "atan2": each(atan2), "cosh": each(cosh), "sinh": each(sinh),
				"tanh": each(tanh), "acosh": each(acosh), "asinh": each(asinh), "atanh": each(atanh), "erf": each(erf),
				"erfc": each(erfc), "gamma": each(tgamma), "lgamma": each(lgamma),
				"j0": each(j0), "j1": each(j1), "y0": each(y0), "y1": each(y1),
				"jn": each { n, x in jn(Int32(clamping: Int(exactly: n.rounded(.towardZero)) ?? 0), x) },
				"yn": each { n, x in yn(Int32(clamping: Int(exactly: n.rounded(.towardZero)) ?? 0), x) },
				// GSL's elliptic integrals, of the modulus k, and Lambert's W
				"elliptick": each(SpecialFunctions.completeK), "elliptice": each(SpecialFunctions.completeE),
				"incelliptice": each(SpecialFunctions.incompleteE), "incellipticf": each(SpecialFunctions.incompleteF),
				"ellipticp": each(SpecialFunctions.completeP),
				"lambertw0": each(SpecialFunctions.lambertW0), "lambertwm1": each(SpecialFunctions.lambertWm1),
			]
			functions["incellipticp"] = Function(arity: 3 ... 3) { arguments in
				// The shape of the three together (arrays of different sizes are error 18).
				try Formula.combine(Formula.combine(arguments[0], arguments[1]) { x, _ in x }, arguments[2]) { x, _ in x }
					.indexedMap { index in
						SpecialFunctions.incompleteP(arguments[0].item(index), arguments[1].item(index), arguments[2].item(index))
					}
			}
			// max and min: of two (item by item), or of one array's numbers.
			functions["max"] = Function(arity: 1 ... 2) { arguments in
				arguments.count == 2 ? try Formula.combine(arguments[0], arguments[1], fmax) : .number(arguments[0].values.reduce(-.infinity, fmax))
			}
			functions["min"] = Function(arity: 1 ... 2) { arguments in
				arguments.count == 2 ? try Formula.combine(arguments[0], arguments[1], fmin) : .number(arguments[0].values.reduce(.infinity, fmin))
			}
			// On whole arrays (a number is an array of one).
			functions["norm"] = Function(arity: 1 ... 1) { .number(sqrt($0[0].values.reduce(0) { $0 + $1 * $1 })) }
			functions["norm2"] = Function(arity: 1 ... 1) { .number($0[0].values.reduce(0) { $0 + $1 * $1 }) }
			functions["sum"] = Function(arity: 1 ... 1) { .number($0[0].values.reduce(0, +)) }
			functions["count"] = Function(arity: 1 ... 1) { .number(Double($0[0].count)) }
			functions["runsum"] = Function(arity: 1 ... 1) { arguments in
				guard case let .array(values) = arguments[0] else { return arguments[0] }
				var sum = 0.0
				return .array(values.map { sum += $0; return sum })
			}
			functions["diff"] = Function(arity: 1 ... 1) { arguments in
				let values = arguments[0].values
				return .array(values.count < 2 ? [] : (1 ..< values.count).map { values[$0] - values[$0 - 1] })
			}
			functions["rest"] = Function(arity: 1 ... 1) { .array(Array($0[0].values.dropFirst())) }
			functions["butlast"] = Function(arity: 1 ... 1) { .array(Array($0[0].values.dropLast())) }
			functions["concat"] = Function(arity: 2 ... 2) { .array($0[0].values + $0[1].values) }
			// ∫f dx by trapezoids, as the dictionary says: SatimageOSAX computed ∫x df (its arguments the other way
			// around). Arrays only (error 21), of the same size (18).
			functions["int"] = Function(arity: 2 ... 2) { arguments in
				guard case let .array(f) = arguments[0], case let .array(x) = arguments[1] else {
					throw Failure(number: 21)
				}
				guard f.count == x.count else {
					throw Failure(number: 18)
				}
				var integral = 0.0
				for index in x.indices.dropFirst() {
					integral += (f[index] + f[index - 1]) / 2 * (x[index] - x[index - 1])
				}
				return .number(integral)
			}
			return functions
		}()
	}
}

extension Formula.Value {
	/// The number at `index`: an array's item, or a number for every index.
	func item(_ index: Int) -> Double {
		switch self {
		case let .number(value): value
		case let .array(values): values[index]
		}
	}

	/// A value of this one's shape, each number from `transform` of its index.
	func indexedMap(_ transform: (Int) -> Double) -> Formula.Value {
		switch self {
		case .number: .number(transform(0))
		case let .array(values): .array(values.indices.map(transform))
		}
	}
}

// MARK: evalformula

extension Formula {
	/// `evalformula`: a formula (or a list of them, for a list of results) with variables from a list of names and
	/// values or a record. A result is a real (NaN and infinities too) or an `array of real` (an empty one is an empty
	/// list); with `as matrix`, an array the size of a matrix variable is that matrix.
	@MainActor
	static func command() -> CommandDefinition {
		CommandDefinition("evalformula", code: "SATILSOP") { request in
			let direct = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
			var shape: Matrix?
			let variables = try request.descriptor(for: "with").map { try self.variables($0, shape: &shape) } ?? [:]
			let asMatrix = request.descriptor(for: "rtyp")?.typeCodeValue == Matrix.descriptorType
			func evaluate(_ formula: String) throws -> NSAppleEventDescriptor {
				var evaluator = Evaluator(variables: variables)
				let result: Value
				do {
					result = try evaluator.run(parse(formula))
				} catch let failure as Failure {
					throw OSAXError(failure.number)
				}
				switch result {
				case let .number(value):
					return NSAppleEventDescriptor(double: value)
				case let .array(values):
					if values.isEmpty {
						return NSAppleEventDescriptor.list()
					}
					if asMatrix, let shape, shape.values.count == values.count {
						return try Matrix(columns: shape.columns, rows: shape.rows, values: values).descriptor()
					}
					return try Values.array(values)
				}
			}
			if let formulas = RawList(direct) {
				return try (0 ..< formulas.count).map { try evaluate(String(appleEventDescriptor: formulas.descriptor($0))) }.appleEventDescriptor
			}
			return try evaluate(String(appleEventDescriptor: direct))
		}
	}

	/// The variables, by lowercase name: from a list of names and values (a name without a value is left out), or a
	/// record's own properties. `shape` is the first matrix among them.
	static func variables(_ descriptor: NSAppleEventDescriptor, shape: inout Matrix?) throws -> [String: Value] {
		var pairs: [(String, NSAppleEventDescriptor)] = []
		if let list = RawList(descriptor) {
			var index = 0
			while index + 1 < list.count {
				pairs.append((try String(appleEventDescriptor: list.descriptor(index)), list.descriptor(index + 1)))
				index += 2
			}
		} else if let record = RecordFields(descriptor) {
			for (key, value) in record.fields {
				if case let .user(name) = key {
					pairs.append((name, value))
				}
			}
		}
		var variables: [String: Value] = [:]
		for (name, descriptor) in pairs {
			if let matrix = try Matrix(descriptor) {
				shape = shape ?? matrix
			}
			// An empty list leaves the variable undefined, as recorded (error 7 where it's used).
			if let value = try value(descriptor), value.count > 0 || value.isNumber {
				variables[name.lowercased()] = value
			}
		}
		return variables
	}

	/// A variable's value: a number (text that reads as one; other text is -50, anything else -1700) or several
	/// (a list, whose items that aren't numbers are NaN, an array, a polynomial or a matrix). One number in a list is
	/// a number, as recorded (`IncEllipticF(x,k)` with `{x:{0.5}, k:{0.5}}` is a real).
	private static func value(_ descriptor: NSAppleEventDescriptor) throws -> Value? {
		if Values.isSeveral(descriptor) {
			let values = try lenientNumbers(descriptor)
			return values.count == 1 ? .number(values[0]) : .array(values)
		}
		if descriptor.descriptorType == typeType, descriptor.typeCodeValue == Values.missingValue {
			return .number(.nan)
		}
		if descriptor.isText {
			return .number(try Values.number(descriptor))
		}
		return .number(try Numbers.number(descriptor))
	}

	/// The numbers in a list, NaN for an item that isn't one.
	private static func lenientNumbers(_ descriptor: NSAppleEventDescriptor) throws -> [Double] {
		guard let list = RawList(descriptor), ArrayOfReal.values(of: descriptor) == nil else {
			return try Values.numbers(descriptor)
		}
		var result: [Double] = []
		for index in 0 ..< list.count {
			let item = list.descriptor(index)
			if Values.isSeveral(item) {
				result += try lenientNumbers(item)
			} else {
				result.append((try? Values.number(item)) ?? .nan)
			}
		}
		return result
	}
}

private extension Formula.Value {
	var isNumber: Bool {
		if case .number = self { true } else { false }
	}
}
