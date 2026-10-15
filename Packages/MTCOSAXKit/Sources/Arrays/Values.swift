import AppleEventCore
import Foundation
import Numerics

/// The numbers in what scripts give the Arrays commands: a number (or text that reads as one), a list of numbers
/// (nested lists are flattened, `missing value` is NaN), an `array of real`, a polynomial or a matrix (its numbers,
/// row by row). Lists are read from their data (`RawList`), not as a descriptor for each item.
enum Values {
	static let missingValue = FourCharCode(fourCharString: "msng")

	/// Error -50 for anything else (text that isn't a number, a record, a boolean).
	static func numbers(_ descriptor: NSAppleEventDescriptor) throws -> [Double] {
		var result: [Double] = []
		try append(descriptor, to: &result, depth: 0)
		return result
	}

	private static func append(_ descriptor: NSAppleEventDescriptor, to result: inout [Double], depth: Int) throws {
		if let values = ArrayOfReal.values(of: descriptor) ?? ArrayOfReal.values(of: descriptor, type: ArrayOfReal.polynomialType) {
			result += values
		} else if let matrix = try Matrix(descriptor) {
			result += matrix.values
		} else if let list = RawList(descriptor) {
			// A loop over the items, recursing only into lists (nested more deeply than scripts make, it stops).
			try checkNesting(depth)
			result.reserveCapacity(result.count + list.count)
			try list.forEachItem { item in
				if let value = number(item) {
					result.append(value)
				} else {
					try append(list.descriptor(item.index), to: &result, depth: depth + 1)
				}
			}
		} else {
			result.append(try number(descriptor))
		}
	}

	/// -50 for lists nested more than `NSAppleEventDescriptor.maximumNesting` levels (they ran out of stack).
	static func checkNesting(_ depth: Int) throws {
		guard depth < NSAppleEventDescriptor.maximumNesting else {
			throw NSAppleEventDescriptor.nestedTooDeep
		}
	}

	/// A list item's number, if it's a number (`missing value` is NaN); nil for anything else.
	static func number(_ item: RawList.Item) -> Double? {
		switch item.type {
		case typeSInt16: Double(Int16(truncatingIfNeeded: item.bits))
		case typeSInt32: Double(Int32(truncatingIfNeeded: item.bits))
		case typeSInt64: Double(Int64(bitPattern: item.bits))
		case typeIEEE32BitFloatingPoint: Double(Float32(bitPattern: UInt32(truncatingIfNeeded: item.bits)))
		case typeIEEE64BitFloatingPoint: Double(bitPattern: item.bits)
		case typeType where isMissingValue(item): .nan
		default: nil
		}
	}

	/// Whether a list item is `missing value`.
	static func isMissingValue(_ item: RawList.Item) -> Bool {
		item.type == typeType && UInt32(truncatingIfNeeded: item.bits) == missingValue
	}

	/// Whether a descriptor is `missing value`.
	static func isMissingValue(_ descriptor: NSAppleEventDescriptor) -> Bool {
		descriptor.descriptorType == typeType && descriptor.typeCodeValue == missingValue
	}

	/// One number: `missing value` is NaN; error -50 for anything that isn't a number or text that reads as one.
	static func number(_ descriptor: NSAppleEventDescriptor) throws -> Double {
		if isMissingValue(descriptor) {
			return .nan
		}
		do {
			return try Numbers.number(descriptor)
		} catch {
			throw OSAXError.parameterError
		}
	}

	/// A whole number from a parameter: half rounds to even, as `createarray`'s size does (2.5 is 2).
	static func integer(_ descriptor: NSAppleEventDescriptor) throws -> Int {
		let value = try number(descriptor).rounded(.toNearestOrEven)
		guard value.isFinite, value.magnitude <= Double(Int32.max) else {
			throw OSAXError.parameterError
		}
		return Int(value)
	}

	/// The types that hold several numbers: a list, an array, a polynomial or a matrix.
	static let severalTypes: Set<DescType> = [typeAEList, ArrayOfReal.descriptorType, ArrayOfReal.polynomialType, Matrix.descriptorType]

