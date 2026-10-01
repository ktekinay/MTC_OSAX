import AppleEventCore
import CoreServices
import Foundation

/// Conversions between AppleScript values (Apple event descriptors), property list elements, and Foundation
/// objects (for files, XML, JSON and comparing), as SatimageOSAX made them.
///
/// - Lists become arrays and records dictionaries; a record's keyword properties (`name`) get keys like
///   `«class pnam»`, and come back as keywords.
/// - Text, integers, reals, booleans and dates become their property list types. Anything else (aliases, file
///   references, `missing value`, data, classes) is stored as data: the flattened descriptor (`dle2`), which
///   `PlistGet` turns back into the value.
/// - A CFRef stands for a copy of the element it refers to.
extension PropertyLists {
	/// How deeply lists and records (or arrays and dictionaries) may nest: the recursion that converts them would
	/// otherwise run out of stack and crash the app (a JSON file of a million `[`s did).
	nonisolated static let maximumDepth = 512
	nonisolated static let tooDeep = OSAXError(-50, "The value is nested more than \(maximumDepth) levels deep.")

	/// How many values, and bytes of text and data, a parsed file may repeat: it becomes a tree, with a copy of each
	/// value wherever it's used.
	nonisolated static let maximumRepeatedValues = 1_000_000
	nonisolated static let maximumRepeatedBytes = 100_000_000
	nonisolated static let tooRepetitive = OSAXError(-50, "The property list uses the same values over and over: as a tree it would be too large.")

	/// -50 unless `child` can go under `parent` without the tree being more than `maximumDepth` levels deep. A script
	/// could build one deeper (a CFRef of a deep part put under another deep part, say) until writing it out, or
	/// reading it, ran out of stack.
	static func checkDepth(of child: Node, under parent: Node) throws {
		guard parent.depth + 1 + child.height <= maximumDepth else { throw tooDeep }
	}

	/// -50 for Foundation objects (a parsed file) nested more than `maximumDepth` levels deep, or that would repeat
	/// more than `maximumRepeatedValues` values or `maximumRepeatedBytes` bytes when made a tree.
	///
	/// A binary property list refers to its values by number, so it can use one array in two places, the one
	/// holding it in two places, and so on: a file of 200 bytes stood for 2⁴⁰ values, which reading took days
	/// over and then ran out of memory. (YAML's aliases, as read, are the same.) Each container is measured once.
	static func checkLimits(_ object: Any) throws {
		var measure = Measure()
		let size = try measure.size(of: object as AnyObject, depth: 0)
		guard size.values - measure.values <= maximumRepeatedValues, size.bytes - measure.bytes <= maximumRepeatedBytes else {
			throw tooRepetitive
		}
	}

	/// Sizes of values as trees, each container measured once. `values` and `bytes` count what was measured (each
	/// container, and what's directly in it, once); the difference from a tree's size is what it repeats.
	private struct Measure {
		struct Size {
			/// Values, and bytes of text and data, in the tree; how many levels deep it goes.
			var values = 1
			var bytes = 0
			var height = 0
		}

		var values = 0
		var bytes = 0
		private var measured: [ObjectIdentifier: Size] = [:]
		private var leaves: Set<ObjectIdentifier> = []

		mutating func size(of object: AnyObject, depth: Int) throws -> Size {
			guard depth <= maximumDepth else { throw tooDeep }
			let children: [Any]
			switch object {
			case let dictionary as NSDictionary: children = dictionary.allValues
			case let array as NSArray: children = array as [AnyObject]
			default:
				values += 1
				var size = Size()
				switch object {
				case let text as NSString: size.bytes = text.length
				case let data as NSData: size.bytes = data.length
				default: break
				}
				// Text used again (binary files store equal strings once) counts only once.
				if leaves.insert(ObjectIdentifier(object)).inserted {
					bytes += size.bytes
				}
				return size
			}
			let identity = ObjectIdentifier(object)
			if let size = measured[identity] {
				guard depth + size.height <= maximumDepth else { throw tooDeep }
				return size
			}
			values += 1
			var size = Size()
			for child in children {
				let childSize = try self.size(of: child as AnyObject, depth: depth + 1)
				// Saturating: the counts double with each level of repetition.
				size.values = min(size.values + childSize.values, Int.max / 4)
				size.bytes = min(size.bytes + childSize.bytes, Int.max / 4)
				size.height = max(size.height, childSize.height + 1)
			}
			measured[identity] = size
			return size
		}
	}

