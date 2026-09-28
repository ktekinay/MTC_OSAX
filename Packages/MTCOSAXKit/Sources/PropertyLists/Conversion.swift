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
	static let maximumDepth = 512
	static let tooDeep = OSAXError(-50, "The value is nested more than \(maximumDepth) levels deep.")

	/// -50 for Foundation objects (a parsed file) nested more than `maximumDepth` levels deep.
	static func checkDepth(_ object: Any, depth: Int = 0) throws {
		guard depth <= maximumDepth else { throw tooDeep }
		switch object {
		case let dictionary as NSDictionary:
			for value in dictionary.allValues { try checkDepth(value, depth: depth + 1) }
		case let array as NSArray:
			for value in array { try checkDepth(value, depth: depth + 1) }
		default:
			break
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
		case typeSInt16, typeSInt32, typeSInt64:
			return .integer(Int64(descriptor.int32Value))
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

	static func flatten(_ descriptor: NSAppleEventDescriptor) -> Data {
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
	/// from a file can claim more than it holds; `AEUnflattenDesc` would read past the end).
	static func unflatten(_ data: Data) -> NSAppleEventDescriptor? {
		guard data.starts(with: Array("dle2".utf8)) else {
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

	/// An element from Foundation objects (a parsed file, checked with `checkDepth`). Dictionaries keep their key order.
	static func node(from object: Any, in document: Document) -> Node {
		switch object {
		case let dictionary as NSDictionary:
			return Node(.dictionary(dictionary.mappingValues { node(from: $0, in: document) }), in: document)
		case let array as NSArray:
			return Node(.array(array.map { node(from: $0, in: document) }), in: document)
		case let text as String:
			return Node(.string(text), in: document)
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return Node(.boolean(number.boolValue), in: document)
			}
			return Node(CFNumberIsFloatType(number) ? .real(number.doubleValue) : .integer(number.int64Value), in: document)
		case let date as Date:
			return Node(.date(date), in: document)
		case let data as Data:
			return Node(.data(data), in: document)
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

	init(plistKey key: String) {
		if key.hasPrefix("«class "), key.hasSuffix("»"), key.count == 12 {
			self = .code(String(key.dropFirst(7).dropLast()))
		} else {
			self = .user(key)
		}
	}
}
