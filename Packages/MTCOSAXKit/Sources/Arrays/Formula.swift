import AppleEventCore
import Foundation

/// `evalformula`'s language, as SatimageOSAX parsed it (probed and recorded in `Fixtures/Arrays`):
///
/// - Statements separated by `;` or line ends; an assignment (`r = …`) gives its value; the result is the last
///   statement's. `//` starts a comment to the end of the line (SatimageOSAX failed on one with a space in it, or
///   after an expression on the same line).
/// - Operators, loosest first: `|`; `&`; `==` `!=`; `<` `<=` `>` `>=`; `+` `-`; `*` `/`; `^` (left to right: `2^3^2`
///   is 64). Comparisons and logic give 1 or 0; any number but 0 is true.
/// - Unary `-`, `+` and `!` only where an expression starts (the formula, a statement, after `(`, `,` or `=`), and
///   they apply to the power that follows: `-2^2` is -4 and `-2+3` is 1; `1+-2` is a syntax error.
/// - Numbers as C's `strtod` reads them (`.5`, `1e3`, `0x10`); `pi`; names of anything but spaces and operator
///   characters, without regard to case (`X` is `x`, `COS` is `cos`). A variable can be named like a function.
/// - Satimage's error numbers: 2 a missing `)`, 5 an unknown function, 7 an unknown variable, 10 too few
///   arguments, 11 none, 15 an operator (or `)`) where a value goes, 16 anything else unexpected, 17 assigning
///   `pi`, 18 arrays of different sizes, 21 an array function given a number.
enum Formula {
	struct Failure: Error {
		var number: Int
	}

	/// A value: a number, or an array of them.
	enum Value: Sendable {
		case number(Double)
		case array([Double])

		var count: Int {
			switch self {
			case .number: 1
			case let .array(values): values.count
			}
		}

		var values: [Double] {
			switch self {
			case let .number(value): [value]
			case let .array(values): values
			}
		}
	}

	indirect enum Node {
		case number(Double)
		case variable(String)
		case unary(UInt8, Node)
		case binary(Operator, Node, Node)
		case call(Function, [Node])
	}

	struct Statement {
		var target: String?
		var expression: Node
	}

	enum Operator: String {
		case or = "|", and = "&", equal = "==", notEqual = "!=", less = "<", lessOrEqual = "<=", greater = ">"
		case greaterOrEqual = ">=", add = "+", subtract = "-", multiply = "*", divide = "/", power = "^"

		/// Loosest first.
		static let levels: [[Operator]] = [[.or], [.and], [.equal, .notEqual], [.less, .lessOrEqual, .greater, .greaterOrEqual], [.add, .subtract], [.multiply, .divide], [.power]]

		func callAsFunction(_ x: Double, _ y: Double) -> Double {
			switch self {
			case .or: (x != 0 || y != 0) ? 1 : 0
			case .and: (x != 0 && y != 0) ? 1 : 0
			case .equal: x == y ? 1 : 0
			case .notEqual: x != y ? 1 : 0
			case .less: x < y ? 1 : 0
			case .lessOrEqual: x <= y ? 1 : 0
			case .greater: x > y ? 1 : 0
			case .greaterOrEqual: x >= y ? 1 : 0
			case .add: x + y
			case .subtract: x - y
			case .multiply: x * y
			case .divide: x / y
			case .power: pow(x, y)
			}
		}
	}

	// MARK: Tokens

	enum Token: Equatable {
		case number(Double)
		case name(String)
		case symbol(String)
		case separator
		case end
	}

	static let symbolCharacters = Set("+-*/^<>=!&|(),;".utf8)

