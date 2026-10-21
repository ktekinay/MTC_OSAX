import CoreServices
import Foundation

/// A list's items read with the Apple Event Manager (`AESizeOfNthItem`, `AEGetNthPtr`), and lists made with it
/// (`AEPutDesc`, `AEPutPtr`), without an `NSAppleEventDescriptor` for each item: for a million texts, reading each
/// with `atIndex` and its `stringValue` as UTF-8 took 386 ms, and reading its UTF-16 into the sort keys takes 72.
/// Indexes are from 0.
package struct RawList {
	/// Holds the list's `AEDesc`, which is valid while it lives.
	private let list: NSAppleEventDescriptor
	package let count: Int

	/// nil if `descriptor` isn't a list.
	package init?(_ descriptor: NSAppleEventDescriptor) {
		guard descriptor.descriptorType == typeAEList else {
			return nil
		}
		list = descriptor
		count = descriptor.numberOfItems
	}

	/// A list of one item.
	package init(single item: NSAppleEventDescriptor) {
		list = NSAppleEventDescriptor.list()
		list.insert(item, at: 1)
		count = 1
	}

	private func withList<Result>(_ body: (UnsafePointer<AEDesc>) throws -> Result) rethrows -> Result {
		try withExtendedLifetime(list) { try body(list.aeDesc!) }
	}

	/// An item's descriptor type and the size of its data.
	package func info(_ index: Int) -> (type: DescType, size: Int) {
		withList { list in
			var type: DescType = 0, size = 0
			AESizeOfNthItem(list, index + 1, &type, &size)
			return (type, size)
		}
	}

	/// An item's data as a value of its own type, which is `type` and `MemoryLayout<Value>.size` long (check `info`).
	package func value<Value: BitwiseCopyable>(_ index: Int, type: DescType, as _: Value.Type) -> Value {
		withList { list in
			withUnsafeTemporaryAllocation(of: Value.self, capacity: 1) { buffer in
				var keyword: AEKeyword = 0, actualType: DescType = 0, size = 0
				AEGetNthPtr(list, index + 1, type, &keyword, &actualType, buffer.baseAddress!, MemoryLayout<Value>.size, &size)
				return buffer[0]
			}
		}
	}

	/// A `utxt` item's UTF-16 (`size` bytes, from `info`), into `buffer` (which grows if it must).
	package func utf16(_ index: Int, size: Int, into buffer: inout [UInt16]) -> Int {
		if buffer.count < size / 2 {
			buffer = [UInt16](repeating: 0, count: size / 2)
		}
		return withList { list in
			buffer.withUnsafeMutableBytes { bytes in
				var keyword: AEKeyword = 0, actualType: DescType = 0, actualSize = 0
				AEGetNthPtr(list, index + 1, typeUnicodeText, &keyword, &actualType, bytes.baseAddress!, bytes.count, &actualSize)
				return min(actualSize, bytes.count) / 2
			}
		}
	}

	/// An item seen by `forEachItem`: its type and size, and for a number or a type (eight bytes or fewer) its data.
	package struct Item {
		package var index: Int
		package var type: DescType
		package var size: Int
		/// The data of a `shor`, `long`, `comp`, `sing`, `doub` or `type` item, little-endian from the low byte; 0
		/// for other items, whose data isn't read (a list's would be copied whole).
		package var bits: UInt64

		/// Whether `bits` holds the item's data: a number or a type, eight bytes or fewer.
		package var hasBits: Bool {
			size <= 8 && RawList.scalarTypes.contains(type)
		}

		/// Whether the item is `missing value`.
		package var isMissingValue: Bool {
			type == typeType && UInt32(truncatingIfNeeded: bits) == NSAppleEventDescriptor.missingValueCode
		}

		/// The item's number, if it's an integer or a real; nil for anything else.
		package var number: Double? {
			switch type {
			case typeSInt16: Double(Int16(truncatingIfNeeded: bits))
			case typeSInt32: Double(Int32(truncatingIfNeeded: bits))
			case typeSInt64: Double(Int64(bitPattern: bits))
			case typeIEEE32BitFloatingPoint: Double(Float32(bitPattern: UInt32(truncatingIfNeeded: bits)))
			case typeIEEE64BitFloatingPoint: Double(bitPattern: bits)
			default: nil
			}
		}
	}

	private static let scalarTypes: Set<DescType> = [typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint, typeType]

	/// Each item in order, with one look at the list: reading 1,000,000 reals through `info` and `value` took 127 ms,
	/// and this takes about 93. (One `AEGetNthPtr` of any type for each item would be quicker, but for an item that
	/// is a list it copies the whole list: 50 ms for one of 100,000.)
	package func forEachItem(_ body: (Item) throws -> Void) rethrows {
		try withList { list in
			var keyword: AEKeyword = 0, actualType: DescType = 0, actualSize = 0
			for index in 0 ..< count {
				var item = Item(index: index, type: 0, size: 0, bits: 0)
				AESizeOfNthItem(list, index + 1, &item.type, &item.size)
				if item.size <= 8, Self.scalarTypes.contains(item.type) {
					AEGetNthPtr(list, index + 1, item.type, &keyword, &actualType, &item.bits, 8, &actualSize)
				}
				try body(item)
			}
		}
	}

	/// An item as a descriptor, for the kinds read no other way.
	package func descriptor(_ index: Int) -> NSAppleEventDescriptor {
		list.atIndex(index + 1)!
	}

	/// What goes in a made list instead of the item.
	package enum Replacement {
		case real(Double)
		case text(String)
	}

	/// A list of the items at `rows`, in that order, or their replacements.
	package func list(of rows: [Int], replacing replacement: (Int) -> Replacement? = { _ in nil }) throws -> NSAppleEventDescriptor {
		var result = AEDescList()
		try OSAXError.check(AECreateList(nil, 0, false, &result))
		do {
			try withList { list in
				for row in rows {
					switch replacement(row) {
					case nil:
						var item = AEDesc(), keyword: AEKeyword = 0
						try OSAXError.check(AEGetNthDesc(list, row + 1, typeWildCard, &keyword, &item))
						defer { AEDisposeDesc(&item) }
						try OSAXError.check(AEPutDesc(&result, 0, &item))
					case var .real(value)?:
						try OSAXError.check(AEPutPtr(&result, 0, typeIEEE64BitFloatingPoint, &value, 8))
					case let .text(text)?:
						// A pointer even for no text (an empty array's may be nil).
						let units = Array(text.utf16) + [0]
						try units.withUnsafeBytes { try OSAXError.check(AEPutPtr(&result, 0, typeUnicodeText, $0.baseAddress!, $0.count - 2)) }
					}
				}
			}
		} catch {
			AEDisposeDesc(&result)
			throw error
		}
		return NSAppleEventDescriptor(aeDescNoCopy: &result)
	}
}
