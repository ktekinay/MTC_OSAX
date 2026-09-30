import AppleEventCore
import CLibXML
import Foundation
import PropertyLists

/// Satimage's four XML suites (event class `XML `): XML DOM, XPath and XSLT, Documents, and Validation, built on
/// macOS's libxml2 and libxslt as SatimageOSAX's were.
/// Behavior recorded from SatimageOSAX in `Fixtures/XML`; where Satimage was broken, MTC_OSAX follows the
/// dictionary (`Fixtures/XMLFixes`, listed in Implemented/PLAN-XML.md).
public enum XML {
	// Error numbers recorded from SatimageOSAX (libxml2's own numbers are passed through as they are).
	static let noSuchNode = OSAXError(-1728) // errAENoSuchObject
	static let notFound = OSAXError(-2763)
	static let invalid = OSAXError(-1)
	static let badIndex = OSAXError(-1719) // errAEIllegalIndex

	/// - Parameter store: the open documents, shared with the PropertyList suite and its pools.
	@MainActor
	public static func commands(store: DocumentStore = DocumentStore()) -> [CommandDefinition] {
		let commands = XMLCommands(store: store, settings: XMLSettings())
		NetworkInput.install()
		Stylesheets.registerEXSLT()
		store.addResolver { descriptor in
			XMLReferences.isReference(descriptor) ? try commands.references.resolve(descriptor).0 : nil
		}
		// libxml2's callbacks are per thread; the app runs every command on the main thread, tests on several.
		return (commands.dom + commands.documents + commands.xpath + commands.xslt + commands.validation).map { command in
			CommandDefinition(command.name, code: command.key.code) { request in
				XMLDocument.installCallbacks()
				return try Network.withTimeBudget { try command.handler(request) }
			}
		}
	}

	/// The libxml2 version in use, e.g. "20913".
	static var libxmlVersion: String {
		String(cString: __xmlParserVersion().pointee!)
	}
}

/// The handlers, sharing the document store.
@MainActor
struct XMLCommands {
	let store: DocumentStore
	let settings: XMLSettings
	var references: XMLReferences { XMLReferences(store: store) }

	// MARK: Parameters

	func resolve(_ descriptor: NSAppleEventDescriptor) throws -> (XMLDocument, xmlNodePtr) {
		try references.resolve(descriptor)
	}

