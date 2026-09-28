import AppleEventCore
import Foundation

/// Satimage's "PropertyList Additions" (event class `PLST`) and "Pool Additions" (`POOL`) suites.
/// Behavior recorded from SatimageOSAX in `Fixtures/PropertyLists`; where Satimage was broken, MTC_OSAX follows the
/// dictionary (`Fixtures/PropertyListsFixes`, listed in Implemented/PLAN-PropertyLists.md).
///
/// Scripts work on property lists through CFRefs: references to a document or to an element in one, valid until
/// the element is removed or the document closed (then error -1728).
public enum PropertyLists {
	// Error numbers recorded from SatimageOSAX.
	static let invalid = OSAXError(-1)
	static let noSuchElement = OSAXError(-1728) // errAENoSuchObject
	static let notFound = OSAXError(-2763)
	static let wrongType = OSAXError(-10001) // errAETypeError

	/// - Parameter store: the open documents; the app passes its own, to know when documents are open.
	public static func commands(store: DocumentStore = DocumentStore()) -> [CommandDefinition] {
		let commands = Commands(store: store)
		return [
			CommandDefinition("PlistNew", code: "PLSTmake", handler: commands.new),
			CommandDefinition("PlistOpen", code: "PLSTopen", handler: commands.open),
			CommandDefinition("PlistClose", code: "PLSTclos", handler: commands.close),
			CommandDefinition("PlistRetain", code: "PLSTReta") { request in
				try commands.node(request).document.retainCount += 1
				return nil
			},
			CommandDefinition("PlistSave", code: "PLSTsave", handler: commands.save),
			CommandDefinition("PlistBinaryFormat", code: "PLSTIsBi") { try commands.node($0).document.isBinary },
			CommandDefinition("PlistCount", code: "PLSTcunt", handler: commands.count),
			CommandDefinition("PlistChild", code: "PLSTchld", handler: commands.child),
			CommandDefinition("PlistType", code: "PLSTdisp") { try commands.node($0).typeName },
			CommandDefinition("PlistGet", code: "PLSTdisx", handler: commands.get),
			CommandDefinition("PlistGetXML", code: "PLSTDISP") { request in
				String(decoding: try serialized(commands.node(request)), as: UTF8.self)
			},
			CommandDefinition("PlistGetKeys", code: "PLSTgkey") { request in
				let node = try commands.node(request)
				guard case .dictionary = node.content else {
					throw wrongType
				}
				return node.keys.sorted()
			},
			CommandDefinition("PlistSet", code: "PLSTseta", handler: commands.set),
			CommandDefinition("PlistNewChild", code: "PLSTaddc", handler: commands.newChild),
			CommandDefinition("PlistRemoveChild", code: "PLSTremc", handler: commands.removeChild),
			CommandDefinition("PlistEqual", code: "PLSTequa") { request in
				let other = try commands.store.node(request.requiredParameter("to  ", as: AnyDescriptor.self).descriptor)
				return (object(of: try commands.node(request)) as AnyObject).isEqual(object(of: other))
			},
			CommandDefinition("PlistExist", code: "PLSTcont", handler: commands.exist),
			CommandDefinition("PlistMatch", code: "PLSTmatc", handler: commands.match),
			CommandDefinition("PlistURL", code: "PLSTgurl", handler: commands.url),
			CommandDefinition("PlistDocument", code: "PLSTgfur", handler: commands.document),
			CommandDefinition("PlistListDocuments", code: "PLSTList") { request in
				let pool = try request.directParameter(as: String.self) ?? commands.store.currentPool
				return commands.store.documents.filter { $0.pool == pool }.map { commands.store.reference($0.root) }
			},
			CommandDefinition("PlistAdd", code: "PLSTconc", handler: commands.add),
			CommandDefinition("PlistToJSON", code: "PLSTJSON", handler: commands.toJSON),
			CommandDefinition("PlistToJavaScript", code: "PLSTToJa") { request in
				JSON.javaScript(object(of: try commands.node(request)))
			},
			CommandDefinition("PlistFromJSON", code: "PLSTNOSJ") { try commands.newDocument($0) { text, _ in try JSON.parse(text) } },
			// MTC_OSAX extensions: YAML and TOML, in their own suite (event class MTCp).
			CommandDefinition("PlistToYAML", code: "MTCpTYML") { try commands.output(YAML.write(object(of: commands.node($0))), $0) },
			CommandDefinition("PlistFromYAML", code: "MTCpFYML") { try commands.newDocument($0, from: YAML.read) },
			CommandDefinition("PlistToTOML", code: "MTCpTTML") { try commands.output(TOML.write(object(of: commands.node($0))), $0) },
			CommandDefinition("PlistFromTOML", code: "MTCpFTML") { try commands.newDocument($0, from: TOML.read) },
			CommandDefinition("PlistSetDocID", code: "PLSTSDbK") { request in
				let document = try commands.node(request).document
				let previous = document.identifier
				document.identifier = try request.requiredParameter("to  ", as: String.self)
				return previous
			},
			CommandDefinition("PlistGetDocByID", code: "PLSTGDbK") { request in
				let identifier = try request.requiredDirectParameter(as: String.self)
				let pool = try request.parameter("pool", as: String.self) ?? commands.store.currentPool
				guard let document = commands.store.documents.first(where: { $0.identifier == identifier && $0.pool == pool }) else {
					throw notFound
				}
				return commands.store.reference(document.root)
			},
			CommandDefinition("PlistGetID", code: "PLSTgID ") { try commands.node($0).document.number },
			CommandDefinition("PlistFromID", code: "PLSTgfID") { request in
				guard let document = commands.store.document(number: try request.requiredDirectParameter(as: Int.self)) else {
					throw notFound
				}
				return commands.store.reference(document.root)
			},
			CommandDefinition("SetPool", code: "POOLpool") { request in
				let previous = commands.store.currentPool
				commands.store.currentPool = try request.requiredDirectParameter(as: String.self)
				return previous
			},
			// Releases each document once, as PlistClose does, so one kept with PlistRetain stays open until its last
			// close, as in SatimageOSAX (MTC_OSAX closed it regardless).
			CommandDefinition("DeletePool", code: "POOLdpoo") { request in
				let pool = try request.directParameter(as: String.self) ?? commands.store.currentPool
				for document in commands.store.allDocuments where document.pool == pool {
					if let plist = document as? Document {
						plist.retainCount -= 1
						guard plist.retainCount <= 0 else { continue }
					}
					commands.store.close(document)
				}
				return nil
			},
			CommandDefinition("GetPool", code: "POOLgpoo") { request in
				try commands.store.storedDocument(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor).pool
			},
		]
	}
}

