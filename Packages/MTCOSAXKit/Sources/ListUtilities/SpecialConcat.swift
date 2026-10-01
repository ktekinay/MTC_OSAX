import AppleEventCore
import Foundation
import Numerics

/// `special concat`: merges two records property by property, or puts two tab-separated text tables side by side.
enum SpecialConcat {
	static func concat(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let first = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let second = try request.requiredParameter("with", as: AnyDescriptor.self).descriptor
		// Records are merged recursively.
		guard !first.nestsDeeper(), !second.nestsDeeper() else { throw NSAppleEventDescriptor.nestedTooDeep }
		if let a = RecordFields(first), let b = RecordFields(second) {
			return try merge(a, b).appleEventDescriptor
		}
		// Text with anything but text is an error (SatimageOSAX returned garbage for a record).
		guard first.isText, second.isText, let a = first.stringValue, let b = second.stringValue else {
			throw OSAXError.coercionFailed
		}
		return NSAppleEventDescriptor(string: sideBySide(a, b))
	}

	/// The first record's properties, combined with the second's where both have them, then the second's others.
	static func merge(_ a: RecordFields, _ b: RecordFields) throws -> RecordFields {
		var result = RecordFields(try a.fields.map { key, value in
			(key, try b[key].map { try combine(value, $0) } ?? value)
		})
		for field in b.fields where a[field.key] == nil {
			result.fields.append(field)
		}
		return result
	}

	/// Lists are joined (a value is added to a list), numbers added (as reals), records merged; anything else keeps
	/// the first value.
	static func combine(_ x: NSAppleEventDescriptor, _ y: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
		if x.descriptorType == typeAEList {
			return ((ListUtilities.items(x) ?? []) + (ListUtilities.items(y).flatMap { y.descriptorType == typeAEList ? $0 : nil } ?? [y])).appleEventDescriptor
		}
		if let a = RecordFields(x), let b = RecordFields(y) {
			return try merge(a, b).appleEventDescriptor
		}
		if let first = try? Numbers.number(x), !x.isText {
			let items = ListUtilities.items(y)
			let other = items.flatMap { $0.count == 1 ? $0[0] : nil } ?? y
			if let second = try? Numbers.number(other), !other.isText {
				// A sum too large for a real is -50, as the math functions' results are (it was infinity).
				let sum = first + second
				guard sum.isFinite || !first.isFinite || !second.isFinite else {
					throw OSAXError(-50, "The sum is too large for a real.")
				}
				return NSAppleEventDescriptor(double: sum)
			}
		}
		return x
	}

	/// Row by row, joined with a tab. Each table's rows end at any line ending (return, linefeed or both), and each
	/// row of the result ends as that row of the second table did, or else of the first, as in SatimageOSAX (which
	/// the comment here used to say took the first table's, and the code took whichever came first in a fixed
	/// order, splitting both tables with it). A table with fewer rows gets empty cells; a final line ending is kept.
	static func sideBySide(_ a: String, _ b: String) -> String {
		let left = rows(a)
		let right = rows(b)
		var result = ""
		for index in 0 ..< max(left.count, right.count) {
			let first = left.indices.contains(index) ? left[index] : nil
			let second = right.indices.contains(index) ? right[index] : nil
			result += (first?.text ?? "") + "\t" + (second?.text ?? "") + (second?.ending ?? first?.ending ?? "")
		}
		return result
	}

	/// A table's rows, each with the line ending after it (none for a last row without one).
	static func rows(_ text: String) -> [(text: String, ending: String?)] {
		var rows: [(text: String, ending: String?)] = []
		var row = ""
		var characters = text[...]
		while let character = characters.first {
			characters = characters.dropFirst()
			// "\r\n" is one Character in Swift.
			if character == "\r\n" || character == "\r" || character == "\n" {
				rows.append((row, String(character)))
				row = ""
			} else {
				row.append(character)
			}
		}
		if !row.isEmpty {
			rows.append((row, nil))
		}
		return rows
	}
}
