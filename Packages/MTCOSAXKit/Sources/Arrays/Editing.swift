import AppleEventCore
import Foundation
import Numerics

/// Making, reading and changing arrays: `creatematrix`, `extractarray`, `changearray`, `insertarray`, `reversearray`,
/// `maskarray`, `replacemissingvalue` and `removemissingvalue`. Indexes are 1-based, as in AppleScript; an index or
/// a block outside the array is -1719 (`errAEIllegalIndex`), and blocks that run past its end in `extractarray`
/// are Satimage's error 2000, as recorded.
enum Editing {
	static let invalidIndex = OSAXError(-1719)
	static let pastTheEnd = OSAXError(2000)
	static let matrixTooLarge = OSAXError(-50, "A matrix can have at most \(Arrays.grouped(Arrays.maximumSize)) items.")

	@MainActor
	static func commands() -> [CommandDefinition] {
		[
			CommandDefinition("creatematrix", code: "SATICRMT", handler: createMatrix),
			CommandDefinition("extractarray", code: "SATIExLF", handler: extract),
			CommandDefinition("changearray", code: "SATISeLF", handler: change),
			CommandDefinition("insertarray", code: "SATIInLF", handler: insert),
			CommandDefinition("reversearray", code: "SATILiRe", handler: reverse),
			CommandDefinition("maskarray", code: "SATIMASK", handler: mask),
			CommandDefinition("replacemissingvalue", code: "SATIFILL") { request in
				guard let with = request.descriptor(for: "with") else {
					throw OSAXError.missingParameter
				}
				// `missing value` (or a NaN) as the replacement is -1700, as recorded.
				let value = try Numbers.number(with)
				return try replacingMissing(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor, with: value)
			},
			CommandDefinition("removemissingvalue", code: "SATIRmMv") { request in
				try replacingMissing(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor, with: nil)
			},
		]
	}

	// MARK: creatematrix

	/// "1": every number 1; "x": each row the same (the column's x); "y": each column the same; "d": a diagonal
	/// square matrix. `ncols` with "x" (and `nrows` with "y") can be the numbers themselves; otherwise they're
	/// spread over `range` (0, 1, 2, … without one).
	static func createMatrix(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let kind = try request.requiredDirectParameter(as: String.self).lowercased()
		let asMatrix = request.descriptor(for: "rtyp")?.typeCodeValue == Matrix.descriptorType
		let matrix: Matrix
		switch kind {
		case "d":
			matrix = try diagonal(request)
		case "1", "x", "y":
			let columns = try axis(request, "ncol", isValues: kind == "x")
			let rows = try axis(request, "nrow", isValues: kind == "y")
			guard columns.count * rows.count <= Arrays.maximumSize else {
				throw Arrays.tooLarge
			}
			var values = [Double](repeating: 1, count: columns.count * rows.count)
			if kind != "1" {
				let (columns, rows) = (columns.values, rows.values)
				for row in 0 ..< rows.count {
					for column in 0 ..< columns.count {
						values[row * columns.count + column] = kind == "x" ? columns[column] : rows[row]
					}
				}
			}
			matrix = Matrix(columns: columns.count, rows: rows.count, values: values)
		default:
			throw OSAXError.parameterError
		}
		return asMatrix ? try matrix.descriptor() : try Values.array(matrix.values)
	}

	/// A dimension's values: the numbers given, or `count` of them from `low`, `step` apart, made only once they're
	/// needed (so that two axes too large together are refused before either is made).
	private enum Axis {
		case values([Double])
		case spread(count: Int, low: Double, step: Double)

		var count: Int {
			switch self {
			case let .values(values): values.count
			case let .spread(count, _, _): count
			}
		}

		var values: [Double] {
			switch self {
			case let .values(values): values
			case let .spread(count, low, step): (0 ..< count).map { low + Double($0) * step }
			}
		}
	}

	/// The numbers given (for "x"'s `ncols` or "y"'s `nrows`), or a size, as 0, 1, 2, … or spread over `range`. A
	/// size below 1 is -1700, as recorded.
	private static func axis(_ request: AppleEventRequest, _ keyword: String, isValues: Bool) throws -> Axis {
		guard let descriptor = request.descriptor(for: keyword) else {
			throw OSAXError.missingParameter
		}
		if isValues, Values.isSeveral(descriptor) {
			return .values(try Values.numbers(descriptor))
		}
		let count = try Values.integer(descriptor)
		guard count >= 1 else {
			throw OSAXError.coercionFailed
		}
		guard count <= Arrays.maximumSize else {
			throw Arrays.tooLarge
		}
		let (low, high) = try Arrays.range(request) ?? (0, Double(count - 1))
		return .spread(count: count, low: low, step: count > 1 ? (high - low) / Double(count - 1) : 0)
	}

