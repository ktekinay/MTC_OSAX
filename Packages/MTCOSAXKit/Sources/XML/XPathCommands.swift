import AppleEventCore
import CLibXML
import Foundation

/// The "XML XPath, XSLT" suite, except XSLT (`Transform.swift`).
extension XMLCommands {
	var xpath: [CommandDefinition] {
		[
			CommandDefinition("XMLXPath", code: "XML path", handler: xpath),
			CommandDefinition("XMLSetContext", code: "XML xpns", handler: setContext),
			CommandDefinition("XMLGetContext", code: "XML xpNS") { request in
				let document = try direct(request).0
				let namespaces = document.namespaces.map { prefix, uri in
					RecordFields([(.code("PREf"), NSAppleEventDescriptor(string: prefix)), (.code("PUri"), NSAppleEventDescriptor(string: uri))])
						.appleEventDescriptor
				}
				let variables = document.variables.map { [NSAppleEventDescriptor(string: $0.name), $0.value].appleEventDescriptor }
				return RecordFields([(.code("nsls"), namespaces.appleEventDescriptor), (.code("vars"), variables.appleEventDescriptor)])
			},
			CommandDefinition("XMLGetNodePath", code: "XML NoPa", handler: nodePath),
			CommandDefinition("XMLXPointer", code: "XML xptr", handler: xpointer),
			CommandDefinition("XMLEscapeXPointer", code: "XML ExXp") { request in
				let text = try request.requiredDirectParameter(as: String.self)
				return text.replacingOccurrences(of: "^", with: "^^").replacingOccurrences(of: "(", with: "^(")
					.replacingOccurrences(of: ")", with: "^)")
			},
			CommandDefinition("XMLGetXPointer", code: "XML gxpt", handler: getXPointer),
			CommandDefinition("XMLNewIndex", code: "XML NKey", handler: newIndex),
			CommandDefinition("XMLLookup", code: "XML GKey") { request in
				let key = try request.requiredDirectParameter(as: String.self)
				let (document, _) = try resolve(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
				guard let index = document.indexes[try request.requiredParameter("by  ", as: String.self)] else { throw XML.invalid }
				return (index.nodes[key] ?? []).compactMap { document.node(number: $0).map { reference($0, document) } }.appleEventDescriptor
			},
			CommandDefinition("XMLEntries", code: "XML LKey") { request in
				let (document, _) = try resolve(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
				guard let index = document.indexes[try request.requiredDirectParameter(as: String.self)] else { throw XML.invalid }
				let duplicates = try request.parameter("dupl", as: Bool.self)
				return index.order.keys.filter { key in duplicates.map { (index.nodes[key]?.count ?? 0 > 1) == $0 } ?? true }
			},
			CommandDefinition("XMLIndexDocument", code: "XML idoc") { request in
				_ = xmlXPathOrderDocElems(try direct(request).0.doc)
				return nil
			},
			CommandDefinition("XMLStrings", code: "XML DCon") { request in
				try each(request) { _, node in NSAppleEventDescriptor(string: XMLCommands.strings(node)) }
			},
			CommandDefinition("XMLLocalize", code: "XML LoCo", handler: localize),
		]
	}

	// MARK: XPath

	/// Adds the command's `namespace` and `xpath variables` to the document's context, as `XMLSetContext` does
	/// (SatimageOSAX kept them for later expressions too), and returns it.
	@discardableResult
	func context(_ document: XMLDocument, _ request: AppleEventRequest) throws -> (XPath.Namespaces, XPath.Variables) {
		let namespaces = XPath.merged(document.namespaces.map { ($0.prefix, $0.uri) }, try XPath.namespaces(request.descriptor(for: "nsls"))) { $0.isEmpty }
		let variables = XPath.merged(document.variables.map { ($0.name, $0.value) }, try XPath.variables(request.descriptor(for: "vars")),
		                             isRemoval: XMLCommands.isMissingValue)
		document.namespaces = namespaces.map { (prefix: $0.0, uri: $0.1) }
		document.variables = variables.map { (name: $0.0, value: $0.1) }
		return (document.namespaces, document.variables)
	}

	/// Evaluates `with` at each node (a list of nodes gives a list of results): node sets are lists of XMLRefs.
	func xpath(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (nodes, isList) = try directNodes(request)
		let expression = try request.requiredParameter("with", as: String.self)
		let results = try nodes.map { document, node in
			let (namespaces, variables) = try context(document, request)
			return try XPath.withContext(document.doc, node: node, namespaces: namespaces, variables: variables, references: references) { context in
				let object = try XPath.evaluate(expression, in: context)
				defer { xmlXPathFreeObject(object) }
				return XPath.result(object, references: references)
			}
		}
		return isList ? results.appleEventDescriptor : results[0]
	}

	/// Runs `body` with the node set `descriptor` defines, and the document of its first node (nil if it's empty):
	/// an XMLRef, a list of them (-1700 if empty), or an `XPathRef` record `{XMLRef:…, xpath pattern:…}` with an
	/// optional `namespace` and `xpath variables` (used only for this expression).
	func withNodeSet<T>(_ descriptor: NSAppleEventDescriptor, _ body: (XMLDocument?, xmlNodeSetPtr) throws -> T) throws -> T {
		if let fields = RecordFields(descriptor), let start = fields[.code("XMLR")] {
			let (document, node) = try resolve(start)
			let expression = try fields[.code("xpat")].map(XMLCommands.text) ?? "."
			let namespaces = XPath.merged(document.namespaces.map { ($0.prefix, $0.uri) }, try XPath.namespaces(fields[.code("nsls")])) { $0.isEmpty }
			let variables = XPath.merged(document.variables.map { ($0.name, $0.value) }, try XPath.variables(fields[.code("vars")]),
			                             isRemoval: XMLCommands.isMissingValue)
			return try XPath.withContext(document.doc, node: node, namespaces: namespaces.map { (prefix: $0.0, uri: $0.1) },
			                             variables: variables.map { (name: $0.0, value: $0.1) }, references: references) { context in
				let object = try XPath.evaluate(expression, in: context)
				defer { xmlXPathFreeObject(object) }
				guard object.pointee.type == XPATH_NODESET else { throw OSAXError.coercionFailed }
				// The object keeps any namespace nodes XPath made alive until the body is done.
				guard let set = object.pointee.nodesetval ?? xmlXPathNodeSetCreate(nil) else { throw XML.invalid }
				defer { if set != object.pointee.nodesetval { xmlXPathFreeNodeSet(set) } }
				let first = XPath.nodes(set).first { $0.pointee.type != XML_NAMESPACE_DECL }
				return try body(first.flatMap(XMLDocument.owner) ?? document, set)
			}
		}
		let items = XMLCommands.items(descriptor)
		guard !items.isEmpty else { throw OSAXError.coercionFailed }
		let nodes = try items.map(resolve)
		guard let set = xmlXPathNodeSetCreate(nil) else { throw XML.invalid }
		defer { xmlXPathFreeNodeSet(set) }
		for (_, node) in nodes {
			xmlXPathNodeSetAdd(set, node)
		}
		return try body(nodes[0].0, set)
	}

	/// Changes the document's context: a namespace with an empty URL, or a variable set to `missing value`, is
	/// removed (SatimageOSAX kept such namespaces).
	func setContext(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		try context(direct(request).0, request)
		return nil
	}

	/// `xpointer(/…)` for a node, or the path from `from` when it's an ancestor (SatimageOSAX only managed a
	/// parent, with a space before the path).
	func nodePath(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (_, node) = try direct(request)
		if let from = try request.descriptor(for: "from").map(resolve), from.1 != node,
		   let steps = XPath.steps(to: node, from: from.1)
		{
			return NSAppleEventDescriptor(string: steps.joined(separator: "/"))
		}
		return NSAppleEventDescriptor(string: XPath.pointer(node))
	}

	/// The document's URL, `#`, and the node's path; `suffix` is added as further steps (SatimageOSAX added it with
	/// no `/`). -50 for a document.
	func getXPointer(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (document, node) = try direct(request)
		guard !XMLCommands.isDocument(node) else { throw OSAXError.parameterError }
		var suffix = try request.parameter("suff", as: String.self) ?? ""
		if !suffix.isEmpty, !suffix.hasPrefix("/") {
			suffix = "/" + suffix
		}
		return NSAppleEventDescriptor(string: (document.url?.absoluteString ?? "") + "#" + XPath.pointer(node, suffix: suffix))
	}

	// MARK: XPointer

	/// Resolves `[URL]#pointer`: the URL (relative to `baseURL`, or to `from`) names a document open in the pool,
	/// or one it opens (unless `read permission` is false: error 11); without one, `from`'s document. The pointer
	/// is an ID, `xpointer(…)` (relative to `from` in its document, which SatimageOSAX couldn't do), or libxml2's
	/// other XPointer forms.
	func xpointer(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let link = try request.requiredDirectParameter(as: String.self)
		let from = try request.descriptor(for: "from").map(resolve)
		let hash = link.firstIndex(of: "#")
		let location = hash.map { String(link[..<$0]) } ?? link
		let fragment = hash.map { String(link[link.index(after: $0)...]) } ?? ""

		let document: XMLDocument
		if location.isEmpty {
			guard let from else { throw OSAXError.missingParameter }
			document = from.0
		} else {
			document = try linkedDocument(location, from: from, request: request)
		}
		guard let doc = document.doc, let root = document.node(number: 0) else { throw XML.noSuchNode }
		guard !fragment.isEmpty else {
			return [references.reference(document)].appleEventDescriptor
		}
		let namespaces = XPath.merged(document.namespaces.map { ($0.prefix, $0.uri) }, try XPath.namespaces(request.descriptor(for: "nsls"))) { _ in false }
			.map { (prefix: $0.0, uri: $0.1) }
		let origin = from.flatMap { $0.0 === document ? $0.1 : nil }

		// A relative XPath from an element: evaluated at the element.
		if let origin, !XMLCommands.isDocument(origin), fragment.hasPrefix("xpointer("), fragment.hasSuffix(")") {
			let expression = XMLCommands.unescapedXPointer(String(fragment.dropFirst(9).dropLast()))
			if !expression.hasPrefix("/") {
				return try XPath.withContext(doc, node: origin, namespaces: namespaces, variables: document.variables, references: references) { context in
					let object = try XPath.evaluate(expression, in: context)
					defer { xmlXPathFreeObject(object) }
					return XPath.result(object, references: references)
				}
			}
		}

		guard let context = xmlXPtrNewContext(doc, origin ?? root, origin ?? root) else { throw XML.invalid }
		defer { xmlXPathFreeContext(context) }
		try XPath.prepare(context, namespaces: namespaces, variables: document.variables, references: references)
		let (object, issues) = XMLIssues.collect { withXMLString(fragment) { xmlXPtrEval($0, context) } }
		guard let object else {
			if let issue = issues.first { throw OSAXError(issue.code) }
			return [NSAppleEventDescriptor]().appleEventDescriptor
		}
		defer { xmlXPathFreeObject(object) }
		return XMLCommands.locations(object).map { references.referenceOrText($0) }.appleEventDescriptor
	}

	/// XPointer's escapes: `^(`, `^)` and `^^`.
	static func unescapedXPointer(_ text: String) -> String {
		var result = ""
		var escaped = false
		for character in text {
			if !escaped, character == "^" {
				escaped = true
				continue
			}
			escaped = false
			result.append(character)
		}
		return result
	}

	/// The nodes of an XPointer result: a node set, or a location set's points and ranges (their start nodes).
	static func locations(_ object: xmlXPathObjectPtr) -> [xmlNodePtr] {
		switch object.pointee.type {
		case XPATH_NODESET:
			return XPath.nodes(object.pointee.nodesetval)
		case XPATH_LOCATIONSET:
			guard let set = object.pointee.user?.assumingMemoryBound(to: xmlLocationSet.self), let table = set.pointee.locTab else { return [] }
			return (0 ..< Int(set.pointee.locNr)).flatMap { index -> [xmlNodePtr] in
				guard let location = table[index] else { return [] }
				return locations(location)
			}
		case XPATH_POINT, XPATH_RANGE:
			return object.pointee.user.map { [$0.assumingMemoryBound(to: xmlNode.self)] } ?? []
		default:
			return []
		}
	}

	/// The document a link's URL names: one open in the pool (`in pool`, `from`'s, or the current one), or opened.
	func linkedDocument(_ location: String, from: (XMLDocument, xmlNodePtr)?, request: AppleEventRequest) throws -> XMLDocument {
		var base = try request.parameter("burl", as: String.self)
		if base == nil, let from {
			base = Parsing.string(xmlNodeGetBase(from.0.doc, from.1)) ?? from.0.url?.absoluteString
		}
		let absolute = base.flatMap { base in
			withXMLString(location) { l in withXMLString(base) { Parsing.string(xmlBuildURI(l, $0)) } }
		} ?? location
		guard let url = URL(string: absolute) ?? URL(string: absolute.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else {
			throw XML.invalid
		}
		let pool = try request.parameter("pool", as: String.self) ?? from?.0.pool ?? store.currentPool
		if let open = references.documents.first(where: { $0.pool == pool && $0.url.map { XMLCommands.sameLocation($0, url) } == true }) {
			return open
		}
		guard try request.parameter("CnOp", default: true) else { throw OSAXError(11) }
		var options = ParseOptions()
		options.keepBlanks = try request.parameter("kbln", default: false)
		options.substituteEntities = try request.parameter("SuEn", default: false)
		options.validate = try request.parameter("Vali", default: false)
		options.failureLevel = try request.parameter("ErLe", default: settings.errorLevel)
		options.extendedCharacters = settings.extendedCharacters
		let data: Data
		if url.isFileURL {
			guard let contents = try? Data(contentsOf: url) else { throw OSAXError(1549) }
			data = contents
		} else {
			data = try Network.fetch(url, post: false, query: nil, headers: nil)
		}
		let doc = try Parsing.parse(data, url: url.absoluteString, options: options)
		let document = store.add(pool: pool) { XMLDocument(number: $0, pool: $1, doc: doc) }
		document.url = url
		return document
	}

	static func sameLocation(_ a: URL, _ b: URL) -> Bool {
		if a.isFileURL, b.isFileURL {
			return a.standardizedFileURL.path == b.standardizedFileURL.path
		}
		return a.absoluteString == b.absoluteString
	}

	// MARK: Indexes

	/// Indexes the nodes `match` selects by the string value of `use` at each; an empty `match` removes the index.
	/// Error 3 if nothing matches.
	func newIndex(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let name = try request.requiredDirectParameter(as: String.self)
		let match = try request.requiredParameter("matc", as: String.self)
		let use = try request.requiredParameter("use ", as: String.self)
		let (document, node) = try resolve(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
		guard !match.isEmpty else {
			document.indexes[name] = nil
			return nil
		}
		let (namespaces, variables) = try context(document, request)
		let index = XMLIndex()
		try XPath.withContext(document.doc, node: node, namespaces: namespaces, variables: variables, references: references) { context in
			let matched = try XPath.evaluate(match, in: context)
			defer { xmlXPathFreeObject(matched) }
			for item in XPath.nodes(matched.pointee.nodesetval) where item.pointee.type != XML_NAMESPACE_DECL {
				context.pointee.node = item
				let key = try XPath.evaluate(use, in: context)
				defer { xmlXPathFreeObject(key) }
				index.add(XPath.string(key), document.number(of: item))
			}
		}
		guard !index.nodes.isEmpty else { throw XPath.failed }
		document.indexes[name] = index
		return nil
	}

	// MARK: Localizing

	/// Text with a node's markup as numbered placeholders: each start tag, end tag or empty element is `%n$s`. A
	/// text node is its text.
	static func strings(_ node: xmlNodePtr) -> String {
		guard [XML_ELEMENT_NODE, XML_DOCUMENT_NODE, XML_HTML_DOCUMENT_NODE].contains(node.pointee.type) else {
			return Parsing.text(node)
		}
		var result = ""
		var number = 0
		func placeholder() {
			number += 1
			result += "%\(number)$s"
		}
		func add(_ parent: xmlNodePtr) {
			var current = parent.pointee.children
			while let child = current {
				switch child.pointee.type {
				case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
					result += Parsing.text(child)
				case XML_ELEMENT_NODE:
					placeholder()
					if child.pointee.children != nil {
						add(child)
						placeholder()
					}
				default:
					break
				}
				current = child.pointee.next
			}
		}
		add(node)
		return result
	}

	/// Replaces text nodes' text with their translations in a `.strings` file; other nodes are left as they are
	/// (as in SatimageOSAX).
	func localize(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let file = try request.requiredParameter("in  ", as: URL.self)
		guard let table = NSDictionary(contentsOf: file) as? [String: Any] else { throw OSAXError(-43) }
		for (document, node) in try directNodes(request).nodes
			where node.pointee.type == XML_TEXT_NODE || node.pointee.type == XML_CDATA_SECTION_NODE
		{
			guard let translation = table[Parsing.text(node)] as? String else { continue }
			withXMLString(translation) { xmlNodeSetContent(node, $0) }
			modified(document)
		}
		return nil
	}
}

/// An `XMLNewIndex` index: keys to the numbers of their nodes, in document order.
final class XMLIndex {
	var nodes: [String: [Int]] = [:]
	var order = HashOrder()

	func add(_ key: String, _ node: Int) {
		order.insert(key)
		nodes[key, default: []].append(node)
	}
}

/// The order a libxml2 2.9 hash table (without its random seed) lists keys in, which SatimageOSAX's `XMLEntries`
/// shows: 256 buckets to start with, each listing its keys in the order they came, growing eightfold when a bucket
/// gets more than 9.
struct HashOrder {
	private var buckets: [[String]] = Array(repeating: [], count: 256)

	var keys: [String] {
		buckets.flatMap { $0 }
	}

	mutating func insert(_ key: String) {
		let bucket = Self.bucket(key, size: buckets.count)
		guard !buckets[bucket].contains(key) else { return }
		let length = max(buckets[bucket].count - 1, 0)
		buckets[bucket].append(key)
		if length > 8 {
			grow()
		}
	}

	/// The first key of each old bucket goes first; then the rest, each at the front of its new bucket's others.
	private mutating func grow() {
		var grown: [[String]] = Array(repeating: [], count: buckets.count * 8)
		for bucket in buckets {
			if let first = bucket.first {
				grown[Self.bucket(first, size: grown.count)].append(first)
			}
		}
		for bucket in buckets {
			for key in bucket.dropFirst() {
				let index = Self.bucket(key, size: grown.count)
				if grown[index].isEmpty {
					grown[index].append(key)
				} else {
					grown[index].insert(key, at: 1)
				}
			}
		}
		buckets = grown
	}

	/// libxml2's `xmlHashComputeKey` for one name.
	static func bucket(_ key: String, size: Int) -> Int {
		var value: UInt64 = 0
		let bytes = Array(key.utf8)
		if let first = bytes.first {
			value &+= 30 &* UInt64(first)
		}
		for byte in bytes {
			value ^= (value << 5) &+ (value >> 3) &+ UInt64(byte)
		}
		value ^= (value << 5) &+ (value >> 3)
		value ^= (value << 5) &+ (value >> 3)
		return Int(value % UInt64(size))
	}
}
