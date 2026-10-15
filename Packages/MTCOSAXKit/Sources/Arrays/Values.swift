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
			guard depth < NSAppleEventDescriptor.maximumNesting else {
				throw NSAppleEventDescriptor.nestedTooDeep
			}
			result.reserveCapacity(result.count + list.count)
			for index in 0 ..< list.count {
				let (type, _) = list.info(index)
				switch type {
				case typeSInt16: result.append(Double(list.value(index, type: type, as: Int16.self)))
				case typeSInt32: result.append(Double(list.value(index, type: type, as: Int32.self)))
				case typeSInt64: result.append(Double(list.value(index, type: type, as: Int64.self)))
				case typeIEEE32BitFloatingPoint: result.append(Double(list.value(index, type: type, as: Float32.self)))
				case typeIEEE64BitFloatingPoint: result.append(list.value(index, type: type, as: Double.self))
				default: try append(list.descriptor(index), to: &result, depth: depth + 1)
				}
			}
		} else {
			result.append(try number(descriptor))
		}
	}

	/// One number: `missing value` is NaN; error -50 for anything that isn't a number or text that reads as one.
	static func number(_ descriptor: NSAppleEventDescriptor) throws -> Double {
		if descriptor.descriptorType == typeType, descriptor.typeCodeValue == missingValue {
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

	/// Whether a descriptor holds several numbers (a list, an array, a polynomial or a matrix) rather than one.
	static func isSeveral(_ descriptor: NSAppleEventDescriptor) -> Bool {
		[typeAEList, ArrayOfReal.descriptorType, ArrayOfReal.polynomialType, Matrix.descriptorType].contains(descriptor.descriptorType)
	}

	/// An `array of real` of these numbers.
	static func array(_ values: [Double]) throws -> NSAppleEventDescriptor {
		try ArrayOfReal.descriptor(count: values.count) { _ = $0.initialize(from: values) }
	}

	/// A list of reals, `missing value` for NaN.
	static func listOfReals(_ values: [Double]) -> NSAppleEventDescriptor {
		values.map { $0.isNaN ? NSAppleEventDescriptor.missingValue : NSAppleEventDescriptor(double: $0) }.appleEventDescriptor
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