	func direct(_ request: AppleEventRequest) throws -> (XMLDocument, xmlNodePtr) {
		try resolve(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
	}

	/// Whether a value is an `XPathRef` record: `{XMLRef:…, xpath pattern:…}`.
	static func isXPathReference(_ descriptor: NSAppleEventDescriptor) -> Bool {
		descriptor.descriptorType != typeAEList && RecordFields(descriptor)?[.code("XMLR")] != nil
	}

	/// The XMLRefs a command's nodes are given as: one, a list, or an `XPathRef` record, which stands for the list
	/// of nodes its expression selects wherever a list of XMLRefs can go, as the dictionary says. As in SatimageOSAX
	/// that's a list even of one node, and empty when the expression gives something other than nodes; namespace
	/// nodes (which XPath makes on the fly) are left out.
	func nodeReferences(_ descriptor: NSAppleEventDescriptor) throws -> (items: [NSAppleEventDescriptor], isList: Bool) {
		guard XMLCommands.isXPathReference(descriptor) else {
			return (XMLCommands.items(descriptor), descriptor.descriptorType == typeAEList)
		}
		let items = try withXPathReference(descriptor) { _, object in
			guard object.pointee.type == XPATH_NODESET else { return [NSAppleEventDescriptor]() }
			return XPath.nodes(object.pointee.nodesetval).compactMap { node in
				node.pointee.type == XML_NAMESPACE_DECL ? nil : XMLDocument.owner(of: node).map { reference(node, $0) }
			}
		}
		return (items, true)
	}

	/// The direct parameter's nodes: one, a list, or an `XPathRef`. Commands that take lists answer with lists.
	func directNodes(_ request: AppleEventRequest) throws -> (nodes: [(XMLDocument, xmlNodePtr)], isList: Bool) {
		let (items, isList) = try nodeReferences(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		return (try items.map(resolve), isList)
	}

	/// Changes the direct parameter's nodes in turn, with each one's position in the list. Every reference is
	/// checked first (-1728 for one that's invalid), then resolved again just before its node is changed, so a node
	/// that an earlier change freed (a descendant of a removed node, or one listed twice) is skipped instead of used.
	func changeEach(_ request: AppleEventRequest, _ change: (Int, XMLDocument, xmlNodePtr) throws -> Void) throws {
		let items = try nodeReferences(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor).items
		for item in items {
			_ = try resolve(item)
		}
		for (index, item) in items.enumerated() {
			guard let (document, node) = try? resolve(item) else { continue }
			try change(index, document, node)
		}
	}

	func reference(_ node: xmlNodePtr, _ document: XMLDocument) -> NSAppleEventDescriptor {
		references.reference(node, in: document)
	}

	/// One result per node, as a list if the direct parameter was one.
	func each(_ request: AppleEventRequest, _ transform: (XMLDocument, xmlNodePtr) throws -> NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
		let (nodes, isList) = try directNodes(request)
		let results = try nodes.map(transform)
		return isList ? results.appleEventDescriptor : results[0]
	}

	static func text(_ descriptor: NSAppleEventDescriptor) throws -> String {
		if [typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType) {
			return descriptor.stringValue ?? ""
		}
		guard let text = descriptor.coerce(toDescriptorType: typeUnicodeText)?.stringValue else {
			throw OSAXError.coercionFailed
		}
		return text
	}

	static func isMissingValue(_ descriptor: NSAppleEventDescriptor) -> Bool {
		descriptor.descriptorType == typeType && descriptor.typeCodeValue.fourCharString == "msng"
	}

	static func items(_ descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
		descriptor.descriptorType == typeAEList ? (0 ..< descriptor.numberOfItems).map { descriptor.atIndex($0 + 1)! } : [descriptor]
	}

	// MARK: Tree

	static func isElement(_ node: xmlNodePtr) -> Bool {
		node.pointee.type == XML_ELEMENT_NODE
	}

	static func isDocument(_ node: xmlNodePtr) -> Bool {
		node.pointee.type == XML_DOCUMENT_NODE || node.pointee.type == XML_HTML_DOCUMENT_NODE
	}

	/// An element's or attribute's namespace. Only they have one: other kinds of node keep something else in that
	/// field (a document its `compression` and `standalone`, a DTD its notations, a declaration its type).
	static func namespace(of node: xmlNodePtr) -> xmlNsPtr? {
		node.pointee.type == XML_ELEMENT_NODE || node.pointee.type == XML_ATTRIBUTE_NODE ? node.pointee.ns : nil
	}

	/// Children, with or without the nodes that aren't elements (`all nodes`). An entity reference's one child is its
	/// entity's declaration (whose siblings are the rest of the DTD, not the reference's).
	static func children(of node: xmlNodePtr, allNodes: Bool) -> [xmlNodePtr] {
		if node.pointee.type == XML_ENTITY_REF_NODE {
			return allNodes ? node.pointee.children.map { [$0] } ?? [] : []
		}
		var result: [xmlNodePtr] = []
		var current = node.pointee.children
		while let child = current {
			if allNodes || isElement(child) {
				result.append(child)
			}
			current = child.pointee.next
		}
		return result
	}

	static func sibling(of node: xmlNodePtr, next: Bool, allNodes: Bool) -> xmlNodePtr? {
		var current = next ? node.pointee.next : node.pointee.prev
		while let sibling = current {
			if allNodes || isElement(sibling) {
				return sibling
			}
			current = next ? sibling.pointee.next : sibling.pointee.prev
		}
		return nil
	}

	func modified(_ document: XMLDocument) {
		document.isModified = true
	}

	/// The kinds of node that can be inside an element: the ones scripts can move, replace and remove.
	static let contentKinds = [XML_ELEMENT_NODE, XML_TEXT_NODE, XML_CDATA_SECTION_NODE, XML_COMMENT_NODE, XML_PI_NODE, XML_ENTITY_REF_NODE]

	/// Error -50 (or `error`) unless the node is one of `kinds`. Declarations inside a DTD in particular can be read
	/// but not changed: libxml2 frees them through the DTD's tables, not as nodes.
	static func require(_ node: xmlNodePtr, isOneOf kinds: [xmlElementType], error: OSAXError = .parameterError) throws {
		guard kinds.contains(node.pointee.type) else {
			throw error
		}
	}

	/// Unlinks and frees nodes (their references then give -1728). A DTD's declarations are freed without
	/// libxml2's node callback, so their numbers are forgotten first, and entity references to its entities are
	/// detached from them. Removing text from an ID attribute changes the ID.
	static func remove(_ node: xmlNodePtr) {
		if node.pointee.type == XML_DTD_NODE {
			XMLDocument.forgetNumbers(in: node.pointee.children)
			detachEntityReferences(from: node, in: node.pointee.doc)
		}
		guard node.pointee.type != XML_ATTRIBUTE_NODE else {
			// libxml2 takes a freed attribute's ID out of the table itself.
			xmlUnlinkNode(node)
			xmlFreeNode(node)
			return
		}
		changingValue(of: node) {
			xmlUnlinkNode(node)
			xmlFreeNode(node)
		}
	}

	/// Runs `change`, which changes the value of an attribute or of the text in one, keeping libxml2's table of IDs
	/// right. The table is found by an ID's value, and libxml2 doesn't update it when an attribute's text changes:
	/// the old value then led to the attribute after it was freed (XMLGetByID, and XPath's `id()`, read freed
	/// memory). The attribute must still be there afterwards.
	nonisolated static func changingValue<T>(of node: xmlNodePtr, _ change: () throws -> T) rethrows -> T {
		let owner = node.pointee.type == XML_ATTRIBUTE_NODE ? node : node.pointee.parent
		guard let owner, owner.pointee.type == XML_ATTRIBUTE_NODE, let doc = owner.pointee.doc else { return try change() }
		let attribute = UnsafeMutableRawPointer(owner).assumingMemoryBound(to: xmlAttr.self)
		guard attribute.pointee.atype == XML_ATTRIBUTE_ID else { return try change() }
		xmlRemoveID(doc, attribute)
		defer {
			if let value = xmlNodeListGetString(doc, attribute.pointee.children, 1) {
				xmlAddID(nil, doc, value, attribute)
				xmlRelease(value)
			}
		}
		return try change()
	}

	/// An entity reference points at its entity (as its child, and its content is the entity's), so after the DTD
	/// declaring the entity is freed, it would point at freed memory. Without them it's a reference to an entity
	/// that isn't declared, which libxml2 looks up by name, finds nothing, and writes as it is (`&e;`).
	private static func detachEntityReferences(from dtd: xmlNodePtr, in doc: xmlDocPtr?) {
		func detach(_ node: xmlNodePtr) {
			guard node.pointee.type == XML_ENTITY_REF_NODE, let entity = node.pointee.children, entity.pointee.parent == dtd else { return }
			node.pointee.children = nil
			node.pointee.last = nil
			node.pointee.content = nil
		}
		guard let doc else { return }
		Parsing.walk(UnsafeMutableRawPointer(doc).assumingMemoryBound(to: xmlNode.self).pointee.children) { node in
			detach(node)
			var attribute = node.pointee.type == XML_ELEMENT_NODE ? node.pointee.properties : nil
			while let current = attribute {
				var child = current.pointee.children
				while let value = child {
					detach(value)
					child = value.pointee.next
				}
				attribute = current.pointee.next
			}
		}
	}

	/// The node an `xmlAddChild`, `xmlAddNextSibling` or `xmlAddPrevSibling` call left in the tree. libxml2 merges a
	/// text node into an adjacent text node and frees it, returning the node it merged into; that one is then the
	/// node to refer to (and to insert after). -1 if it wasn't added (it's freed).
	static func added(_ node: xmlNodePtr, _ result: xmlNodePtr?) throws -> xmlNodePtr {
		guard let result else {
			xmlFreeNode(node)
			throw XML.invalid
		}
		return result
	}

	/// Copies a node (and what's in it) into a document, for inserting a clone.
	static func copy(_ node: xmlNodePtr, into document: XMLDocument) -> xmlNodePtr? {
		xmlDocCopyNode(node, document.doc, 1)
	}

	/// Removes namespace declarations of new nodes that an ancestor already declares (`nsclean`).
	static func cleanNamespaces(_ node: xmlNodePtr) {
		guard isElement(node), let context = xmlDOMWrapNewCtxt() else { return }
		defer { xmlDOMWrapFreeCtxt(context) }
		xmlDOMWrapReconcileNamespaces(context, node, 1) // XML_DOM_RECONNS_REMOVEREDUND (private to tree.c)
	}
}