	/// The formula's tokens. A number that `strtod` can't read (`.`) is error 16.
	static func tokens(_ formula: String) throws -> [Token] {
		let bytes = Array(formula.utf8) + [0]
		var tokens: [Token] = []
		var index = 0
		while bytes[index] != 0 {
			let byte = bytes[index]
			switch byte {
			case UInt8(ascii: " "), UInt8(ascii: "\t"):
				index += 1
			case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: ";"):
				tokens.append(.separator)
				index += 1
			case UInt8(ascii: "/") where bytes[index + 1] == UInt8(ascii: "/"):
				while bytes[index] != 0, bytes[index] != UInt8(ascii: "\n"), bytes[index] != UInt8(ascii: "\r") {
					index += 1
				}
			case UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "."):
				let (value, length) = bytes.withUnsafeBufferPointer { buffer -> (Double, Int) in
					buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { start in
						var end: UnsafeMutablePointer<CChar>?
						let value = strtod(start + index, &end)
						return (value, end.map { UnsafePointer($0) - (start + index) } ?? 0)
					}
				}
				guard length > 0 else {
					throw Failure(number: 16)
				}
				tokens.append(.number(value))
				index += length
			case _ where symbolCharacters.contains(byte):
				let pair = String(decoding: bytes[index ... index + 1], as: UTF8.self)
				if ["==", "!=", "<=", ">="].contains(pair) {
					tokens.append(.symbol(pair))
					index += 2
				} else {
					tokens.append(.symbol(String(UnicodeScalar(byte))))
					index += 1
				}
			default:
				let start = index
				while bytes[index] != 0, !symbolCharacters.contains(bytes[index]),
				      ![UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r")].contains(bytes[index])
				{
					index += 1
				}
				tokens.append(.name(String(decoding: bytes[start ..< index], as: UTF8.self).lowercased()))
			}
		}
		tokens.append(.end)
		return tokens
	}

	// MARK: Parsing

	/// The formula's statements; error -50 if it has none.
	static func parse(_ formula: String) throws -> [Statement] {
		var parser = Parser(tokens: try tokens(formula))
		let statements = try parser.statements()
		guard !statements.isEmpty else {
			throw OSAXError.parameterError
		}
		return statements
	}

	struct Parser {
		var tokens: [Token]
		var position = 0

		var current: Token { tokens[position] }

		mutating func statements() throws -> [Statement] {
			var statements: [Statement] = []
			while current != .end {
				if current == .separator {
					position += 1
					continue
				}
				var target: String?
				if case let .name(name) = current, tokens[position + 1] == .symbol("=") {
					guard name != "pi" else {
						throw Failure(number: 17)
					}
					target = name
					position += 2
				}
				statements.append(Statement(target: target, expression: try expression(level: 0, unary: true)))
				// A statement ends at a separator or the end ("1 2", "2x", "sqrt 4" aren't formulas).
				guard current == .separator || current == .end else {
					throw Failure(number: 16)
				}
			}
			return statements
		}

		/// Operators of `level` and tighter. `unary`: a unary operator may begin it.
		mutating func expression(level: Int, unary: Bool) throws -> Node {
			guard level < Operator.levels.count else {
				return try operand(unary: unary)
			}
			var left = try expression(level: level + 1, unary: unary)
			while case let .symbol(symbol) = current, let op = Operator(rawValue: symbol), Operator.levels[level].contains(op) {
				position += 1
				left = .binary(op, left, try expression(level: level + 1, unary: false))
			}
			return left
		}

		/// A value, with the unary operators before it (where they're allowed) applying to it and any `^` after it.
		mutating func operand(unary: Bool) throws -> Node {
			if unary, case let .symbol(symbol) = current, ["-", "+", "!"].contains(symbol) {
				position += 1
				var node = try operand(unary: true)
				while case let .symbol(next) = current, next == "^" {
					position += 1
					node = .binary(.power, node, try primary())
				}
				return .unary(symbol.utf8.first!, node)
			}
			var node = try primary()
			while case let .symbol(next) = current, next == "^" {
				position += 1
				node = .binary(.power, node, try primary())
			}
			return node
		}

		mutating func primary() throws -> Node {
			switch current {
			case let .number(value):
				position += 1
				return .number(value)
			case let .name(name):
				position += 1
				guard current == .symbol("(") else {
					return .variable(name)
				}
				guard let function = Function.named[name] else {
					throw Failure(number: 5)
				}
				position += 1
				var arguments: [Node] = []
				if current != .symbol(")") {
					while true {
						arguments.append(try expression(level: 0, unary: true))
						guard current == .symbol(",") else { break }
						position += 1
					}
				}
				guard current == .symbol(")") else {
					throw Failure(number: current == .end || current == .separator ? 2 : 16)
				}
				position += 1
				guard function.arity.contains(arguments.count) else {
					throw Failure(number: arguments.isEmpty ? 11 : arguments.count < function.arity.lowerBound ? 10 : 16)
				}
				return .call(function, arguments)
			case .symbol("("):
				position += 1
				let node = try expression(level: 0, unary: true)
				guard current == .symbol(")") else {
					throw Failure(number: current == .end || current == .separator ? 2 : 16)
				}
				position += 1
				return node
			case .symbol("-"):
				// A minus where it can't be unary ("1+-2", "2^-1").
				throw Failure(number: 16)
			case .symbol:
				throw Failure(number: 15)
			case .separator, .end:
				throw Failure(number: 16)
			}
		}
	}

	// MARK: Evaluating

	struct Evaluator {
		var variables: [String: Value]

		/// The last statement's value.
		mutating func run(_ statements: [Statement]) throws -> Value {
			var result = Value.number(0)
			for statement in statements {
				result = try value(statement.expression)
				if let target = statement.target {
					variables[target] = result
				}
			}
			return result
		}

		func value(_ node: Node) throws -> Value {
			switch node {
			case let .number(value):
				return .number(value)
			case let .variable(name):
				if let value = variables[name] {
					return value
				}
				guard name == "pi" else {
					throw Failure(number: 7)
				}
				return .number(.pi)
			case let .unary(symbol, operand):
				let value = try value(operand)
				switch symbol {
				case UInt8(ascii: "-"): return Formula.map(value) { -$0 }
				case UInt8(ascii: "!"): return Formula.map(value) { $0 == 0 ? 1 : 0 }
				default: return value
				}
			case let .binary(op, left, right):
				return try Formula.combine(value(left), value(right)) { op($0, $1) }
			case let .call(function, arguments):
				return try function.evaluate(arguments.map(value))
			}
		}
	}

	static func map(_ value: Value, _ function: (Double) -> Double) -> Value {
		switch value {
		case let .number(x): .number(function(x))
		case let .array(values): .array(values.map(function))
		}
	}

	/// Item by item, a number going with every item of an array; arrays of different sizes are error 18.
	static func combine(_ left: Value, _ right: Value, _ function: (Double, Double) -> Double) throws -> Value {
		switch (left, right) {
		case let (.number(x), .number(y)):
			return .number(function(x, y))
		case let (.number(x), .array(y)):
			return .array(y.map { function(x, $0) })
		case let (.array(x), .number(y)):
			return .array(x.map { function($0, y) })
		case let (.array(x), .array(y)):
			guard x.count == y.count else {
				throw Failure(number: 18)
			}
			return .array(zip(x, y).map(function))
		}
	}
}