	/// "d": the `diagonal` numbers (a list or array makes the size), or one number (default 1) on the diagonal of
	/// an `ncols` × `nrows` matrix, which must be square (-50 otherwise).
	private static func diagonal(_ request: AppleEventRequest) throws -> Matrix {
		let given = request.descriptor(for: "Diag")
		var diagonal: [Double]
		if let given, Values.isSeveral(given) {
			diagonal = try Values.numbers(given)
			guard diagonal.count <= Arrays.maximumSide else {
				throw matrixTooLarge
			}
		} else {
			let value = try given.map(Values.number) ?? 1
			let columns = try request.descriptor(for: "ncol").map(Values.integer)
			let rows = try request.descriptor(for: "nrow").map(Values.integer)
			guard let size = columns ?? rows, columns == nil || rows == nil || columns == rows else {
				throw columns == nil && rows == nil ? OSAXError.missingParameter : OSAXError.parameterError
			}
			guard size >= 1 else {
				throw OSAXError.coercionFailed
			}
			guard size <= Arrays.maximumSide else {
				throw matrixTooLarge
			}
			diagonal = Array(repeating: value, count: size)
		}
		let size = diagonal.count
		var values = [Double](repeating: 0, count: size * size)
		for index in 0 ..< size {
			values[index * size + index] = diagonal[index]
		}
		return Matrix(columns: size, rows: size, values: values)
	}

	// MARK: extractarray

