import AppleEventCore
import Foundation

/// `read binary` and `write binary`: numbers as reals (8 bytes), small reals (4), integers (4), small integers (2)
/// or bytes, in the Mac's byte order (little endian) or `big endian`, as recorded from SatimageOSAX in
/// `Fixtures/Arrays/Files`. The file is a file reference or a POSIX or HFS path, as for the file commands
/// (SatimageOSAX gave error 1 for a path).
enum BinaryFiles {
	/// A number format in a file.
	enum Format: String {
		case real = "doub", smallReal = "sing", integer = "long", smallInteger = "shor", byte

		var size: Int {
			switch self {
			case .real: 8
			case .smallReal, .integer: 4
			case .smallInteger: 2
			case .byte: 1
			}
		}

		/// `as`: real by default; another type is -50 (SatimageOSAX accepted `as text` and didn't say what it did).
		init(_ request: AppleEventRequest, default defaultFormat: Format?) throws {
			guard let descriptor = request.descriptor(for: "rtyp") else {
				guard let defaultFormat else {
					// As recorded: read binary without `as` is -10001.
					throw OSAXError(-10001)
				}
				self = defaultFormat
				return
			}
			guard let format = Format(rawValue: descriptor.typeCodeValue.fourCharString) else {
				throw OSAXError.parameterError
			}
			self = format
		}
	}

	@MainActor
	static func commands() -> [CommandDefinition] {
		[
			CommandDefinition("read binary", code: "SATIRdBF", handler: read),
			CommandDefinition("write binary", code: "SATIWrBF", handler: write),
		]
	}

	// MARK: write binary

