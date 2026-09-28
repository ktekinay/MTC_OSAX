import AppleEventCore
import Foundation

/// Reading and writing text files the way Satimage does (recorded in `Fixtures/TextAdditions/Files`).
enum FileText {
	/// Text read from a file, with how to write it back.
	struct Contents {
		var text: String
		var encoding: String.Encoding
		/// The byte-order mark the file started with, written back by `change`.
		var byteOrderMark: Data
	}

	/// An IANA character set name ("UTF-8", "MACINTOSH", "ISO-8859-1", "windows-1252", …; any case).
	/// Unknown: error -1.
	static func encoding(named name: String) throws -> String.Encoding {
		let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
		guard cfEncoding != kCFStringEncodingInvalidId else {
			throw invalidOptionError
		}
		return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
	}

	// MARK: Reading

	/// Reads `url`. With no `encoding`: the byte-order mark if there is one, else UTF-8 if valid, else MacRoman.
	/// `start` and `length` are in bytes (a `length` of 0 or none reads to the end; Satimage failed with -1 for a
	/// `start` without a `length`). A `start` past the end is error -39.
	static func read(_ url: URL, start: Int? = nil, length: Int? = nil, encoding: String.Encoding? = nil) throws -> Contents {
		let start = start ?? 0
		let length = (length ?? 0) > 0 ? length : nil
		let partial = start > 0 || length != nil
		let data = try readData(url, from: max(start, 0), length: length)
		if let encoding {
			guard let text = String(data: data, encoding: encoding) else {
				throw OSAXError(-1409)
			}
			return Contents(text: text, encoding: encoding, byteOrderMark: Data())
		}
		return decode(data, trimIncompleteEnd: partial)
	}

	/// The bytes from `start`, `length` of them or to the end; only those are read. Only regular files: a device
	/// such as /dev/zero would be read until memory ran out, and a named pipe would wait forever (-50).
	private static func readData(_ url: URL, from start: Int, length: Int?) throws -> Data {
		var status = stat()
		guard stat(url.path, &status) == 0 else {
			throw OSAXError(-43) // fnfErr
		}
		switch status.st_mode & S_IFMT {
		case S_IFDIR:
			throw OSAXError(1)
		case S_IFREG:
			break
		default:
			throw OSAXError(-50, "“\(url.lastPathComponent)” isn’t a file that can be read as text (it’s a device, a pipe or a socket).")
		}
		let size = Int(status.st_size)
		guard start <= size else {
			throw OSAXError(-39) // eofErr
		}
		do {
			let handle = try FileHandle(forReadingFrom: url)
			defer { try? handle.close() }
			try handle.seek(toOffset: UInt64(start))
			return try handle.read(upToCount: min(length ?? size, size - start)) ?? Data()
		} catch {
			throw OSAXError(-54) // permErr
		}
	}

	private static let byteOrderMarks: [(bytes: [UInt8], encoding: String.Encoding)] = [
		([0xEF, 0xBB, 0xBF], .utf8),
		([0xFF, 0xFE], .utf16LittleEndian),
		([0xFE, 0xFF], .utf16BigEndian),
	]

	/// Satimage's detection: byte-order mark, then UTF-8, then MacRoman. A partial read drops an incomplete
	/// character at the end.
	static func decode(_ data: Data, trimIncompleteEnd: Bool) -> Contents {
		let bytes = [UInt8](data)
		for mark in byteOrderMarks where bytes.starts(with: mark.bytes) {
			var body = Data(bytes.dropFirst(mark.bytes.count))
			if mark.encoding != .utf8, body.count % 2 == 1 {
				body.removeLast()
			}
			if mark.encoding == .utf8, trimIncompleteEnd {
				body = trimmingIncompleteUTF8(body)
			}
			if let text = String(data: body, encoding: mark.encoding) {
				return Contents(text: text, encoding: mark.encoding, byteOrderMark: Data(mark.bytes))
			}
		}
		let utf8 = trimIncompleteEnd ? trimmingIncompleteUTF8(data) : data
		if let text = String(data: utf8, encoding: .utf8) {
			return Contents(text: text, encoding: .utf8, byteOrderMark: Data())
		}
		return Contents(text: String(data: data, encoding: .macOSRoman) ?? "", encoding: .macOSRoman, byteOrderMark: Data())
	}