	/// An element made from an AppleScript value. `typed` false stores a single value (not a list or record) as its
	/// raw bytes, as `PlistSet … without typed` does.
	static func node(from descriptor: NSAppleEventDescriptor, in document: Document, store: DocumentStore, typed: Bool = true,
	                 depth: Int = 0) throws -> Node
	{
		guard depth <= maximumDepth else { throw tooDeep }
		if DocumentStore.isReference(descriptor) {
			return try store.node(descriptor).copy(in: document)
		}
		if descriptor.descriptorType == typeAEList {
			let items = try (0 ..< descriptor.numberOfItems).map {
				try node(from: descriptor.atIndex($0 + 1)!, in: document, store: store, typed: typed, depth: depth + 1)
			}
			return Node(.array(items), in: document)
		}
		if let record = RecordFields(descriptor) {
			let dictionary = NSMutableDictionary()
			for (key, value) in record.fields {
				dictionary[key.plistKey] = try node(from: value, in: document, store: store, typed: typed, depth: depth + 1)
			}
			return Node(.dictionary(dictionary), in: document)
		}
		if !typed {
			// `true` and `false` have no bytes of their own; their one-byte boolean form stands in.
			let raw = [typeTrue, typeFalse].contains(descriptor.descriptorType) ? descriptor.coerce(toDescriptorType: typeBoolean) ?? descriptor : descriptor
			return Node(.data(raw.data), in: document)
		}
		return Node(content(of: descriptor), in: document)
	}