extension PropertyLists {
	/// Opens a property list from its data (XML, binary, or the old OpenStep text, which PropertyListSerialization
	/// also reads) in `pool`: its CFRef. -1 if it isn't one.
	public static func open(_ data: Data, pool: String?, store: DocumentStore) throws -> NSAppleEventDescriptor {
		store.reference(try document(data, pool: pool, store: store).root)
	}

	static func document(_ data: Data, pool: String?, store: DocumentStore) throws -> Document {
		var format = PropertyListSerialization.PropertyListFormat.xml
		guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) else {
			throw invalid
		}
		try checkDepth(object)
		let document = store.newDocument(pool: pool)
		document.isBinary = format == .binary
		document.root = node(from: object, in: document)
		return document
	}

	/// Adds keys to the dictionary a CFRef refers to (replacing ones it has), for `filter text … into`: -1 unless it's
	/// a dictionary.
	public static func add(_ entries: [(key: String, value: Any)], to reference: NSAppleEventDescriptor, store: DocumentStore) throws {
		let target = try store.node(reference)
		guard case .dictionary = target.content else {
			throw invalid
		}
		for (key, value) in entries {
			target.setChild(node(from: value, in: target.document), forKey: key)
		}
	}
}

/// The handlers, sharing the document store.
struct Commands {
	let store: DocumentStore