	/// Appends the numbers to the file (making it), or writes them from byte `starting at` (0 is the first; past
	/// the end, the gap is zeros). Integers round half away from zero, but bytes are cut toward zero (-2.5 is -3 as
	/// an integer and -2 as a byte), and keep their low bytes, as recorded (300 as a byte is 44); NaN is 0. No
	/// numbers writes nothing.
	static func write(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let url = try request.requiredDirectParameter(as: URL.self)
		guard let dataDescriptor = request.descriptor(for: "data") else {
			throw OSAXError.missingParameter
		}
		let values = try Values.numbers(dataDescriptor)
		let format = try Format(request, default: .real)
		let bigEndian = try request.parameter("Endi", default: false)
		let start = try request.descriptor(for: "strt").map(Values.integer)
		if let start, start < 0 {
			throw OSAXError.parameterError
		}
		guard !values.isEmpty else {
			return nil
		}
		var bytes = [UInt8]()
		bytes.reserveCapacity(values.count * format.size)
		for value in values {
			append(value, as: format, bigEndian: bigEndian, to: &bytes)
		}
		let descriptor = open(url.path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o666)
		guard descriptor >= 0 else {
			throw OSAXError.file(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO), "write “\(url.lastPathComponent)”")
		}
		defer { close(descriptor) }
		var offset = try start.map(Int64.init) ?? {
			let end = lseek(descriptor, 0, SEEK_END)
			guard end >= 0 else { throw OSAXError.file(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO), "write “\(url.lastPathComponent)”") }
			return Int64(end)
		}()
		try bytes.withUnsafeBytes { buffer in
			var written = 0
			while written < buffer.count {
				let count = pwrite(descriptor, buffer.baseAddress! + written, buffer.count - written, off_t(offset))
				guard count > 0 else {
					throw OSAXError.file(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO), "write “\(url.lastPathComponent)”")
				}
				written += count
				offset += Int64(count)
			}
		}
		return nil
	}

	private static func append(_ value: Double, as format: Format, bigEndian: Bool, to bytes: inout [UInt8]) {
		func put<Value: FixedWidthInteger>(_ integer: Value) {
			let ordered = bigEndian ? integer.bigEndian : integer.littleEndian
			withUnsafeBytes(of: ordered) { bytes.append(contentsOf: $0) }
		}
		// Rounded half away from zero (cut toward zero for a byte); NaN, and numbers beyond 64 bits, are 0.
		let rule: FloatingPointRoundingRule = format == .byte ? .towardZero : .toNearestOrAwayFromZero
		let whole = value.isFinite && abs(value) < 9.2e18 ? Int64(value.rounded(rule)) : 0
		switch format {
		case .real: put(value.bitPattern)
		case .smallReal: put(Float(value).bitPattern)
		case .integer: put(Int32(truncatingIfNeeded: whole))
		case .smallInteger: put(Int16(truncatingIfNeeded: whole))
		case .byte: put(Int8(truncatingIfNeeded: whole))
		}
	}

	// MARK: read binary

	/// The file's numbers as an `array of real` of 8-byte reals (SatimageOSAX made 4-byte ones for all but `real`,
	/// so integers above 16,777,216 lost their last digits): after `skip` bytes, `length` blocks (default all that fit) of
	/// `blocksize` numbers (default 1), each `step` numbers after the one before (default `blocksize`); integers
	/// `signed` (default) or not; an incomplete number at the end is left out. A missing or empty file is -43.
	static func read(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let url = try request.requiredDirectParameter(as: URL.self)
		let format = try Format(request, default: nil)
		let bigEndian = try request.parameter("Endi", default: false)
		let signed = try request.parameter("Sign", default: true)
		let skip = try request.descriptor(for: "skip").map(Values.integer) ?? 0
		let blocksize = try request.descriptor(for: "bloc").map(Values.integer) ?? 1
		let step = try request.descriptor(for: "jump").map(Values.integer) ?? blocksize
		let length = try request.descriptor(for: "for ").map(Values.integer)
		guard skip >= 0, blocksize >= 1, step >= 1, (length ?? 0) >= 0 else {
			throw OSAXError.parameterError
		}
		let data: Data
		do {
			data = try Data(contentsOf: url, options: .mappedIfSafe)
		} catch let error as CocoaError where error.code == .fileReadNoSuchFile {
			throw OSAXError(-43)
		} catch {
			throw OSAXError.file(error, "read “\(url.lastPathComponent)”")
		}
		guard !data.isEmpty else {
			throw OSAXError(-43)
		}
		let available = max(0, (data.count - skip) / format.size)
		let fitting = available >= blocksize ? (available - blocksize) / step + 1 : 0
		let blocks = min(length ?? fitting, fitting)
		return try ArrayOfReal.descriptor(count: blocks * blocksize) { buffer in
			data.withUnsafeBytes { bytes in
				var index = 0
				for block in 0 ..< blocks {
					for item in 0 ..< blocksize {
						let offset = skip + (block * step + item) * format.size
						buffer[index] = number(bytes, at: offset, as: format, bigEndian: bigEndian, signed: signed)
						index += 1
					}
				}
			}
		}
	}

	private static func number(_ bytes: UnsafeRawBufferPointer, at offset: Int, as format: Format, bigEndian: Bool, signed: Bool) -> Double {
		func get<Value: FixedWidthInteger>(_: Value.Type) -> Value {
			let raw = bytes.loadUnaligned(fromByteOffset: offset, as: Value.self)
			return bigEndian ? Value(bigEndian: raw) : Value(littleEndian: raw)
		}
		switch format {
		case .real: return Double(bitPattern: get(UInt64.self))
		case .smallReal: return Double(Float(bitPattern: get(UInt32.self)))
		case .integer: return signed ? Double(Int32(bitPattern: get(UInt32.self))) : Double(get(UInt32.self))
		case .smallInteger: return signed ? Double(Int16(bitPattern: get(UInt16.self))) : Double(get(UInt16.self))
		case .byte: return signed ? Double(Int8(bitPattern: get(UInt8.self))) : Double(get(UInt8.self))
		}
	}
}