	static func content(of descriptor: NSAppleEventDescriptor) -> Node.Content {
		switch descriptor.descriptorType {
		case typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16"):
			return .string(descriptor.stringValue ?? "")
		case typeSInt16, typeSInt32:
			return .integer(Int64(descriptor.int32Value))
		case typeSInt64 where descriptor.data.count == 8:
			// int32Value is 0 for a 64-bit integer (AppleScript sends reals, but other senders can send these).
			return .integer(descriptor.data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) })
		case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
			return .real(descriptor.doubleValue)
		case typeTrue, typeFalse, typeBoolean:
			return .boolean(descriptor.booleanValue)
		case typeLongDateTime:
			if let date = descriptor.dateValue {
				return .date(date)
			}
		default:
			break
		}
		return .data(flatten(descriptor))
	}

	/// The AppleScript value of an element. Integers beyond 32 bits become reals (SatimageOSAX returned 0). Data that
	/// isn't a flattened descriptor comes back as text of its bytes, or as `type` when given (`PlistGet … as`).
	static func descriptor(of node: Node, as type: FourCharCode? = nil) -> NSAppleEventDescriptor {
		switch node.content {
		case let .dictionary(dictionary):
			var record = RecordFields()
			for key in dictionary.allKeys {
				guard let key = key as? String, let child = dictionary[key] as? Node else { continue }
				record.fields.append((RecordFields.Key(plistKey: key), descriptor(of: child)))
			}
			return record.appleEventDescriptor
		case let .array(items):
			return items.map { descriptor(of: $0) }.appleEventDescriptor
		case let .data(data):
			if let type {
				return NSAppleEventDescriptor(descriptorType: type, data: data) ?? NSAppleEventDescriptor(descriptorType: type, data: nil)!
			}
			return unflatten(data) ?? NSAppleEventDescriptor(descriptorType: typeChar, data: data)!
		default:
			let value = scalarDescriptor(node.content)
			if let type, let coerced = value.coerce(toDescriptorType: type) {
				return coerced
			}
			return value
		}
	}

	private static func scalarDescriptor(_ content: Node.Content) -> NSAppleEventDescriptor {
		switch content {
		case let .string(text): NSAppleEventDescriptor(string: text)
		case let .integer(value): Int32(exactly: value).map(NSAppleEventDescriptor.init(int32:)) ?? NSAppleEventDescriptor(double: Double(value))
		case let .real(value): NSAppleEventDescriptor(double: value)
		case let .boolean(value): NSAppleEventDescriptor(boolean: value)
		case let .date(date): NSAppleEventDescriptor(date: date)
		default: .null()
		}
	}

	// MARK: Flattened descriptors

	nonisolated static func flatten(_ descriptor: NSAppleEventDescriptor) -> Data {
		guard var desc = descriptor.aeDesc?.pointee else {
			return Data()
		}
		let size = AESizeOfFlattenedDesc(&desc)
		var buffer = [UInt8](repeating: 0, count: size)
		var written = 0
		guard AEFlattenDesc(&desc, &buffer, size, &written) == noErr else {
			return Data()
		}
		return Data(buffer.prefix(written))
	}

	/// The descriptor flattened in `data`, or nil if it isn't one. The length inside the data isn't trusted (data
	/// from a file can claim more than it holds; `AEUnflattenDesc` would read past the end), and neither is its
	/// nesting: lists or records nested more than `maximumDepth` deep are left as data, since unflattening them
	/// takes time that grows with the square of the depth (a minute at 12,000 levels, 192 KB) and then overflows the
	/// stack (16,000 levels, 256 KB), where a value from a document could stop or end the app.
	nonisolated static func unflatten(_ data: Data) -> NSAppleEventDescriptor? {
		guard data.starts(with: Array("dle2".utf8)), let depth = FlattenedDescriptor.depth(of: data), depth <= maximumDepth else {
			return nil
		}
		var desc = AEDesc()
		let status = data.withUnsafeBytes { AEUnflattenDescFromBytes($0.baseAddress!, $0.count, &desc) }
		guard status == noErr else {
			return nil
		}
		return NSAppleEventDescriptor(aeDescNoCopy: &desc)
	}

	// MARK: Foundation objects

	/// The element as Foundation objects, for `PropertyListSerialization`, JSON and comparing. Dictionaries keep
	/// their key order.
	static func object(of node: Node) -> Any {
		switch node.content {
		case let .dictionary(dictionary):
			return dictionary.mappingValues { object(of: $0 as! Node) }
		case let .array(items): return items.map { object(of: $0) } as NSArray
		case let .string(text): return text as NSString
		case let .integer(value): return NSNumber(value: value)
		case let .real(value): return NSNumber(value: value)
		case let .boolean(value): return value ? kCFBooleanTrue! : kCFBooleanFalse!
		case let .date(date): return date as NSDate
		case let .data(data): return data as NSData
		}
	}

	/// An element from Foundation objects (a parsed file, checked with `checkLimits`). Dictionaries keep their key order.
	/// Objective-C classes are checked: Swift casts such as `as String` and `as Date` are slow for Objective-C objects,
	/// and were most of `PlistFromJSON`'s time.
	static func node(from object: Any, in document: Document) -> Node {
		switch object as AnyObject {
		case let dictionary as NSDictionary:
			return Node(.dictionary(dictionary.mappingValues { node(from: $0, in: document) }), in: document)
		case let array as NSArray:
			return Node(.array(array.map { node(from: $0, in: document) }), in: document)
		case let text as NSString:
			return Node(.string(text as String), in: document)
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return Node(.boolean(number.boolValue), in: document)
			}
			// An unsigned integer past Int64.max (a property list file can hold one up to 2⁶⁴ - 1) is a real, as an
			// integer too large for AppleScript is: as an Int64 its bits read negative (18446744073709551615 was -1).
			if CFNumberIsFloatType(number) || number.compare(NSNumber(value: Int64.max)) == .orderedDescending {
				return Node(.real(number.doubleValue), in: document)
			}
			return Node(.integer(number.int64Value), in: document)
		case let date as NSDate:
			return Node(.date(date as Date), in: document)
		case let data as NSData:
			return Node(.data(data as Data), in: document)
		case is NSNull:
			// JSON's null, stored as `missing value` (SatimageOSAX made a property list it couldn't use).
			return Node(.data(flatten(.missingValue)), in: document)
		default:
			return Node(.data(Data()), in: document)
		}
	}

	/// The element as a property list file's XML (Apple's format, with keys sorted), or in binary.
	static func serialized(_ node: Node, binary: Bool = false) throws -> Data {
		do {
			return try PropertyListSerialization.data(fromPropertyList: object(of: node), format: binary ? .binary : .xml, options: 0)
		} catch {
			throw OSAXError(-1)
		}
	}
}

