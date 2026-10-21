import AppleEventCore
import Foundation

/// `addlist`, `sublist`, `multlist` and `divlist`: an operation item by item on numbers, lists, arrays, matrices
/// and polynomials, the result of the kind given (as recorded from SatimageOSAX):
///
/// - Lists keep their shape (nested lists too) and must be as long as each other (-50); a number goes with every
///   item. An item that isn't a number (or a result that isn't finite) is `missing value`.
/// - With an array, the result is an array; it keeps NaN and infinities.
/// - A matrix goes with a number or a matrix of its shape (error -1 otherwise); with a list or an array it's -1700.
/// - Polynomials are added as polynomials (a number to the constant term) and multiplied as polynomials. Satimage
///   couldn't divide one by a number (-50), which its dictionary lists; MTC_OSAX can. By a polynomial is -50.
enum Arithmetic {
	enum Operation {
		case add, subtract, multiply, divide

		func callAsFunction(_ x: Double, _ y: Double) -> Double {
			switch self {
			case .add: x + y
			case .subtract: x - y
			case .multiply: x * y
			case .divide: x / y
			}
		}
	}

	/// What the commands take, as given.
	enum Operand {
		case number(Double)
		case list([Operand])
		case array([Double])
		case matrix(Matrix)
		case polynomial([Double])
	}

