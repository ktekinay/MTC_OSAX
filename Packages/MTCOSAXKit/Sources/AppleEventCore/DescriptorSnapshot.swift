import Foundation

/// A lossless, JSON-friendly copy of an Apple event descriptor, keeping every descriptor type.
/// Used to store fixtures and to describe values for debugging.
///
/// Only the properties relevant to `type` are set: text for text types, `integer` for `long`/`shor`,
/// `real` for `doub`/`sing` (or `text` "inf", "-inf" or "nan", which JSON can't hold), `boolean` for `bool`, `code` for `type`/`enum`/`keyw`, `items` for
/// lists and for Satimage's `array of real` (`Lido`, as `doub` items), `fields` for records and Apple event parameters, and `hex` for anything
/// else.
public struct DescriptorSnapshot: Codable, Hashable {
	public var type: String
	public var text: String?
	public var integer: Int?
	public var real: Double?
	public var boolean: Bool?
	public var code: String?
	public var items: [DescriptorSnapshot]?
	public var fields: [Field]?
	public var eventClass: String?
	public var eventID: String?
	public var hex: String?

	public struct Field: Codable, Hashable {
		public var key: String
		public var value: DescriptorSnapshot

		public init(key: String, value: DescriptorSnapshot) {
			self.key = key
			self.value = value
		}
	}

	public init(type: String) {
		self.type = type
	}

	// MARK: Descriptor → snapshot

	public init(_ descriptor: NSAppleEventDescriptor) {
		self.init(descriptor, hexLimit: nil)
	}

	/// `hexLimit`: at most that many bytes of data as hex, with `…` after (for `mtc_describe`; fixtures keep every
	/// byte).
	public init(_ descriptor: NSAppleEventDescriptor, hexLimit: Int?) {
		type = descriptor.descriptorType.fourCharString
		func hexText(_ data: Data) -> String {
			let shown = hexLimit.map { data.prefix($0) } ?? data
			return shown.map { String(format: "%02x", $0) }.joined() + (shown.count < data.count ? "…" : "")
		}
		switch type {
		case "aevt":
			eventClass = descriptor.eventClass.fourCharString
			eventID = descriptor.eventID.fourCharString
			fields = Self.fields(of: descriptor, hexLimit: hexLimit)
		case "list":
			items = (0 ..< descriptor.numberOfItems).map { DescriptorSnapshot(descriptor.atIndex($0 + 1)!, hexLimit: hexLimit) }
		case "Lido" where ArrayOfReal.values(of: descriptor) != nil:
			items = ArrayOfReal.values(of: descriptor)!.map { DescriptorSnapshot(NSAppleEventDescriptor(double: $0)) }
		case "utxt", "ut16", "utf8", "TEXT":
			text = descriptor.stringValue
		case "furl":
			// A file URL, kept readable so fixtures can swap paths.
			text = String(decoding: descriptor.data, as: UTF8.self)
		case "alis":
			// An alias holds its absolute path in binary form; keep the POSIX path instead, so fixtures can swap
			// paths. It's recreated as a file URL, which commands accept the same way.
			if let url = descriptor.coerce(toDescriptorType: typeFileURL)?.fileURLValue {
				text = url.path
			} else {
				hex = hexText(descriptor.data)
			}
		case "fsrf":
			// An FSRef identifies an item by volume and node; keep its POSIX path instead, like an alias.
			if let path = descriptor.fileReferencePath {
				text = path
			} else {
				hex = hexText(descriptor.data)
			}
		case "long", "shor":
			integer = Int(descriptor.int32Value)
		case "doub", "sing":
			let value = descriptor.doubleValue
			if value.isFinite {
				real = value
			} else {
				text = value.isNaN ? "nan" : (value < 0 ? "-inf" : "inf")
			}
		case "bool":
			boolean = descriptor.booleanValue
		case "true", "fals", "null":
			break
		case "type":
			code = descriptor.typeCodeValue.fourCharString
		case "enum":
			code = descriptor.enumCodeValue.fourCharString
		case "keyw":
			// Descriptor data needn't be aligned, or long enough.
			let data = descriptor.data
			code = data.count >= 4 ? data.withUnsafeBytes { $0.loadUnaligned(as: FourCharCode.self) }.fourCharString : "????"
		default:
			if descriptor.isRecordDescriptor {
				fields = Self.fields(of: descriptor, hexLimit: hexLimit)
			} else {
				hex = hexText(descriptor.data)
			}
		}
	}

