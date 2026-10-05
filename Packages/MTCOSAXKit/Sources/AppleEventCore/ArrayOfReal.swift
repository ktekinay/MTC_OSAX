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
		// Copied in one step (the numbers are little-endian, as the Mac is); element by element through slices
		// took most of `sqrt`'s time.
		let count = (data.count - header.count) / 8
		return [Double](unsafeUninitializedCapacity: count) { buffer, initialized in
			data.withUnsafeBytes { bytes in
				UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[header.count...]))
			}
			initialized = count
		}
	}

	/// An `array of real` of `count` numbers, which `fill` writes. The numbers go straight into a buffer with room
	/// for the header (16 bytes, two numbers' worth) and the descriptor is made from it, one copy of the numbers
	/// fewer than going through `values` and Data (a hundred million numbers were 800 MB each). -108 if there isn't
	/// memory for the descriptor (it trapped).
	public static func descriptor(count: Int, _ fill: (UnsafeMutableBufferPointer<Double>) -> Void) throws -> NSAppleEventDescriptor {
		let buffer = [Double](unsafeUninitializedCapacity: count + 2) { buffer, initialized in
			header.withUnsafeBytes { UnsafeMutableRawBufferPointer(buffer).copyMemory(from: $0) }
			fill(UnsafeMutableBufferPointer(rebasing: buffer[2...]))
			initialized = count + 2
		}
		let descriptor = buffer.withUnsafeBytes {
			NSAppleEventDescriptor(descriptorType: descriptorType, bytes: $0.baseAddress, length: $0.count)
		}
		guard let descriptor else { throw OSAXError(-108, "There isn’t enough memory for an array of \(count) reals.") } // memFullErr
		return descriptor
	}

	/// This array as a descriptor; -108 without the memory.
	public func descriptor() throws -> NSAppleEventDescriptor {
		try Self.descriptor(count: values.count) { buffer in
			_ = buffer.initialize(from: values)
		}
	}

	/// This array as a descriptor, or `missing value` without the memory (commands use `descriptor()`, which says so).
	public var appleEventDescriptor: NSAppleEventDescriptor {
		(try? descriptor()) ?? .missingValue
	}
}
