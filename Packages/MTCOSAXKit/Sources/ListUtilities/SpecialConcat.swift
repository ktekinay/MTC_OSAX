import AppleEventCore
import Foundation
import Numerics

/// `special concat`: merges two records property by property, or puts two tab-separated text tables side by side.
enum SpecialConcat {
	static func concat(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let first = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let second = try request.requiredParameter("with", as: AnyDescriptor.self).descriptor
		if let a = RecordFields(first), let b = RecordFields(second) {
			return merge(a, b).appleEventDescriptor
		}
		// Text with anything but text is an error (SatimageOSAX returned garbage for a record).
		guard ListUtilities.isText(first), ListUtilities.isText(second), let a = first.stringValue, let b = second.stringValue else {
			throw OSAXError.coercionFailed
		}
		return NSAppleEventDescriptor(string: sideBySide(a, b))
	}

	/// The first record's properties, combined with the second's where both have them, then the second's others.
	static func merge(_ a: RecordFields, _ b: RecordFields) -> RecordFields {
		var result = RecordFields(a.fields.map { key, value in
			(key, b[key].map { combine(value, $0) } ?? value)
		})
		for field in b.fields where a[field.key] == nil {
			result.fields.append(field)
		}
		return result
	}

	/// Lists are joined (a value is added to a list), numbers added (as reals), records merged; anything else keeps
	/// the first value.
	static func combine(_ x: NSAppleEventDescriptor, _ y: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
		if x.descriptorType == typeAEList {
			return ((ListUtilities.items(x) ?? []) + (ListUtilities.items(y).flatMap { y.descriptorType == typeAEList ? $0 : nil } ?? [y])).appleEventDescriptor
		}
		if let a = RecordFields(x), let b = RecordFields(y) {
			return merge(a, b).appleEventDescriptor
		}
		if let first = try? Numbers.number(x), !ListUtilities.isText(x) {
			let items = ListUtilities.items(y)
			let other = items.flatMap { $0.count == 1 ? $0[0] : nil } ?? y
			if let second = try? Numbers.number(other), !ListUtilities.isText(other) {
				return NSAppleEventDescriptor(double: first + second)
			}
		}
		return x
	}

	/// Row by row, joined with a tab. Rows are separated as in the first table (return, linefeed or both); a table
	/// with fewer rows gets empty cells; a final separator is kept.
	static func sideBySide(_ a: String, _ b: String) -> String {
		let separator = [("\r\n"), "\r", "\n"].first { a.contains($0) || b.contains($0) } ?? "\r"
		func rows(_ text: String) -> (rows: [String], trailing: Bool) {
			guard !text.isEmpty else {
				return ([], false)
			}
			var rows = text.components(separatedBy: separator)
			let trailing = rows.count > 1 && rows.last == ""
			if trailing {
				rows.removeLast()
			}
			return (rows, trailing)
		}
		let (left, leftTrailing) = rows(a)
		let (right, rightTrailing) = rows(b)
		let lines = (0 ..< max(left.count, right.count)).map { index in
			(left.indices.contains(index) ? left[index] : "") + "\t" + (right.indices.contains(index) ? right[index] : "")
		}
		return lines.joined(separator: separator) + (leftTrailing || rightTrailing ? separator : "")
	}
}

extension ListUtilities {
	static func isText(_ descriptor: NSAppleEventDescriptor) -> Bool {
		[typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType)
	}
}