extension NSDictionary {
	/// A mutable copy with each value transformed. Copying (rather than inserting the keys again) keeps the keys in
	/// the same order, which is the order of Core Foundation's hashing that SatimageOSAX's results show.
	func mappingValues(_ transform: (Any) -> Any) -> NSMutableDictionary {
		let copy = mutableCopy() as! NSMutableDictionary
		for key in allKeys {
			copy[key] = transform(self[key]!)
		}
		return copy
	}
}

extension RecordFields.Key {
	/// A record key as a property list key: user properties as they are, keywords as `«class pnam»`.
	var plistKey: String {
		switch self {
		case let .user(name): name
		case let .code(code): "«class \(code)»"
		}
	}

	/// `«class xxxx»` is a keyword only when `xxxx` is a four-character code (four Mac OS Roman characters); any
	/// other key, from a file too, is a user property. (Four emoji passed the old check and then trapped when the
	/// record was made.)
	init(plistKey key: String) {
		let code = String(key.dropFirst(7).dropLast())
		if key.hasPrefix("«class "), key.hasSuffix("»"), code.data(using: .macOSRoman)?.count == 4 {
			self = .code(code)
		} else {
			self = .user(key)
		}
	}
}

/// How deeply the lists and records in a flattened descriptor (`dle2`) nest, read without unflattening it.
///
/// The layout, as `AEFlattenDesc` writes it: `dle2`, four bytes, then the descriptor as its type, a 4-byte length
/// and that many bytes of data (an item's data is padded to an even length). A list or record's data is a 4-byte
/// count, four bytes, then its items: a list's are type, length and data; a record's have a 4-byte keyword first. At
/// the top only, a `list` or `reco` has 16 more bytes before the count. A record coerced to another type (`docu`,
/// an object specifier's `obj `) has a record's data under its own type, and nothing else marks it, so anything
/// whose data reads as a whole number of record items counts as a record here: counting too deep leaves a value
/// as data, counting too shallow would let a document's value through.
enum FlattenedDescriptor {
	/// The deepest nesting, or nil if the data doesn't read as a flattened descriptor.
	static func depth(of data: Data) -> Int? {
		let bytes = [UInt8](data)
		guard bytes.count >= 16 else { return nil }
		func word(_ at: Int) -> Int? {
			guard at >= 0, at + 4 <= bytes.count else { return nil }
			return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
		}
		func type(_ at: Int) -> String? {
			guard at + 4 <= bytes.count else { return nil }
			return String(decoding: bytes[at ..< at + 4], as: UTF8.self)
		}
		/// Whether `range` holds a whole number of record items (keyword, type, length, padded data).
		func readsAsRecord(_ range: Range<Int>) -> Bool {
			guard range.count >= 8, let count = word(range.lowerBound), word(range.lowerBound + 4) == 0 else { return false }
			var at = range.lowerBound + 8
			for _ in 0 ..< count {
				guard let length = word(at + 8), length >= 0, length <= range.upperBound - (at + 12) else { return false }
				at += 12 + length + (length & 1)
			}
			return at == range.upperBound || at - 1 == range.upperBound
		}

		guard let topType = type(8), let topLength = word(12), topLength <= bytes.count - 16 else { return nil }
		struct Frame { var next: Int; let end: Int; let isRecord: Bool }
		var frames: [Frame] = []
		var deepest = 0
		/// Enters the container (if it is one) whose data is `range`.
		func enter(_ typeName: String, _ range: Range<Int>, top: Bool) {
			let isList = typeName == "list", isRecord = typeName == "reco"
			var start = range.lowerBound
			if top, isList || isRecord, word(start + 8) == 0x18, type(start + 12) == typeName {
				start += 16
			}
			guard isList || isRecord || readsAsRecord(start ..< range.upperBound), let count = word(start), count >= 0 else { return }
			frames.append(Frame(next: start + 8, end: range.upperBound, isRecord: !isList))
			deepest = max(deepest, frames.count)
		}
		enter(topType, 16 ..< 16 + topLength, top: true)
		while let frame = frames.last {
			let at = frame.next + (frame.isRecord ? 4 : 0)
			guard frame.next < frame.end, let itemType = type(at), let length = word(at + 4), length >= 0, at + 8 + length <= frame.end else {
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].next = at + 8 + length + (length & 1)
			enter(itemType, at + 8 ..< at + 8 + length, top: false)
		}
		return deepest
	}
}
