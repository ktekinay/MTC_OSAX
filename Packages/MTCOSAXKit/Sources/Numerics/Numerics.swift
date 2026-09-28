import AppleEventCore
import Foundation

/// Numbers as scripts give them to Satimage's math and list commands: a number, a list of numbers (possibly nested),
/// or an `array of real`. Commands answer in the same shape.
public indirect enum Numbers: Equatable {
	case number(Double)
	case list([Numbers])
	case array([Double])

	private static let numberTypes: Set<DescType> = [
		typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint,
		typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16"),
	]

	/// Error -1700 for anything that isn't a number, a text that reads as one, a list of those or an array;
	/// -1701 for a record, as SatimageOSAX replied.
	public init(_ descriptor: NSAppleEventDescriptor) throws {
		if let values = ArrayOfReal.values(of: descriptor) {
			self = .array(values)
		} else if descriptor.descriptorType == typeAEList {
			self = .list(try (0 ..< descriptor.numberOfItems).map { try Numbers(descriptor.atIndex($0 + 1)!) })
		} else if descriptor.isRecordDescriptor {
			throw OSAXError.missingParameter
		} else {
			self = .number(try Self.number(descriptor))
		}
	}

	/// One number: integers, reals and text that reads as a number (in the script's format, `2.5`).
	public static func number(_ descriptor: NSAppleEventDescriptor) throws -> Double {
		guard numberTypes.contains(descriptor.descriptorType),
		      let real = descriptor.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)
		else {
			throw OSAXError.coercionFailed
		}
		return real.doubleValue
	}

	/// Applies `function` to every number. A single result that isn't finite is error -50; in a list it becomes
	/// `missing value`; in an array it stays (NaN, as SatimageOSAX left it).
	public func map(_ function: (Double) -> Double) throws -> NSAppleEventDescriptor {
		switch self {
		case let .number(value):
			let result = function(value)
			guard result.isFinite else {
				throw OSAXError.parameterError
			}
			return NSAppleEventDescriptor(double: result)
		case let .list(items):
			return try items.map { item -> NSAppleEventDescriptor in
				if case let .number(value) = item {
					let result = function(value)
					return result.isFinite ? NSAppleEventDescriptor(double: result) : .missingValue
				}
				return try item.map(function)
			}.appleEventDescriptor
		case let .array(values):
			return ArrayOfReal(values.map(function)).appleEventDescriptor
		}
	}
}

