import AppleEventCore
import CLibXML
import CommonCrypto
import Foundation

/// XPath for `XMLXPath`, `XMLNewIndex` and `XMLXPointer`: contexts with a document's namespaces and variables
/// (`XMLSetContext`) and SatimageOSAX's extension functions; results as Apple event values.
enum XPath {
	typealias Namespaces = [(prefix: String, uri: String)]
	typealias Variables = [(name: String, value: NSAppleEventDescriptor)]

	/// SatimageOSAX's error for an expression that fails when evaluated (an undeclared prefix, an unknown function
	/// or variable), a stylesheet that doesn't compile, or an empty index.
	static let failed = OSAXError(3)

	// MARK: Parameters

	/// `namespace`: a `{nsprefix:…, nsurl:…}` record or a list of them.
	static func namespaces(_ descriptor: NSAppleEventDescriptor?) throws -> Namespaces {
		guard let descriptor else { return [] }
		return try XMLCommands.items(descriptor).map { item in
			guard let fields = RecordFields(item) else { throw OSAXError.coercionFailed }
			let prefix = try fields[.code("PREf")].map(XMLCommands.text) ?? ""
			let uri = try fields[.code("PUri")].map(XMLCommands.text) ?? ""
			return (prefix, uri)
		}
	}

	/// `xpath variables`: an even list `{name, value, …}` (-1700 if odd) or a record `{name:value, …}`.
	static func variables(_ descriptor: NSAppleEventDescriptor?) throws -> Variables {
		guard let descriptor else { return [] }
		if let fields = RecordFields(descriptor) {
			return fields.fields.map { key, value in
				switch key {
				case let .user(name): (name, value)
				case let .code(code): (code, value)
				}
			}
		}
		let items = XMLCommands.items(descriptor)
		guard items.count % 2 == 0 else { throw OSAXError.coercionFailed }
		return try stride(from: 0, to: items.count, by: 2).map { (try XMLCommands.text(items[$0]), items[$0 + 1]) }
	}

	/// `pairs` with `changes` applied: a changed name keeps its place, a new one goes at the end, and a removed one
	/// (`isRemoval`) goes.
	static func merged<Value>(_ pairs: [(String, Value)], _ changes: [(String, Value)], isRemoval: (Value) -> Bool) -> [(String, Value)] {
		var result = pairs
		for (name, value) in changes {
			let index = result.firstIndex { $0.0 == name }
			if isRemoval(value) {
				if let index { result.remove(at: index) }
			} else if let index {
				result[index] = (name, value)
			} else {
				result.append((name, value))
			}
		}
		return result
	}

	// MARK: Evaluating

	/// Runs `body` with an XPath context at `node`, with `namespaces` and `variables` (a document's context with a
	/// command's parameters applied) and the extension functions.
	static func withContext<T>(_ doc: xmlDocPtr?, node: xmlNodePtr, namespaces: Namespaces, variables: Variables,
	                           references: XMLReferences, _ body: (xmlXPathContextPtr) throws -> T) throws -> T
	{
		guard let context = xmlXPathNewContext(doc) else { throw XML.invalid }
		defer { xmlXPathFreeContext(context) }
		context.pointee.node = node
		try prepare(context, namespaces: namespaces, variables: variables, references: references)
		return try body(context)
	}

	static func prepare(_ context: xmlXPathContextPtr, namespaces: Namespaces, variables: Variables, references: XMLReferences) throws {
		Functions.register(context)
		for (prefix, uri) in namespaces where !prefix.isEmpty && !uri.isEmpty {
			withXMLString(prefix) { p in withXMLString(uri) { _ = xmlXPathRegisterNs(context, p, $0) } }
		}
		for (name, value) in variables {
			let object = try self.object(value, references: references)
			withXMLString(name) { _ = xmlXPathRegisterVariable(context, $0, object) }
		}
	}

	/// Compiles and evaluates an expression: a syntax error is libxml2's error number (1207), any other failure 3.
	static func evaluate(_ expression: String, in context: xmlXPathContextPtr) throws -> xmlXPathObjectPtr {
		let (compiled, issues) = XMLIssues.collect { withXMLString(expression) { xmlXPathCtxtCompile(context, $0) } }
		guard let compiled else { throw OSAXError(issues.first?.code ?? 1207) }
		defer { xmlXPathFreeCompExpr(compiled) }
		let (result, _) = XMLIssues.collect { xmlXPathCompiledEval(compiled, context) }
		guard let result else { throw failed }
		return result
	}

	/// An Apple event value as an XPath value: XMLRefs as node sets, numbers, booleans, and anything else as text.
	static func object(_ descriptor: NSAppleEventDescriptor, references: XMLReferences) throws -> xmlXPathObjectPtr? {
		let items = XMLCommands.items(descriptor)
		if !items.isEmpty, items.allSatisfy(XMLReferences.isReference) {
			let set = xmlXPathNodeSetCreate(nil)
			for item in items {
				xmlXPathNodeSetAdd(set, try references.resolve(item).1)
			}
			return xmlXPathWrapNodeSet(set)
		}
		switch descriptor.descriptorType.fourCharString {
		case "bool", "true", "fals":
			return xmlXPathNewBoolean(descriptor.booleanValue ? 1 : 0)
		case "long", "shor", "comp", "magn", "doub", "sing", "ldbl":
			return xmlXPathNewFloat(try Double(appleEventDescriptor: descriptor))
		default:
			return withXMLString(try XMLCommands.text(descriptor)) { xmlXPathNewString($0) }
		}
	}