	private static func fields(of descriptor: NSAppleEventDescriptor, hexLimit: Int? = nil) -> [Field] {
		(0 ..< descriptor.numberOfItems).map { index in
			Field(
				key: descriptor.keywordForDescriptor(at: index + 1).fourCharString,
				value: DescriptorSnapshot(descriptor.atIndex(index + 1)!, hexLimit: hexLimit)
			)
		}
	}

	// MARK: Snapshot → descriptor

	/// Recreates the descriptor. Apple events are recreated with no target, ready to pass to a dispatcher.
	public var descriptor: NSAppleEventDescriptor {
		let typeCode = FourCharCode(fourCharString: type)
		switch type {
		case "aevt":
			let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: (eventClass ?? "????") + (eventID ?? "????")))
			for field in fields ?? [] {
				event.setParam(field.value.descriptor, forKeyword: FourCharCode(fourCharString: field.key))
			}
			return event
		case "list":
			let list = NSAppleEventDescriptor.list()
			for (index, item) in (items ?? []).enumerated() {
				list.insert(item.descriptor, at: index + 1)
			}
			return list
		case "Lido" where items != nil:
			return ArrayOfReal(items!.map(\.realValue)).appleEventDescriptor
		case "utxt":
			return NSAppleEventDescriptor(string: text ?? "")
		case "ut16":
			// UTF-16 with a byte-order mark, as SatimageOSAX returns text.
			return NSAppleEventDescriptor(descriptorType: typeCode, data: (text ?? "").data(using: .utf16))!
		case "utf8", "furl":
			return NSAppleEventDescriptor(descriptorType: typeCode, data: (text ?? "").data(using: .utf8))!
		case "alis" where text != nil:
			// Aliases can't be created in-process; a file URL to the same path stands in for it.
			return NSAppleEventDescriptor(fileURL: URL(fileURLWithPath: text!))
		case "fsrf" where text != nil:
			// An FSRef needs an existing item; a file URL stands in for a missing one.
			let url = URL(fileURLWithPath: text!)
			return .fileReference(url) ?? NSAppleEventDescriptor(fileURL: url)
		case "TEXT":
			return NSAppleEventDescriptor(descriptorType: typeCode, data: (text ?? "").data(using: .macOSRoman))!
		case "long":
			return NSAppleEventDescriptor(int32: Int32(integer ?? 0))
		case "shor":
			return withUnsafeBytes(of: Int16(integer ?? 0)) { NSAppleEventDescriptor(descriptorType: typeCode, data: Data($0))! }
		case "doub":
			return NSAppleEventDescriptor(double: realValue)
		case "sing":
			return withUnsafeBytes(of: Float(realValue)) { NSAppleEventDescriptor(descriptorType: typeCode, data: Data($0))! }
		case "bool":
			return NSAppleEventDescriptor(boolean: boolean ?? false)
		case "true", "fals":
			return NSAppleEventDescriptor(descriptorType: typeCode, data: nil)!
		case "null":
			return .null()
		case "type":
			return NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: code ?? "????"))
		case "enum":
			return NSAppleEventDescriptor(enumCode: FourCharCode(fourCharString: code ?? "????"))
		case "keyw":
			return withUnsafeBytes(of: FourCharCode(fourCharString: code ?? "????")) {
				NSAppleEventDescriptor(descriptorType: typeCode, data: Data($0))!
			}
		default:
			if let fields {
				let record = NSAppleEventDescriptor.record()
				for field in fields {
					record.setDescriptor(field.value.descriptor, forKeyword: FourCharCode(fourCharString: field.key))
				}
				return type == "reco" ? record : (record.coerce(toDescriptorType: typeCode) ?? record)
			}
			return NSAppleEventDescriptor(descriptorType: typeCode, data: Data(hexString: hex ?? ""))!
		}
	}

	/// `real`, or the non-finite value stored in `text`.
	private var realValue: Double {
		switch text {
		case "nan": .nan
		case "inf": .infinity
		case "-inf": -.infinity
		default: real ?? 0
		}
	}

	/// The same value with `old` replaced by `new` in all text, including inside file URLs
	/// (where paths are percent-encoded). Used to move fixtures' file paths to where the tests run.
	public func replacingText(_ old: String, with new: String) -> DescriptorSnapshot {
		var copy = self
		if let text {
			if type == "furl" {
				let encode = { (path: String) in path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path }
				copy.text = text.replacingOccurrences(of: encode(old), with: encode(new))
			} else {
				copy.text = text.replacingOccurrences(of: old, with: new)
			}
		}
		copy.items = items?.map { $0.replacingText(old, with: new) }
		copy.fields = fields?.map { Field(key: $0.key, value: $0.value.replacingText(old, with: new)) }
		return copy
	}

	// MARK: Comparison and display

	/// The same value with encodings that scripts can't tell apart unified, for comparing replies:
	/// all text types become `utxt`, and `true`/`fals` become `bool`. Record fields (and the user-defined properties
	/// in `usrf`) are sorted by key, since a record's order means nothing to a script, and SatimageOSAX's property list
	/// records come in hashing order.
	public var normalized: DescriptorSnapshot {
		var copy = self
		if type == "true" || type == "fals" {
			copy = DescriptorSnapshot(type: "bool")
			copy.boolean = type == "true"
		} else if type == "sing" {
			copy.type = "doub"
		} else if Self.textTypes.contains(type) {
			copy.type = "utxt"
		}
		copy.items = items?.map(\.normalized)
		copy.fields = fields?.map { Field(key: $0.key, value: $0.value.normalized) }
		if type != "aevt", var fields = copy.fields {
			fields.sort { $0.key < $1.key }
			if let index = fields.firstIndex(where: { $0.key == "usrf" }), let items = fields[index].value.items, items.count.isMultiple(of: 2) {
				let pairs = stride(from: 0, to: items.count, by: 2).map { (items[$0], items[$0 + 1]) }
				fields[index].value.items = pairs.sorted { ($0.0.text ?? "") < ($1.0.text ?? "") }.flatMap { [$0.0, $0.1] }
			}
			copy.fields = fields
		}
		return copy
	}

	/// Opaque references to documents and their parts: the PropertyList suite's CFRefs and the XML suites' XMLRefs.
	static let referenceTypes: Set = ["CFob", "XMLR"]

	/// Replaces the recorded references (CFRefs, XMLRefs) in `self` with the ones the app returned in their place,
	/// as `references` maps them (by their recorded bytes).
	public func replacingReferences(_ references: [String: DescriptorSnapshot]) -> DescriptorSnapshot {
		if Self.referenceTypes.contains(type), let hex, let replacement = references[hex] {
			return replacement
		}
		var copy = self
		copy.items = items?.map { $0.replacingReferences(references) }
		copy.fields = fields?.map { Field(key: $0.key, value: $0.value.replacingReferences(references)) }
		return copy
	}

	/// Pairs each recorded CFRef in `self` (an expected reply) with the CFRef at the same place in `actual`, adding
	/// new pairs to `references`.
	public func collectReferences(from actual: DescriptorSnapshot, into references: inout [String: DescriptorSnapshot]) {
		if Self.referenceTypes.contains(type), actual.type == type, let hex {
			if references[hex] == nil {
				references[hex] = actual
			}
			return
		}
		for (expected, other) in zip(items ?? [], actual.items ?? []) {
			expected.collectReferences(from: other, into: &references)
		}
		for (expected, other) in zip(fields ?? [], actual.fields ?? []) where expected.key == other.key {
			expected.value.collectReferences(from: other.value, into: &references)
		}
	}

	/// A compact one-line description, e.g. `list [utxt "abc", long 1, reco {mPos: long 2}]`.
	public var summary: String {
		switch type {
		case "aevt":
			return "aevt \(eventClass ?? "")\(eventID ?? "") {\(fieldsSummary)}"
		case "list":
			return "list [\((items ?? []).map(\.summary).joined(separator: ", "))]"
		case "true", "fals", "null":
			return type
		default:
			if let text { return "\(type) \(Self.quoted(text))" }
			if let integer { return "\(type) \(integer)" }
			if let real { return "\(type) \(real)" }
			if let boolean { return "\(type) \(boolean)" }
			if let code { return "\(type) '\(code)'" }
			if fields != nil { return "\(type) {\(fieldsSummary)}" }
			return "\(type) <\(hex ?? "")>"
		}
	}

	private static let textTypes: Set = ["utxt", "ut16", "utf8", "TEXT"]

	/// Whether `actual` equals this expected value, where `{{random:N}}` in expected text stands for any N letters
	/// or digits (used for `mkstemp` and `mkdtemp` names), and an expected value of type `any` matches any value
	/// (used for dates and applications that depend on the machine). Reals may differ by `realTolerance` units in the
	/// last place. Compare normalized snapshots.
	public func matches(_ actual: DescriptorSnapshot, realTolerance: Int = 0) -> Bool {
		// References (CFRefs, XMLRefs) are opaque, and SatimageOSAX gave equal small numbers the same CFRef.
		if type == "any" || (Self.referenceTypes.contains(type) && actual.type == type) {
			return true
		}
		if realTolerance > 0, type == "doub", actual.type == "doub", let expected = real, let other = actual.real {
			return Self.unitsInTheLastPlace(between: expected, and: other) <= realTolerance
		}
		guard let text, text.contains("{{random:"), let actualText = actual.text, type == actual.type else {
			guard type == actual.type, (items ?? []).count == (actual.items ?? []).count,
			      (fields ?? []).count == (actual.fields ?? []).count
			else {
				return self == actual
			}
			var copy = self
			copy.items = actual.items
			copy.fields = actual.fields
			return copy == actual
				&& zip(items ?? [], actual.items ?? []).allSatisfy { $0.matches($1, realTolerance: realTolerance) }
				&& zip(fields ?? [], actual.fields ?? []).allSatisfy { $0.key == $1.key && $0.value.matches($1.value, realTolerance: realTolerance) }
		}
		var pattern = "^"
		var rest = Substring(text)
		while let start = rest.range(of: "{{random:"), let end = rest[start.upperBound...].range(of: "}}"),
		      let length = Int(rest[start.upperBound ..< end.lowerBound])
		{
			pattern += NSRegularExpression.escapedPattern(for: String(rest[..<start.lowerBound])) + "[A-Za-z0-9]{\(length)}"
			rest = rest[end.upperBound...]
		}
		pattern += NSRegularExpression.escapedPattern(for: String(rest)) + "$"
		return actualText.range(of: pattern, options: .regularExpression) != nil
	}

	/// How many representable doubles apart two numbers are (0 for equal numbers, including 0 and -0).
	static func unitsInTheLastPlace(between a: Double, and b: Double) -> Int {
		if a == b {
			return 0
		}
		guard a.isFinite, b.isFinite, a.sign == b.sign else {
			return .max
		}
		let distance = Int64(bitPattern: a.magnitude.bitPattern) - Int64(bitPattern: b.magnitude.bitPattern)
		return distance.magnitude > UInt64(Int.max) ? .max : Int(distance.magnitude)
	}

	private var fieldsSummary: String {
		(fields ?? []).map { "\($0.key): \($0.value.summary)" }.joined(separator: ", ")
	}

	private static func quoted(_ text: String) -> String {
		"\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
	}
}

extension Data {
	init(hexString: String) {
		var bytes: [UInt8] = []
		var index = hexString.startIndex
		while let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex), index < next {
			if let byte = UInt8(hexString[index ..< next], radix: 16) {
				bytes.append(byte)
			}
			index = next
		}
		self.init(bytes)
	}
}
