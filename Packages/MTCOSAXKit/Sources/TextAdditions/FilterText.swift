import AppleEventCore
import Foundation
import TextMatching

extension TextAdditions {
	/// `filter text`: groups regex matches by a key into an XML property list. It never worked in SatimageOSAX
	/// (every call replied -1708), so this follows its dictionary entry:
	/// - every match of the pattern gives a key (`key` template) and a value (`using` template, default `\0`);
	/// - `as string` (the default) joins each key's values with `separator` (default linefeed); `as list` gives an
	///   array per key, without repeats when `duplicates` is false;
	/// - the property list is returned as XML text, written to the file given as `into`, or added to the dictionary
	///   a CFRef given as `into` refers to (replacing keys it already has); both return nothing.
	static func filterText(_ request: AppleEventRequest, context: TextContext) throws -> NSAppleEventDescriptor? {
		let pattern = try request.requiredDirectParameter(as: String.self)
		let input = try TextInput(request, keyword: "$in ")
		var options = try SearchOptions(request, context: context)
		options.regexp = true
		let searcher = try TextSearcher(pattern: pattern, options: options, context: context)
		let key = try Template(request.requiredParameter("key ", as: String.self), dollarReferences: options.dollarReferences)
		let value = try Template(request.parameter("by  ", default: "\\0"), dollarReferences: options.dollarReferences)
		let asList = try request.parameter("rtyp", as: AnyDescriptor.self).map {
			$0.descriptor.typeCodeValue == typeAEList
		} ?? false
		let duplicates = try request.parameter("Dupl", default: true)
		let separator = try request.parameter("sepa", default: "\n")

		let text: String
		switch input {
		case let .single(string): text = string
		case let .list(strings): text = strings.joined(separator: "\n")
		case let .file(url): text = try FileText.read(url).text
		}

		// Values per key; keys in the order found.
		var values: [String: [String]] = [:]
		var keys: [String] = []
		let utf16 = UTF16Text(text)
		for match in searcher.allMatches(in: utf16) {
			let keyText = try key.expand(match, in: utf16, groupCount: searcher.groupCount, namedGroups: searcher.namedGroups)
			let valueText = try value.expand(match, in: utf16, groupCount: searcher.groupCount, namedGroups: searcher.namedGroups)
			if asList, !duplicates, values[keyText]?.contains(valueText) == true {
				continue
			}
			if values[keyText] == nil {
				keys.append(keyText)
			}
			values[keyText, default: []].append(valueText)
		}
		let entries: [(key: String, value: Any)] = keys.map { key in
			(key, asList ? values[key]! : values[key]!.joined(separator: separator))
		}
		if let destination = request.descriptor(for: "into"), destination.descriptorType == FourCharCode(fourCharString: "CFob") {
			guard let propertyLists = context.propertyLists else {
				throw OSAXError.eventNotHandled
			}
			try propertyLists(destination, entries)
			return nil
		}
		let plist: [String: Any] = asList ? values : values.mapValues { $0.joined(separator: separator) }
		let data: Data
		do {
			data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
		} catch {
			throw OSAXError.general("Couldn't make the property list: \(error.localizedDescription)")
		}

		if let destination = request.descriptor(for: "into") {
			guard TextInput.isFile(destination) || destination.descriptorType == typeUnicodeText
				|| destination.descriptorType == typeUTF8Text || destination.descriptorType == typeChar
			else {
				throw OSAXError.coercionFailed
			}
			try FileText.write(data, to: URL(appleEventDescriptor: destination), append: false)
			return nil
		}
		return String(decoding: data, as: UTF8.self).appleEventDescriptor
	}
}
