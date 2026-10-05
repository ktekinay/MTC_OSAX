import Foundation

/// An AppleScript record's fields in order, with both kinds of key: four-character codes (`name` is `pnam`) and
/// the user-defined properties a script makes (`{abc:1}`), which Apple events keep as a `usrf` list of
/// alternating names and values.
public struct RecordFields: AppleEventEncodable {
	public enum Key: Hashable {
		case code(String)
		case user(String)
	}

	public var fields: [(key: Key, value: NSAppleEventDescriptor)]

	public init(_ fields: [(key: Key, value: NSAppleEventDescriptor)] = []) {
		self.fields = fields
	}

	/// Nil unless the descriptor is a record.
	public init?(_ descriptor: NSAppleEventDescriptor) {
		guard descriptor.isRecordDescriptor, descriptor.descriptorType != typeAEList else {
			return nil
		}
		fields = []
		for index in stride(from: 1, through: descriptor.numberOfItems, by: 1) {
			let keyword = descriptor.keywordForDescriptor(at: index)
			guard let value = descriptor.atIndex(index) else {
				continue
			}
			if keyword.fourCharString == "usrf", value.descriptorType == typeAEList {
				var item = 1
				while item + 1 <= value.numberOfItems {
					if let name = value.atIndex(item)?.stringValue, let userValue = value.atIndex(item + 1) {
						fields.append((.user(name), userValue))
					}
					item += 2
				}
			} else {
				fields.append((.code(keyword.fourCharString), value))
			}
		}
	}

	public subscript(key: Key) -> NSAppleEventDescriptor? {
		fields.first { $0.key == key }?.value
	}

	/// A record: fields with codes in order, then the user-defined ones in a `usrf` list.
	public var appleEventDescriptor: NSAppleEventDescriptor {
		let record = NSAppleEventDescriptor.record()
		let user = NSAppleEventDescriptor.list()
		for (key, value) in fields {
			switch key {
			case let .code(code):
				record.setDescriptor(value, forKeyword: FourCharCode(fourCharString: code))
			case let .user(name):
				user.insert(NSAppleEventDescriptor(string: name), at: user.numberOfItems + 1)
				user.insert(value, at: user.numberOfItems + 1)
			}
		}
		if user.numberOfItems > 0 {
			record.setDescriptor(user, forKeyword: FourCharCode(fourCharString: "usrf"))
		}
		return record
	}
}