	/// Whether a descriptor holds several numbers (a list, an array, a polynomial or a matrix) rather than one.
	static func isSeveral(_ descriptor: NSAppleEventDescriptor) -> Bool {
		severalTypes.contains(descriptor.descriptorType)
	}

	/// An `array of real` of these numbers.
	static func array(_ values: [Double]) throws -> NSAppleEventDescriptor {
		try ArrayOfReal.descriptor(count: values.count) { _ = $0.initialize(from: values) }
	}

	/// A list of reals, `missing value` for NaN.
	static func listOfReals(_ values: [Double]) throws -> NSAppleEventDescriptor {
		let list = try ListBuilder()
		for value in values {
			try value.isNaN ? list.appendMissingValue() : list.append(value)
		}
		return list.descriptor()
	}
}

/// A list made item by item with the Apple Event Manager, without a descriptor for each number: a list of 1,000,000
/// reals took 280 ms with a descriptor for each, and takes about 95 this way.
final class ListBuilder {
	private var list = AEDescList()
	private var isMade = false

	init() throws {
		try Self.check(AECreateList(nil, 0, false, &list))
	}

	deinit {
		if !isMade {
			AEDisposeDesc(&list)
		}
	}

	func append(_ value: Double) throws {
		var value = value
		try Self.check(AEPutPtr(&list, 0, typeIEEE64BitFloatingPoint, &value, 8))
	}

	func append(_ value: Int32) throws {
		var value = value
		try Self.check(AEPutPtr(&list, 0, typeSInt32, &value, 4))
	}

	func appendMissingValue() throws {
		var code = Values.missingValue
		try Self.check(AEPutPtr(&list, 0, typeType, &code, 4))
	}

	func append(_ item: NSAppleEventDescriptor) throws {
		try withExtendedLifetime(item) {
			try Self.check(AEPutDesc(&list, 0, item.aeDesc!))
		}
	}

	/// The list; the builder can't be used after.
	func descriptor() -> NSAppleEventDescriptor {
		isMade = true
		return NSAppleEventDescriptor(aeDescNoCopy: &list)
	}

	private static func check(_ status: OSErr) throws {
		if status != noErr {
			throw OSAXError(Int(status))
		}
	}
}

/// Satimage's `matrix`: `{class:matrix, ncols, nrows, array of real}`, a record of type `Matr` whose numbers (an
/// `array of real` or a list) are the rows one after another.
struct Matrix: Equatable {
	static let descriptorType = FourCharCode(fourCharString: "Matr")

	var columns: Int
	var rows: Int
	var values: [Double]

	init(columns: Int, rows: Int, values: [Double]) {
		self.columns = columns
		self.rows = rows
		self.values = values
	}

	/// Nil unless the descriptor is a matrix record; error -50 if its numbers aren't `ncols` × `nrows` of them.
	init?(_ descriptor: NSAppleEventDescriptor) throws {
		guard descriptor.descriptorType == Self.descriptorType, let fields = RecordFields(descriptor),
		      let columns = fields[.code("ncol")], let rows = fields[.code("nrow")], let data = fields[.code("Lido")]
		else {
			return nil
		}
		self.columns = try Values.integer(columns)
		self.rows = try Values.integer(rows)
		values = try Values.numbers(data)
		guard self.columns >= 0, self.rows >= 0, values.count == self.columns * self.rows else {
			throw OSAXError.parameterError
		}
	}

	func row(_ row: Int) -> ArraySlice<Double> {
		values[row * columns ..< (row + 1) * columns]
	}

	/// `{class:matrix, ncols, nrows, array of real}`, its numbers as an `array of real`.
	func descriptor() throws -> NSAppleEventDescriptor {
		let record = RecordFields([
			(.code("ncol"), NSAppleEventDescriptor(int32: Int32(columns))),
			(.code("nrow"), NSAppleEventDescriptor(int32: Int32(rows))),
			(.code("Lido"), try Values.array(values)),
		]).appleEventDescriptor
		return record.coerce(toDescriptorType: Self.descriptorType) ?? record
	}
}
