import AppleEventCore
import Foundation

/// `read binary` and `write binary`: numbers as reals (8 bytes), small reals (4), integers (4), small integers (2)
/// or bytes, in the Mac's byte order (little endian) or `big endian`, as recorded from SatimageOSAX in
/// `Fixtures/Arrays/Files`. The file is a file reference or a POSIX or HFS path, as for the file commands
/// (SatimageOSAX gave error 1 for a path), and must be a regular file: -50 for a device, a pipe or a socket (writing
/// to a named pipe waited forever for something to read it).
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
		// Straight into the buffer: appending each number's bytes took more than twice as long.
		let bytes = [UInt8](unsafeUninitializedCapacity: values.count * format.size) { buffer, initialized in
			let raw = UnsafeMutableRawBufferPointer(buffer)
			for (index, value) in values.enumerated() {
				store(value, as: format, bigEndian: bigEndian, into: raw, at: index * format.size)
			}
			initialized = values.count * format.size
		}
		let what = "write “\(url.lastPathComponent)”"
		let (descriptor, size) = try openRegularFile(url, O_WRONLY | O_CREAT, what)
		defer { close(descriptor) }
		var offset = Int64(start ?? size)
		try bytes.withUnsafeBytes { buffer in
			var written = 0
			while written < buffer.count {
				let count = pwrite(descriptor, buffer.baseAddress! + written, buffer.count - written, off_t(offset))
				guard count > 0 else {
					throw posixError(what)
				}
				written += count
				offset += Int64(count)
			}
		}
		return nil
	}

	private static func posixError(_ what: String) -> OSAXError {
		OSAXError.file(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO), what)
	}

	/// The file opened without waiting (a named pipe would wait for its other end), and its size; only a regular
	/// file (-50 for a device, a pipe or a socket, as for `readtext`).
	private static func openRegularFile(_ url: URL, _ flags: Int32, _ what: String) throws -> (descriptor: Int32, size: Int) {
		let notAFile = OSAXError(-50, "“\(url.lastPathComponent)” isn’t a file that can be read or written as numbers (it’s a device, a pipe or a socket).")
		let descriptor = open(url.path, flags | O_NONBLOCK | O_CLOEXEC, 0o666)
		guard descriptor >= 0 else {
			// A named pipe with nothing reading it, opened for writing.
			throw errno == ENXIO ? notAFile : posixError(what)
		}
		var status = stat()
		guard fstat(descriptor, &status) == 0 else {
			let error = posixError(what)
			close(descriptor)
			throw error
		}
		switch status.st_mode & S_IFMT {
		case S_IFREG:
			return (descriptor, Int(status.st_size))
		case S_IFDIR:
			close(descriptor)
			throw OSAXError.file(POSIXError(.EISDIR), what)
		default:
			close(descriptor)
			throw notAFile
		}
	}

	private static func store(_ value: Double, as format: Format, bigEndian: Bool, into bytes: UnsafeMutableRawBufferPointer, at offset: Int) {
		func put<Value: FixedWidthInteger>(_ integer: Value) {
			bytes.storeBytes(of: bigEndian ? integer.bigEndian : integer.littleEndian, toByteOffset: offset, as: Value.self)
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
		let what = "read “\(url.lastPathComponent)”"
		let descriptor: Int32, size: Int
		do {
			(descriptor, size) = try openRegularFile(url, O_RDONLY, what)
		} catch let error as OSAXError where error.number == -43 {
			throw OSAXError(-43) // As recorded, without a message.
		}
		defer { close(descriptor) }
		guard size > 0 else {
			throw OSAXError(-43)
		}
		let available = max(0, (size - skip) / format.size)
		let fitting = available >= blocksize ? (available - blocksize) / step + 1 : 0
		let blocks = min(length ?? fitting, fitting)
		// Overlapping blocks (`step` less than `blocksize`) can ask for many times the file: a 20 KB file made 600 MB,
		// and a larger one overflowed.
		let (count, overflow) = blocks.multipliedReportingOverflow(by: blocksize)
		guard !overflow, count <= Arrays.maximumSize else {
			throw Arrays.tooLarge
		}
		// Only the bytes the blocks cover, read rather than mapped (a mapped file cut short while it's read can crash
		// the process).
		let byteCount = blocks == 0 ? 0 : ((blocks - 1) * step + blocksize) * format.size
		let bytes = try [UInt8](unsafeUninitializedCapacity: byteCount) { buffer, initialized in
			while initialized < byteCount {
				let count = pread(descriptor, buffer.baseAddress! + initialized, byteCount - initialized, off_t(skip + initialized))
				guard count > 0 else {
					throw count == 0 ? OSAXError.file(POSIXError(.EIO), what) : posixError(what)
				}
				initialized += count
			}
		}
		return try ArrayOfReal.descriptor(count: count) { buffer in
			bytes.withUnsafeBytes { bytes in
				var index = 0
				for block in 0 ..< blocks {
					for item in 0 ..< blocksize {
						buffer[index] = number(bytes, at: (block * step + item) * format.size, as: format, bigEndian: bigEndian, signed: signed)
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