	/// The direct parameter's element.
	func node(_ request: AppleEventRequest) throws -> Node {
		try store.node(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
	}

	/// The direct parameter's elements: one, or a list of them (`PlistCount`, `PlistGet`).
	func nodes(_ request: AppleEventRequest) throws -> (nodes: [Node], isList: Bool) {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		if descriptor.descriptorType == typeAEList {
			return (try (0 ..< descriptor.numberOfItems).map { try store.node(descriptor.atIndex($0 + 1)!) }, true)
		}
		return ([try store.node(descriptor)], false)
	}

	// MARK: Documents

	/// `without typed` stores each value inside as its raw bytes, as `PlistSet` does (SatimageOSAX ignored it here).
	func new(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let typed = try request.parameter("flat", default: true)
		let document = store.newDocument(pool: try request.parameter("pool", as: String.self))
		let value = request.descriptor(for: Keyword.directObject) ?? RecordFields().appleEventDescriptor
		do {
			document.root = try PropertyLists.node(from: value, in: document, store: store, typed: typed)
		} catch {
			store.close(document)
			throw error
		}
		return store.reference(document.root)
	}

	/// A file (-43 if missing), or XML `from string`; -1 if it isn't a property list.
	func open(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let pool = try request.parameter("pool", as: String.self)
		let data: Data
		var url: URL?
		if let text = try request.parameter("from", as: String.self) {
			data = Data(text.utf8)
		} else {
			let file = try request.requiredDirectParameter(as: URL.self)
			guard let contents = try? Data(contentsOf: file) else {
				throw OSAXError(-43)
			}
			data = contents
			url = file
		}
		let document = try PropertyLists.document(data, pool: pool, store: store)
		document.url = url
		return store.reference(document.root)
	}

	/// Closes the document of any of its elements (after as many closes as `PlistRetain`s).
	func close(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let document = try node(request).document
		document.retainCount -= 1
		if document.retainCount <= 0 {
			store.close(document)
		}
		return nil
	}

	/// Saves the whole document (whichever element is given) to `in` (a file, or a path, which SatimageOSAX refused),
	/// or to the file it came from or was last saved to (-1701 if none), in its format unless `binary` is given.
	/// A missing folder is -1.
	func save(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let document = try node(request).document
		let binary = try request.parameter("bina", default: document.isBinary)
		guard let url = try request.parameter("kfil", as: URL.self) ?? document.url else {
			throw OSAXError.missingParameter
		}
		do {
			try PropertyLists.serialized(document.root, binary: binary).writeReplacing(url)
		} catch {
			throw PropertyLists.invalid
		}
		document.url = url
		document.isBinary = binary
		return nil
	}

	/// The document's file: a POSIX path, or `as` text (a file URL) or alias; `parent` for its folder. -2763 for a
	/// document that has no file.
	func url(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		guard var url = try node(request).document.url else {
			throw PropertyLists.notFound
		}
		let parent = try request.parameter("pare", default: false)
		if parent {
			url = url.deletingLastPathComponent()
		}
		switch request.descriptor(for: "rtyp")?.typeCodeValue.fourCharString {
		case "alis":
			guard let alias = NSAppleEventDescriptor.alias(url) else {
				throw OSAXError(-43)
			}
			return alias
		case "utxt", "TEXT", "ctxt":
			return NSAppleEventDescriptor(string: URL(fileURLWithPath: url.path, isDirectory: parent).absoluteString)
		default:
			return NSAppleEventDescriptor(string: url.path + (parent ? "/" : ""))
		}
	}

	/// The open document for a file, in `in pool` (default: the current pool); -2763 if none.
	func document(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let url = try request.requiredDirectParameter(as: URL.self).standardizedFileURL
		let pool = try request.parameter("pool", as: String.self) ?? store.currentPool
		guard let document = store.documents.first(where: { $0.pool == pool && $0.url?.standardizedFileURL.path == url.path }) else {
			throw PropertyLists.notFound
		}
		return store.reference(document.root)
	}

	// MARK: Reading

	func count(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (nodes, isList) = try nodes(request)
		let counts = try nodes.map { node -> Int in
			switch node.content {
			case let .dictionary(dictionary): return dictionary.count
			case let .array(items): return items.count
			default: throw PropertyLists.invalid
			}
		}
		return isList ? counts.appleEventDescriptor : counts[0].appleEventDescriptor
	}

	/// The selected children of the direct parameter: one, a list for a list of keys, or all without a selector.
	/// `missingKey` is the error for a key that isn't there.
	func selected(_ node: Node, _ selector: Selector, missingKey: OSAXError) throws -> (nodes: [Node?], isList: Bool) {
		switch selector {
		case .none:
			return (node.children, true)
		case let .index(index):
			if case .array = node.content {
				return ([try PropertyLists.child(of: node, .index(index), missingKey: missingKey)], false)
			}
			if case .dictionary = node.content {
				throw PropertyLists.invalid
			}
			throw OSAXError.parameterError
		case let .key(key):
			return ([try PropertyLists.child(of: node, .key(key), missingKey: missingKey)], false)
		case let .keys(keys):
			guard case .dictionary = node.content else {
				throw PropertyLists.invalid
			}
			return (keys.map { node.child(forKey: $0) }, true)
		case let .path(steps):
			let parent = try PropertyLists.follow(Array(steps.dropLast()), from: node, missingKey: PropertyLists.invalid)
			return ([try PropertyLists.child(of: parent, steps.last!, missingKey: PropertyLists.notFound)], false)
		}
	}

	func child(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (children, isList) = try selected(node(request), Selector(request), missingKey: PropertyLists.noSuchElement)
		let references = try children.map { child -> NSAppleEventDescriptor in
			guard let child else { throw PropertyLists.noSuchElement }
			return store.reference(child)
		}
		return isList ? references.appleEventDescriptor : references[0]
	}

	func get(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let type = request.descriptor(for: "rtyp").map { $0.typeCodeValue }
		let selector = try Selector(request)
		let (nodes, isDirectList) = try nodes(request)
		if isDirectList {
			return nodes.map { PropertyLists.descriptor(of: $0, as: type) }.appleEventDescriptor
		}
		if case .none = selector {
			return PropertyLists.descriptor(of: nodes[0], as: type)
		}
		let (children, isList) = try selected(nodes[0], selector, missingKey: PropertyLists.noSuchElement)
		let values = children.map { $0.map { PropertyLists.descriptor(of: $0, as: type) } ?? .missingValue }
		return isList ? values.appleEventDescriptor : values[0]
	}

	// MARK: Changing

	/// Where a change goes: a container and the key or index in it, from `index`, `key` or a `using` path (whose
	/// last step is the key or index; the ones before must exist, else -1).
	func target(_ container: Node, _ selector: Selector) throws -> [(Node, Selector.Step)] {
		switch selector {
		case .none:
			throw PropertyLists.invalid
		case let .index(index):
			return [(container, .index(index))]
		case let .key(key):
			return [(container, .key(key))]
		case let .keys(keys):
			return keys.map { (container, .key($0)) }
		case let .path(steps):
			let parent = try PropertyLists.follow(Array(steps.dropLast()), from: container, missingKey: PropertyLists.invalid)
			return [(parent, steps.last!)]
		}
	}

	/// Sets a key (creating it) or an index (1 to count + 1); with a list of keys, each to the matching item of `to`,
	/// where `missing value` removes the key unless `suppressing` is false (then it's stored, which SatimageOSAX
	/// didn't do).
	func set(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let container = try node(request)
		let value = try request.requiredParameter("to  ", as: AnyDescriptor.self).descriptor
		let suppressing = try request.parameter("Supp", default: true)
		let typed = try request.parameter("flat", default: true)
		let selector = try Selector(request)
		let targets = try target(container, selector)
		var values = [value]
		if case .keys = selector {
			guard value.descriptorType == typeAEList, value.numberOfItems == targets.count else {
				throw PropertyLists.invalid
			}
			values = (0 ..< value.numberOfItems).map { value.atIndex($0 + 1)! }
		}
		for ((parent, step), value) in zip(targets, values) {
			if case .keys = selector, suppressing, value.descriptorType == typeType, value.typeCodeValue.fourCharString == "msng" {
				if case let .key(key) = step, case .dictionary = parent.content {
					parent.removeChild(forKey: key)
				}
				continue
			}
			try place(PropertyLists.node(from: value, in: container.document, store: store, typed: typed), in: parent, at: step, inserting: false)
		}
		return nil
	}

	/// Puts `child` at a key of a dictionary, or at an index of an array: replacing (`PlistSet`, up to count + 1)
	/// or inserting (`PlistNewChild`); -1 otherwise.
	func place(_ child: Node, in parent: Node, at step: Selector.Step, inserting: Bool) throws {
		switch (step, parent.content) {
		case let (.key(key), .dictionary):
			parent.setChild(child, forKey: key)
		case let (.index(index), .array(items)):
			guard (1 ... items.count + 1).contains(index) else {
				throw PropertyLists.invalid
			}
			if inserting || index == items.count + 1 {
				parent.insert(child, at: index - 1)
			} else {
				parent.replace(at: index - 1, with: child)
			}
		default:
			throw PropertyLists.invalid
		}
	}

	/// A new child `at` a container: at a key (required for a dictionary; an existing one is replaced), or at an
	/// index of an array (default: the end). Its value is the direct parameter, or an empty record.
	func newChild(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let container = try store.node(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
		let typed = try request.parameter("flat", default: true)
		let value = request.descriptor(for: Keyword.directObject) ?? RecordFields().appleEventDescriptor
		let selector = try Selector(request)
		let (parent, step): (Node, Selector.Step)
		if case .none = selector, case let .array(items) = container.content {
			(parent, step) = (container, .index(items.count + 1))
		} else {
			(parent, step) = try target(container, selector)[0]
		}
		let child = try PropertyLists.node(from: value, in: container.document, store: store, typed: typed)
		try place(child, in: parent, at: step, inserting: true)
		return store.reference(child)
	}

	/// Removes a key or an index; one that isn't there is ignored, as in SatimageOSAX. References to the removed
	/// element (and anything in it) then give -1728 (SatimageOSAX returned nothing).
	func removeChild(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		for (parent, step) in try target(node(request), Selector(request)) {
			switch (step, parent.content) {
			case let (.key(key), .dictionary):
				parent.removeChild(forKey: key)
			case let (.index(index), .array(items)):
				if items.indices.contains(index - 1) {
					parent.remove(at: index - 1)
				}
			default:
				throw PropertyLists.invalid
			}
		}
		return nil
	}

	/// Concatenates arrays, or merges dictionaries (`after`: the target keeps its values; `before`: the direct
	/// parameter's win), like AppleScript's `&`. The direct parameter may be a CFRef, a list or a record.
	func add(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let after = request.descriptor(for: "afte")
		guard let targetDescriptor = after ?? request.descriptor(for: "befo") else {
			throw OSAXError.missingParameter
		}
		let target = try store.node(targetDescriptor)
		let source = try PropertyLists.node(from: request.requiredDirectParameter(as: AnyDescriptor.self).descriptor, in: target.document, store: store)
		switch (target.content, source.content) {
		case let (.array(items), .array(added)):
			for (offset, child) in added.enumerated() {
				target.insert(child, at: after != nil ? items.count + offset : offset)
			}
		case (.dictionary, .dictionary):
			for key in source.keys {
				if let child = source.child(forKey: key), after == nil || target.child(forKey: key) == nil {
					target.setChild(child, forKey: key)
				}
			}
		default:
			throw OSAXError.coercionFailed
		}
		return nil
	}

	// MARK: Queries

	/// The indices (in an array) or keys (in a dictionary) holding a value, or any of a list of values with
	/// `several values`. Values compare as property lists do (1 equals 1.0; text is case-sensitive).
	func exist(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let container = try store.node(request.requiredParameter("in  ", as: AnyDescriptor.self).descriptor)
		let value = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let several = try request.parameter("List", default: false)
		let scratch = Document(number: 0, pool: "")
		let wanted = try (several && value.descriptorType == typeAEList ? (0 ..< value.numberOfItems).map { value.atIndex($0 + 1)! } : [value])
			.map { PropertyLists.object(of: try PropertyLists.node(from: $0, in: scratch, store: store)) as AnyObject }
		let matches = { (node: Node) in wanted.contains { $0.isEqual(PropertyLists.object(of: node)) } }
		switch container.content {
		case let .array(items):
			return items.indices.filter { matches(items[$0]) }.map { $0 + 1 }.appleEventDescriptor
		case .dictionary:
			return container.keys.filter { container.child(forKey: $0).map(matches) ?? false }.appleEventDescriptor
		default:
			return [Int]().appleEventDescriptor
		}
	}

	/// The dictionaries in an array that have a key (or `using` path), with `value` if given.
	func match(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let array = try node(request)
		let steps: [Selector.Step] = if let path = try request.parameter("by  ", as: String.self) {
			try Selector.steps(path)
		} else {
			[.key(try request.requiredParameter("key ", as: String.self))]
		}
		let scratch = Document(number: 0, pool: "")
		let wanted = try request.descriptor(for: "to  ").map { PropertyLists.object(of: try PropertyLists.node(from: $0, in: scratch, store: store)) as AnyObject }
		guard case let .array(items) = array.content else {
			return [NSAppleEventDescriptor]().appleEventDescriptor
		}
		return items.filter { item in
			guard case .dictionary = item.content, let found = try? PropertyLists.follow(steps, from: item, missingKey: PropertyLists.notFound) else {
				return false
			}
			return wanted.map { $0.isEqual(PropertyLists.object(of: found)) } ?? true
		}.map { store.reference($0) }.appleEventDescriptor
	}

	// MARK: JSON

	/// The JSON text, or with `in` (an MTC_OSAX extension), written to that file.
	func toJSON(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let node = try node(request)
		return try output(JSON.stringify(
			PropertyLists.object(of: node),
			formatted: request.parameter("smar", default: false),
			replacer: request.parameter("rplc", as: String.self)
		), request)
	}

	// MARK: Files (MTC_OSAX extension)

	/// The text a `PlistTo…` command made: returned, or with `in` (a file or POSIX path) written there in UTF-8,
	/// returning nothing. A folder that doesn't exist is -1, as for `PlistSave`.
	func output(_ text: String, _ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		guard let file = try request.parameter("kfil", as: URL.self) else {
			return NSAppleEventDescriptor(string: text)
		}
		do {
			try Data(text.utf8).writeReplacing(file)
		} catch {
			throw PropertyLists.invalid
		}
		return nil
	}

	/// The direct parameter of a `PlistFrom…` command: a file reference is read (UTF-8; -43 if it's missing, -1 if
	/// it isn't UTF-8); text is the document itself, never a path, as in Satimage's `PlistFromJSON`.
	func input(_ request: AppleEventRequest) throws -> String {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard ["alis", "furl", "fsrf", "bmrk", "fss "].contains(descriptor.descriptorType.fourCharString) else {
			return try String(appleEventDescriptor: descriptor)
		}
		guard let data = try? Data(contentsOf: URL(appleEventDescriptor: descriptor)) else {
			throw OSAXError(-43)
		}
		guard let text = String(data: data, encoding: .utf8) else {
			throw PropertyLists.invalid
		}
		return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
	}

	/// A new document from text in another format (`PlistFromJSON`, `PlistFromYAML`, `PlistFromTOML`), `in pool`.
	func newDocument(_ request: AppleEventRequest, from read: (String, TimeZone) throws -> Any) throws -> NSAppleEventDescriptor {
		let object = try read(input(request), .current)
		try PropertyLists.checkDepth(object)
		let document = store.newDocument(pool: try request.parameter("pool", as: String.self))
		document.root = PropertyLists.node(from: object, in: document)
		return store.reference(document.root)
	}
}