	/// Drops a UTF-8 sequence cut off at the end of `data`.
	static func trimmingIncompleteUTF8(_ data: Data) -> Data {
		let bytes = [UInt8](data)
		guard !bytes.isEmpty else {
			return data
		}
		// Look back at most 3 bytes for the start of the last sequence.
		for back in 1 ... min(3, bytes.count) {
			let byte = bytes[bytes.count - back]
			if byte & 0xC0 == 0x80 {
				continue // continuation byte
			}
			let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
			return needed > back ? Data(bytes.dropLast(back)) : data
		}
		return data
	}

	// MARK: Searching bytes

	/// The 0-based byte offset of `text` in the file at or after byte `start`, with `text` encoded in `encoding`
	/// (generic UTF-16 follows the file's byte-order mark). `inclusive` gives the offset just after it.
	/// Not found (or empty `text`): error -2763, like `find text`.
	static func offset(of text: String, in url: URL, from start: Int, encoding: String.Encoding, inclusive: Bool) throws -> Int {
		let data = try readData(url, from: 0, length: nil)
		guard start <= data.count else {
			throw OSAXError(-39)
		}
		guard let needle = bytes(of: text, encoding: encoding, fileStart: data.prefix(4)), !needle.isEmpty,
		      let found = data.range(of: needle, in: max(start, 0) ..< data.count)
		else {
			throw notFoundError
		}
		return inclusive ? found.upperBound : found.lowerBound
	}

	/// `text` encoded for searching, without a byte-order mark. Generic UTF-16 and UTF-32 take the file's byte order
	/// from its byte-order mark (little-endian without one); UTF-32 used to be little-endian regardless.
	static func bytes(of text: String, encoding: String.Encoding, fileStart: Data) -> Data? {
		var encoding = encoding
		if encoding == .utf16 {
			encoding = fileStart.starts(with: [0xFE, 0xFF]) ? .utf16BigEndian : .utf16LittleEndian
		} else if encoding == .utf32 {
			encoding = fileStart.starts(with: [0x00, 0x00, 0xFE, 0xFF]) ? .utf32BigEndian : .utf32LittleEndian
		}
		return text.data(using: encoding)
	}

	// MARK: Writing

	/// The bytes for `text` in `encoding`. Characters the encoding can't hold are replaced by `missingCharacter`
	/// once per UTF-16 unit (so an emoji becomes two); without one, they're error -1.
	static func encode(_ text: String, encoding: String.Encoding, missingCharacter: String?) throws -> Data {
		if let data = text.data(using: encoding) {
			return data
		}
		guard let missingCharacter else {
			throw invalidOptionError
		}
		var replaced = ""
		for scalar in text.unicodeScalars {
			if String(scalar).data(using: encoding) != nil {
				replaced.unicodeScalars.append(scalar)
			} else {
				replaced += String(repeating: missingCharacter, count: String(scalar).utf16.count)
			}
		}
		guard let data = replaced.data(using: encoding) else {
			throw invalidOptionError
		}
		return data
	}

	static func write(_ data: Data, to url: URL, append: Bool) throws {
		let directory = url.deletingLastPathComponent().path
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
			throw OSAXError(-43)
		}
		// A folder can't be written as text: EISDIR, as in SatimageOSAX (it was -54).
		guard !(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue) else {
			throw OSAXError(Int(EISDIR))
		}
		do {
			if append, let handle = try? FileHandle(forWritingTo: url) {
				defer { try? handle.close() }
				try handle.seekToEnd()
				try handle.write(contentsOf: data)
			} else {
				try data.writeReplacing(url)
			}
		} catch {
			throw OSAXError(-54)
		}
	}
}