	/// An XPath value as an Apple event value: node sets as lists of XMLRefs, whole numbers as integers.
	static func result(_ object: xmlXPathObjectPtr, references: XMLReferences) -> NSAppleEventDescriptor {
		switch object.pointee.type {
		case XPATH_NODESET, XPATH_XSLT_TREE:
			return nodes(object.pointee.nodesetval).map { references.referenceOrText($0) }.appleEventDescriptor
		case XPATH_BOOLEAN:
			return NSAppleEventDescriptor(boolean: object.pointee.boolval != 0)
		case XPATH_NUMBER:
			return number(object.pointee.floatval)
		default:
			return NSAppleEventDescriptor(string: string(object))
		}
	}

	static func number(_ value: Double) -> NSAppleEventDescriptor {
		if value.isFinite, value == value.rounded(), let integer = Int32(exactly: value) {
			return NSAppleEventDescriptor(int32: integer)
		}
		return NSAppleEventDescriptor(double: value)
	}

	static func nodes(_ set: xmlNodeSetPtr?) -> [xmlNodePtr] {
		guard let set, let table = set.pointee.nodeTab else { return [] }
		return (0 ..< Int(set.pointee.nodeNr)).compactMap { table[$0] }
	}

	/// The XPath string value of a value.
	static func string(_ object: xmlXPathObjectPtr) -> String {
		Parsing.string(xmlXPathCastToString(object)) ?? ""
	}

	// MARK: Node paths

	/// The steps from the document to a node, as `XMLGetNodePath` writes them: `name[n]` (`*[n]` for an element in
	/// a namespace), `@name`, `text()[n]`, and `comment()` or `processing-instruction('name')` (with `[n]` when
	/// there are more than one).
	static func steps(to node: xmlNodePtr, from ancestor: xmlNodePtr? = nil) -> [String]? {
		var steps: [String] = []
		var current: xmlNodePtr? = node
		while let node = current, !XMLCommands.isDocument(node) {
			if let ancestor, node == ancestor { return steps }
			steps.insert(step(node), at: 0)
			current = node.pointee.parent
		}
		if let ancestor, let current, current != ancestor { return nil }
		return steps
	}

	private static func step(_ node: xmlNodePtr) -> String {
		let name = Parsing.name(node)
		func position(_ matches: (xmlNodePtr) -> Bool) -> (index: Int, count: Int) {
			var index = 1
			var count = 1
			var sibling = node.pointee.prev
			while let current = sibling {
				if matches(current) { index += 1; count += 1 }
				sibling = current.pointee.prev
			}
			sibling = node.pointee.next
			while let current = sibling {
				if matches(current) { count += 1 }
				sibling = current.pointee.next
			}
			return (index, count)
		}
		switch node.pointee.type {
		case XML_ATTRIBUTE_NODE:
			if let prefix = node.pointee.ns?.pointee.prefix {
				return "@\(String(cString: prefix)):\(name)"
			}
			return "@" + name
		case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
			return "text()[\(position { [XML_TEXT_NODE, XML_CDATA_SECTION_NODE].contains($0.pointee.type) }.index)]"
		case XML_COMMENT_NODE:
			let (index, count) = position { $0.pointee.type == XML_COMMENT_NODE }
			return count > 1 ? "comment()[\(index)]" : "comment()"
		case XML_PI_NODE:
			let (index, count) = position { $0.pointee.type == XML_PI_NODE && Parsing.name($0) == name }
			return "processing-instruction('\(name)')" + (count > 1 ? "[\(index)]" : "")
		default:
			if node.pointee.ns != nil {
				return "*[\(position { XMLCommands.isElement($0) }.index)]"
			}
			return "\(name)[\(position { XMLCommands.isElement($0) && $0.pointee.ns == nil && Parsing.name($0) == name }.index)]"
		}
	}

	/// `xpointer(/steps…)`, as SatimageOSAX wrote paths.
	static func pointer(_ node: xmlNodePtr, suffix: String = "") -> String {
		"xpointer(/" + (steps(to: node) ?? []).joined(separator: "/") + suffix + ")"
	}
}

extension XMLReferences {
	/// An XMLRef for a node of an open document; a namespace node (which XPath makes on the fly) as its URI.
	func referenceOrText(_ node: xmlNodePtr) -> NSAppleEventDescriptor {
		if node.pointee.type == XML_NAMESPACE_DECL {
			let ns = UnsafeMutableRawPointer(node).assumingMemoryBound(to: xmlNs.self)
			return NSAppleEventDescriptor(string: ns.pointee.href.map { String(cString: $0) } ?? "")
		}
		guard let document = XMLDocument.owner(of: node) else {
			return NSAppleEventDescriptor(string: Parsing.text(node))
		}
		return reference(node, in: document)
	}
}