	@MainActor
	static func commands() -> [CommandDefinition] {
		[("addlist", "SATILST+", Operation.add), ("sublist", "SATILST-", .subtract), ("multlist", "SATILST*", .multiply), ("divlist", "SATILST/", .divide)]
			.map { name, code, operation in
				CommandDefinition(name, code: code) { request in
					let left = try operand(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
					guard let with = request.descriptor(for: "with") else {
						throw OSAXError.missingParameter
					}
					return try descriptor(combine(left, try operand(with), operation))
				}
			}
	}

	/// An item that isn't a number (`true`, text that isn't one) is NaN, as recorded; a record other than a matrix
	/// is -1700.
	static func operand(_ descriptor: NSAppleEventDescriptor, depth: Int = 0) throws -> Operand {
		if let values = ArrayOfReal.values(of: descriptor) {
			return .array(values)
		}
		if let coefficients = ArrayOfReal.values(of: descriptor, type: ArrayOfReal.polynomialType) {
			return .polynomial(coefficients)
		}
		if let matrix = try Matrix(descriptor, depth: depth) {
			return .matrix(matrix)
		}
		if let list = RawList(descriptor) {
			try Values.checkNesting(depth)
			var items: [Operand] = []
			items.reserveCapacity(list.count)
			try list.forEachItem { item in
				try items.append(Values.number(item).map(Operand.number) ?? operand(list.descriptor(item.index), depth: depth + 1))
			}
			return .list(items)
		}
		if descriptor.isRecordDescriptor {
			throw OSAXError.coercionFailed
		}
		return .number((try? Values.number(descriptor)) ?? .nan)
	}

	static func combine(_ left: Operand, _ right: Operand, _ operation: Operation) throws -> Operand {
		switch (left, right) {
		case let (.number(x), .number(y)):
			return .number(operation(x, y))
		case let (.polynomial(p), .polynomial(q)):
			return .polynomial(try polynomial(p, q, operation))
		case let (.polynomial(p), .number(y)):
			return .polynomial(try polynomial(p, number: y, operation))
		case let (.number(x), .polynomial(q)):
			guard operation != .divide else {
				throw OSAXError.parameterError
			}
			return .polynomial(try polynomial([x], q, operation))
		case let (.polynomial(p), other):
			return .polynomial(try polynomial(p, flattened(other), operation))
		case let (other, .polynomial(q)):
			return .polynomial(try polynomial(flattened(other), q, operation))
		case let (.matrix(m), .number(y)):
			return .matrix(Matrix(columns: m.columns, rows: m.rows, values: m.values.map { operation($0, y) }))
		case let (.number(x), .matrix(m)):
			return .matrix(Matrix(columns: m.columns, rows: m.rows, values: m.values.map { operation(x, $0) }))
		case let (.matrix(a), .matrix(b)):
			guard a.columns == b.columns, a.rows == b.rows else {
				throw OSAXError(-1)
			}
			return .matrix(Matrix(columns: a.columns, rows: a.rows, values: try items(a.values, b.values, operation)))
		case (.matrix, _), (_, .matrix):
			throw OSAXError.coercionFailed
		case let (.array(x), .number(y)):
			return .array(x.map { operation($0, y) })
		case let (.number(x), .array(y)):
			return .array(y.map { operation(x, $0) })
		case let (.array(x), other):
			return .array(try items(x, flattened(other), operation))
		case let (other, .array(y)):
			return .array(try items(flattened(other), y, operation))
		case let (.list(items), .number):
			return .list(try items.map { try combine($0, right, operation) })
		case let (.number, .list(items)):
			return .list(try items.map { try combine(left, $0, operation) })
		case let (.list(x), .list(y)):
			guard x.count == y.count else {
				throw OSAXError.parameterError
			}
			return .list(try zip(x, y).map { try combine($0, $1, operation) })
		}
	}

	/// Item by item; -50 unless they're as long as each other.
	private static func items(_ x: [Double], _ y: [Double], _ operation: Operation) throws -> [Double] {
		guard x.count == y.count else {
			throw OSAXError.parameterError
		}
		return zip(x, y).map { operation($0, $1) }
	}

	/// A list's (or array's) numbers, nested lists flattened.
	private static func flattened(_ operand: Operand) -> [Double] {
		switch operand {
		case let .number(value): [value]
		case let .list(items): items.flatMap(flattened)
		case let .array(values), let .polynomial(values): values
		case let .matrix(matrix): matrix.values
		}
	}

	/// Two polynomials (coefficients, constant term first): summed or subtracted term by term (the shorter padded with
	/// zeros), or multiplied as polynomials. Dividing by a polynomial is -50.
	private static func polynomial(_ p: [Double], _ q: [Double], _ operation: Operation) throws -> [Double] {
		switch operation {
		case .add, .subtract:
			return Polynomials.termwise(p, q) { operation($0, $1) }
		case .multiply:
			try Arrays.check(p.count.multipliedReportingOverflow(by: q.count), atMost: Polynomials.maximumProducts, "The number of products of coefficients")
			return Polynomials.multiply(p, q)
		case .divide:
			throw OSAXError.parameterError
		}
	}

	/// A polynomial with a number: added to (or subtracted from) the constant term; multiplying or dividing scales it.
	private static func polynomial(_ p: [Double], number y: Double, _ operation: Operation) throws -> [Double] {
		switch operation {
		case .add, .subtract: try polynomial(p, [y], operation)
		case .multiply, .divide: p.map { operation($0, y) }
		}
	}

	/// A number or list item that isn't finite is `missing value`; arrays and matrices keep NaN and infinities.
	static func descriptor(_ operand: Operand) throws -> NSAppleEventDescriptor {
		switch operand {
		case let .number(value):
			return value.isFinite ? NSAppleEventDescriptor(double: value) : .missingValue
		case let .list(items):
			let list = try ListBuilder()
			for item in items {
				if case let .number(value) = item {
					try value.isFinite ? list.append(value) : list.appendMissingValue()
				} else {
					try list.append(descriptor(item))
				}
			}
			return list.descriptor()
		case let .array(values):
			return try Values.array(values)
		case let .matrix(matrix):
			return try matrix.descriptor()
		case let .polynomial(coefficients):
			return try ArrayOfReal.descriptor(count: coefficients.count, type: ArrayOfReal.polynomialType) { _ = $0.initialize(from: coefficients) }
		}
	}
}
