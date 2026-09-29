import Foundation

/// Satimage's `array of real` (`Lido`): packed reals, as opaque data that scripts pass from command to command.
/// The data is the text "Not a record", the tag `buod`, then the numbers as little-endian doubles.
public struct ArrayOfReal: Equatable, AppleEventConvertible {
	public static let descriptorType = FourCharCode(fourCharString: "Lido")
	static let header = Data("Not a recordbuod".utf8)

	public var values: [Double]

	public init(_ values: [Double]) {
		self.values = values
	}

	/// Error -1700 unless the descriptor is an `array of real`.
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		guard let values = Self.values(of: descriptor) else {
			throw OSAXError.coercionFailed
		}
		self.values = values
	}

	/// The numbers in an `array of real` descriptor, or nil if it isn't one. The type is checked first: asking a
	/// list for its data made the Apple Event Manager copy and byte-swap the whole list (and log).
	public static func values(of descriptor: NSAppleEventDescriptor) -> [Double]? {
		guard descriptor.descriptorType == descriptorType else {
			return nil
		}
		let data = descriptor.data
		guard data.starts(with: header), (data.count - header.count) % 8 == 0 else {
			return nil
		}
		return stride(from: header.count, to: data.count, by: 8).map { offset in
			Double(bitPattern: UInt64(littleEndian: data[offset ..< offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }))
		}
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		var data = Self.header
		for value in values {
			withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
		}
		return NSAppleEventDescriptor(descriptorType: Self.descriptorType, data: data)!
	}
}
