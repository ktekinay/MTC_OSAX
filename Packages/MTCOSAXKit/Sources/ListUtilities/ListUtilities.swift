import AppleEventCore
import Foundation
import Numerics

/// Satimage's "Array and List Utilities" suite.
/// Behavior recorded from SatimageOSAX in `Fixtures/ListUtilities`; where Satimage was broken, MTC_OSAX follows the
/// dictionary (`Fixtures/ListUtilitiesFixes`, listed in Implemented/PLAN-MathAndLists.md).
public enum ListUtilities {
	@MainActor
	public static func commands() -> [CommandDefinition] {
		[
			CommandDefinition("sortlist", code: "SATISort", handler: Sorting.sortList),
			CommandDefinition("masklist", code: "SATIMASk", handler: maskList),
			CommandDefinition("topological sort", code: "SATITSrt", handler: TopologicalSort.sort),
			CommandDefinition("suppress item", code: "SATIDLKY", handler: suppressItem),
			CommandDefinition("exclude items", code: "SATIEIFL") { try filterItems($0, keeping: false) },
			CommandDefinition("keep items", code: "SATIKIFL") { try filterItems($0, keeping: true) },
			CommandDefinition("special concat", code: "SATICONC", handler: SpecialConcat.concat),
		]
	}

	static let invalidIndex = OSAXError(-1719) // errAEIllegalIndex

	/// The items of a list descriptor, or the numbers of an `array of real`.
	static func items(_ descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor]? {
		if let values = ArrayOfReal.values(of: descriptor) {
			return values.map(NSAppleEventDescriptor.init(double:))
		}
		guard descriptor.descriptorType == typeAEList else {
			return nil
		}
		return (0 ..< descriptor.numberOfItems).map { descriptor.atIndex($0 + 1)! }
	}

	static func isList(_ descriptor: NSAppleEventDescriptor) -> Bool {
		descriptor.descriptorType == typeAEList || ArrayOfReal.values(of: descriptor) != nil
	}

	/// An item as text for comparing: text, or a number or boolean in the script's text form; nil otherwise.
	static func text(_ descriptor: NSAppleEventDescriptor) -> String? {
		switch descriptor.descriptorType {
		case typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16"):
			return descriptor.stringValue
		case typeTrue, typeFalse, typeBoolean:
			return descriptor.booleanValue ? "true" : "false"
		case typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
			return descriptor.coerce(toDescriptorType: typeUnicodeText)?.stringValue
		default:
			return nil
		}
	}

	static func isInteger(_ descriptor: NSAppleEventDescriptor) -> Bool {
		[typeSInt16, typeSInt32, typeSInt64].contains(descriptor.descriptorType)
	}

	// MARK: masklist

	/// Keeps the items whose mask value (repeated when the mask is shorter) isn't 0, or replaces the others with
	/// `substitute`. A mask value that isn't a number (such as a boolean) keeps its item, as in SatimageOSAX.
	static func maskList(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let list = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let maskDescriptor = try request.requiredParameter("with", as: AnyDescriptor.self).descriptor
		guard list.descriptorType == typeAEList, let items = items(list) else {
			throw OSAXError.parameterError
		}
		let mask: [Double?] = (Self.items(maskDescriptor) ?? [maskDescriptor]).map { try? Numbers.number($0) }
		// An empty list with a mask is an empty list, but a longer mask otherwise is -50, as in SatimageOSAX.
		if items.isEmpty, !mask.isEmpty {
			return list
		}
		guard !mask.isEmpty, mask.count <= items.count else {
			throw OSAXError.parameterError
		}
		let substitute = request.descriptor(for: "Subs")
		return items.enumerated().compactMap { index, item in
			if let value = mask[index % mask.count], value == 0 {
				return substitute
			}
			return item
		}.appleEventDescriptor
	}

	// MARK: suppress item

	/// Deletes items by index (negative from the end) from a list, or properties by key from a record.
	static func suppressItem(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let which = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let from = try request.requiredParameter("from", as: AnyDescriptor.self).descriptor
		let selectors = items(which).flatMap { which.descriptorType == typeAEList ? $0 : nil } ?? [which]
		if var record = RecordFields(from) {
			var removed = Set<RecordFields.Key>()
			for selector in selectors {
				if isInteger(selector) {
					throw invalidIndex
				}
				guard let key = recordKey(selector, in: record) else {
					throw OSAXError.parameterError
				}
				removed.insert(key)
			}
			record.fields.removeAll { removed.contains($0.key) }
			return record.appleEventDescriptor
		}
		guard from.descriptorType == typeAEList, let list = items(from) else {
			throw OSAXError.coercionFailed
		}
		var removed = Set<Int>()
		for selector in selectors {
			guard isInteger(selector) else {
				throw OSAXError.parameterError
			}
			let index = Int(selector.int32Value)
			let position = index < 0 ? list.count + index : index - 1
			guard index != 0, list.indices.contains(position) else {
				throw invalidIndex
			}
			removed.insert(position)
		}
		return list.enumerated().filter { !removed.contains($0.offset) }.map(\.element).appleEventDescriptor
	}

	/// A record key from a script: a keyword (`name`), or text naming a user property (`"abc"`) or a
	/// four-character code (`"pnam"`) of one of the record's keys.
	static func recordKey(_ selector: NSAppleEventDescriptor, in record: RecordFields) -> RecordFields.Key? {
		if selector.descriptorType == typeType || selector.descriptorType == typeEnumerated {
			return .code(selector.typeCodeValue.fourCharString)
		}
		if selector.descriptorType == typeObjectSpecifier, let property = selector.forKeyword(AEKeyword(keyAEKeyData)) {
			return .code(property.typeCodeValue.fourCharString)
		}
		guard let name = text(selector) else {
			return nil
		}
		if name.utf8.count == 4, record[.code(name)] != nil {
			return .code(name)
		}
		return .user(name)
	}

	// MARK: exclude items, keep items

	/// Removes (or keeps only) the items that are in the filter list, compared as text; with a list of lists, by
	/// the list at `with respect to`, removing the same positions from the others.
	static func filterItems(_ request: AppleEventRequest, keeping: Bool) throws -> NSAppleEventDescriptor {
		let filterDescriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let from = try request.requiredParameter("from", as: AnyDescriptor.self).descriptor
		let caseSensitive = try request.parameter("CaSe", default: true)
		guard let lists = items(from) else {
			throw OSAXError.coercionFailed
		}
		let fold = { (text: String) in caseSensitive ? text : text.lowercased() }
		let filter = Set((items(filterDescriptor) ?? [filterDescriptor]).compactMap(text).map(fold))
		let matches = { (item: NSAppleEventDescriptor) in text(item).map { filter.contains(fold($0)) } ?? false }

		let isListOfLists = !lists.isEmpty && lists.allSatisfy(isList)
		guard isListOfLists else {
			return lists.filter { matches($0) == keeping }.appleEventDescriptor
		}
		let reference = try request.parameter("With", default: 1)
		guard lists.indices.contains(reference - 1), let referenceItems = items(lists[reference - 1]) else {
			throw invalidIndex
		}
		let kept = Set(referenceItems.indices.filter { matches(referenceItems[$0]) == keeping })
		return lists.map { list in
			let values = items(list) ?? []
			let filtered = values.indices.filter(kept.contains).map { values[$0] }
			if ArrayOfReal.values(of: list) != nil {
				return ArrayOfReal(filtered.map(\.doubleValue)).appleEventDescriptor
			}
			return filtered.appleEventDescriptor
		}.appleEventDescriptor
	}
}