	/// Blocks of `blocksize` items, `step` apart (default `blocksize`), `for` of them (default 1, negative: as many
	/// as fit), from item `at` (default 1, negative counts from the end); or the items at a list of indexes. An empty
	/// result is an empty list. `as`: `list of real` or `list of integer` for a list (NaN is `missing value`; an
	/// integer rounds half to even, and one beyond 32 bits is -1700), `real` or `integer` for the first number.
	static func extract(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let values = try Values.numbers(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		let picked: [Double]
		if let at = request.descriptor(for: "at  "), at.descriptorType == typeAEList {
			picked = try Values.numbers(at).map { index in
				let position = try position(index, count: values.count)
				return values[position]
			}
		} else {
			let blocks = try Blocks(request, count: values.count)
			var count = try request.descriptor(for: "for ").map(Values.integer) ?? 1
			if count < 0 {
				// As many blocks as fit; none is error 2000, as recorded.
				count = blocks.step > 0 ? (values.count - blocks.start - blocks.size) / blocks.step + 1 : 1
				guard count > 0, values.count - blocks.start - blocks.size >= 0 else {
					throw pastTheEnd
				}
			}
			guard blocks.contains(start: values.count) || count == 0, blocks.isValid else {
				throw invalidIndex
			}
			guard blocks.fit(count, in: values.count) else {
				throw pastTheEnd
			}
			var result: [Double] = []
			result.reserveCapacity(count * blocks.size)
			for block in 0 ..< count {
				result += values[blocks.range(block)]
			}
			picked = result
		}
		guard !picked.isEmpty else {
			return NSAppleEventDescriptor.list()
		}
		switch request.descriptor(for: "rtyp")?.typeCodeValue.fourCharString {
		case "LiDo": return try Values.listOfReals(picked)
		case "LiIn": return try listOfIntegers(picked)
		case "doub", "sing": return picked[0].isNaN ? .missingValue : NSAppleEventDescriptor(double: picked[0])
		case "long": return try listOfIntegers([picked[0]]).atIndex(1)!
		default: return try Values.array(picked)
		}
	}

	/// A 1-based index (negative from the end) as a position in `count` items; -1719 outside them.
	private static func position(_ index: Double, count: Int) throws -> Int {
		let rounded = index.rounded(.toNearestOrEven)
		guard rounded.isFinite, rounded.magnitude <= Double(Int32.max) else {
			throw invalidIndex
		}
		let position = rounded < 0 ? count + Int(rounded) : Int(rounded) - 1
		guard (0 ..< count).contains(position) else {
			throw invalidIndex
		}
		return position
	}

	/// Integers rounded half to even (as AppleScript's `as integer`); NaN is `missing value`. SatimageOSAX wrapped
	/// numbers beyond 32 bits (1.0E+10 became 1410065408); that's -1700, as `as integer` is in AppleScript.
	private static func listOfIntegers(_ values: [Double]) throws -> NSAppleEventDescriptor {
		let list = try ListBuilder()
		for value in values {
			guard !value.isNaN else {
				try list.appendMissingValue()
				continue
			}
			let rounded = value.rounded(.toNearestOrEven)
			guard rounded >= Double(Int32.min), rounded <= Double(Int32.max) else {
				throw OSAXError.coercionFailed
			}
			try list.append(Int32(rounded))
		}
		return list.descriptor()
	}

	// MARK: changearray

	/// `into`'s numbers replace items: at a list of indexes (as many as numbers, -50 otherwise), or in blocks of
	/// `blocksize` (default 1), `step` apart (default `blocksize`), from `at` (default 1). A block outside the array,
	/// or numbers that aren't a whole number of blocks, is -1719.
	static func change(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		var values = try Values.numbers(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		guard let intoDescriptor = request.descriptor(for: "into") else {
			throw OSAXError.missingParameter
		}
		let into = try Values.numbers(intoDescriptor)
		if let at = request.descriptor(for: "at  "), at.descriptorType == typeAEList {
			let indexes = try Values.numbers(at)
			guard indexes.count == into.count else {
				throw OSAXError.parameterError
			}
			for (index, value) in zip(indexes, into) {
				values[try position(index, count: values.count)] = value
			}
			return try Values.array(values)
		}
		let blocks = try Blocks(request, count: values.count)
		guard blocks.isValid, into.count % blocks.size == 0, blocks.contains(start: values.count) else {
			throw invalidIndex
		}
		let count = into.count / blocks.size
		guard blocks.fit(count, in: values.count) else {
			throw invalidIndex
		}
		// Item by item: assigning a slice for each block took twice as long for blocks of one.
		for block in 0 ..< count {
			let start = blocks.range(block).lowerBound
			for offset in 0 ..< blocks.size {
				values[start + offset] = into[block * blocks.size + offset]
			}
		}
		return try Values.array(values)
	}

	/// `blocksize` (default 1), `step` (default `blocksize`) and `at` (default 1, negative from the end), as
	/// `extractarray` and `changearray` read them, for an array of `count` items.
	private struct Blocks {
		var size: Int
		var step: Int
		var start: Int

		init(_ request: AppleEventRequest, count: Int) throws {
			size = try request.descriptor(for: "bloc").map(Values.integer) ?? 1
			step = try request.descriptor(for: "step").map(Values.integer) ?? size
			let at = try request.descriptor(for: "at  ").map(Values.integer) ?? 1
			start = at < 0 ? count + at : at - 1
		}

		/// At least one item long, and not overlapping.
		var isValid: Bool {
			size >= 1 && step >= size
		}

		/// Whether the first block starts inside `count` items.
		func contains(start count: Int) -> Bool {
			(0 ..< count).contains(start)
		}

		/// Whether `blocks` of them end inside `count` items.
		func fit(_ blocks: Int, in count: Int) -> Bool {
			blocks == 0 || start + (blocks - 1) * step + size <= count
		}

		func range(_ block: Int) -> Range<Int> {
			start + block * step ..< start + block * step + size
		}
	}

	// MARK: insertarray

	/// Inserts the direct parameter's numbers into `into`: after item `at` (0 is the beginning; default -1, the end),
	/// `for` blocks (default 1) of `blocksize` numbers (default 1 with `for`, all of them without), each `step`
	/// items of `into` after the one before; or each number after the item its index in a list of `at` names (as many
	/// as numbers, -50 otherwise). A place past the end, or too few numbers for the blocks, is -1719.
	static func insert(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let inserted = try Values.numbers(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		guard let intoDescriptor = request.descriptor(for: "into") else {
			throw OSAXError.missingParameter
		}
		let target = try Values.numbers(intoDescriptor)
		// Each number with the count of `into`'s items to put it after.
		var places: [(after: Int, value: Double)] = []
		if let at = request.descriptor(for: "at  "), at.descriptorType == typeAEList {
			let positions = try Values.numbers(at)
			guard positions.count == inserted.count else {
				throw OSAXError.parameterError
			}
			places = try zip(positions, inserted).map { position, value in
				let after = position.rounded(.toNearestOrEven)
				guard after >= 0, after <= Double(target.count) else {
					throw invalidIndex
				}
				return (Int(after), value)
			}
		} else {
			let given = request.descriptor(for: "for ")
			let blocks = try given.map(Values.integer) ?? 1
			let blocksize = try request.descriptor(for: "bloc").map(Values.integer) ?? (given == nil ? inserted.count : 1)
			let step = try request.descriptor(for: "step").map(Values.integer) ?? 0
			let at = try request.descriptor(for: "at  ").map(Values.integer) ?? -1
			let first = at < 0 ? target.count + at + 1 : at
			guard blocks >= 0, blocksize >= 0, step >= 0, blocks * blocksize <= inserted.count, first >= 0,
			      blocks == 0 || first + (blocks - 1) * step <= target.count
			else {
				throw invalidIndex
			}
			for block in 0 ..< blocks {
				for offset in 0 ..< blocksize {
					places.append((first + block * step, inserted[block * blocksize + offset]))
				}
			}
		}
		// In order of place, numbers for the same place in the order given.
		let ordered = places.enumerated().sorted { ($0.element.after, $0.offset) < ($1.element.after, $1.offset) }.map(\.element)
		var result: [Double] = []
		result.reserveCapacity(target.count + ordered.count)
		var next = 0
		for item in 0 ... target.count {
			while next < ordered.count, ordered[next].after == item {
				result.append(ordered[next].value)
				next += 1
			}
			if item < target.count {
				result.append(target[item])
			}
		}
		return try Values.array(result)
	}

	// MARK: reversearray, maskarray

	/// An array in reverse order; a matrix with its rows in reverse order.
	static func reverse(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		if let matrix = try Matrix(descriptor) {
			let values = (0 ..< matrix.rows).reversed().flatMap { matrix.row($0) }
			return try Matrix(columns: matrix.columns, rows: matrix.rows, values: values).descriptor()
		}
		return try Values.array(Values.numbers(descriptor).reversed())
	}

	/// Keeps the items whose number in the mask isn't 0 (NaN keeps); the mask is as long as the array (-50 otherwise).
	/// A matrix keeps rows; a list of arrays (or lists) gives a list of each masked.
	static func mask(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard let maskDescriptor = request.descriptor(for: "with") else {
			throw OSAXError.missingParameter
		}
		let mask = try Values.numbers(maskDescriptor).map { $0 != 0 }
		func masked(_ values: [Double]) throws -> [Double] {
			guard values.count == mask.count else {
				throw OSAXError.parameterError
			}
			return zip(values, mask).compactMap { $1 ? $0 : nil }
		}
		if let matrix = try Matrix(descriptor) {
			guard matrix.rows == mask.count else {
				throw OSAXError.parameterError
			}
			let rows = (0 ..< matrix.rows).filter { mask[$0] }
			return try Matrix(columns: matrix.columns, rows: rows.count, values: rows.flatMap { matrix.row($0) }).descriptor()
		}
		if let list = RawList(descriptor), list.count > 0, (0 ..< list.count).allSatisfy({ Values.severalTypes.contains(list.info($0).type) }) {
			return try (0 ..< list.count).map { try Values.array(masked(Values.numbers(list.descriptor($0)))) }.appleEventDescriptor
		}
		return try Values.array(masked(Values.numbers(descriptor)))
	}

	// MARK: replacemissingvalue, removemissingvalue

	/// `missing value` and NaN replaced by `value`, or removed when it's nil. Arrays stay arrays; lists stay lists,
	/// their other items as they were (a list of arrays has each done).
	static func replacingMissing(_ descriptor: NSAppleEventDescriptor, with value: Double?, depth: Int = 0) throws -> NSAppleEventDescriptor {
		if let values = ArrayOfReal.values(of: descriptor) {
			let result = value.map { value in values.map { $0.isNaN ? value : $0 } } ?? values.filter { !$0.isNaN }
			return try Values.array(result)
		}
		if let matrix = try Matrix(descriptor), let value {
			return try Matrix(columns: matrix.columns, rows: matrix.rows, values: matrix.values.map { $0.isNaN ? value : $0 }).descriptor()
		}
		guard let list = RawList(descriptor) else {
			if Values.isMissingValue(descriptor) || (descriptor.descriptorType == typeIEEE64BitFloatingPoint && descriptor.doubleValue.isNaN) {
				return value.map(NSAppleEventDescriptor.init(double:)) ?? NSAppleEventDescriptor.list()
			}
			return descriptor
		}
		try Values.checkNesting(depth)
		let result = try ListBuilder()
		try list.forEachItem { item in
			if item.type == typeIEEE64BitFloatingPoint, !Double(bitPattern: item.bits).isNaN {
				try result.append(Double(bitPattern: item.bits))
			} else if Values.isMissingValue(item) || item.type == typeIEEE64BitFloatingPoint {
				if let value {
					try result.append(value)
				}
			} else if Values.severalTypes.contains(item.type) {
				try result.append(replacingMissing(list.descriptor(item.index), with: value, depth: depth + 1))
			} else {
				try result.append(list.descriptor(item.index))
			}
		}
		return result.descriptor()
	}
}
