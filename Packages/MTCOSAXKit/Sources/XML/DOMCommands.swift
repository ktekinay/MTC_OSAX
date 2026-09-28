import AppleEventCore
import CLibXML
import Foundation
import PropertyLists

/// The "Satimage XML DOM" suite.
extension XMLCommands {
	var dom: [CommandDefinition] {
		[
			CommandDefinition("XMLOpen", code: "XML open", handler: open),
			CommandDefinition("XMLClose", code: "XML clos") { request in
				store.close(try direct(request).0)
				return nil
			},
			CommandDefinition("XMLRoot", code: "XML root") { request in
				let (document, _) = try direct(request)
				guard let root = xmlDocGetRootElement(document.doc) else { throw XML.notFound }
				return reference(root, document)
			},
			CommandDefinition("XMLCount", code: "XML cunt") { request in
				let (_, node) = try direct(request)
				return XMLCommands.children(of: node, allNodes: try request.parameter("ANot", default: true)).count
			},
			CommandDefinition("XMLCountElement", code: "XML ecun") { request in
				XMLCommands.children(of: try direct(request).1, allNodes: false).count
			},
			CommandDefinition("XMLChild", code: "XML chld") { try child($0, allNodes: $0.parameter("ANot", default: true)) },
			CommandDefinition("XMLElement", code: "XML echl") { try child($0, allNodes: false) },
			CommandDefinition("XMLParent", code: "XML pare") { request in
				try each(request) { document, node in
					guard let parent = node.pointee.parent else { throw XML.noSuchNode }
					return reference(parent, document)
				}
			},
			CommandDefinition("XMLNextSibling", code: "XML sibl") { try sibling($0, next: true, allNodes: $0.parameter("ANot", default: true)) },
			CommandDefinition("XMLNextElement", code: "XML esib") { try sibling($0, next: true, allNodes: false) },
			CommandDefinition("XMLPrevSibling", code: "XML psib") { try sibling($0, next: false, allNodes: $0.parameter("ANot", default: true)) },
			CommandDefinition("XMLPrevElement", code: "XML pesi") { try sibling($0, next: false, allNodes: false) },
			CommandDefinition("XMLTagName", code: "XML gtag") { request in
				try each(request) { _, node in NSAppleEventDescriptor(string: Parsing.name(node)) }
			},
			CommandDefinition("XMLGetAttribute", code: "XML geta", handler: getAttribute),
			CommandDefinition("XMLSetAttribute", code: "XML seta", handler: setAttribute),
			CommandDefinition("XMLRemoveAttribute", code: "XML rema", handler: removeAttribute),
			CommandDefinition("XMLRemove", code: "XML remo") { request in
				for (document, node) in try directNodes(request).nodes where !XMLCommands.isDocument(node) {
					modified(document)
					XMLCommands.remove(node)
				}
				return nil
			},
			CommandDefinition("XMLRemoveChildren", code: "XML remc") { request in
				for (document, node) in try directNodes(request).nodes {
					modified(document)
					for child in XMLCommands.children(of: node, allNodes: true) {
						XMLCommands.remove(child)
					}
				}
				return nil
			},
			CommandDefinition("XMLExists", code: "XML Exis") { request in
				// True if every reference is valid; false otherwise (SatimageOSAX gave -1728 for invalid ones).
				let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
				return XMLCommands.items(descriptor).allSatisfy { (try? resolve($0)) != nil }
			},
			CommandDefinition("XMLNewChild", code: "XML addc", handler: newChild),
			CommandDefinition("XMLNewSibling", code: "XML adds", handler: newSibling),
			CommandDefinition("XMLNodeInfo", code: "XML disp", handler: nodeInfo),
			CommandDefinition("XMLDisplayXML", code: "XML disx") { request in
				let options = try outputOptions(request)
				return try each(request) { _, node in NSAppleEventDescriptor(string: try Output.xml(node, options: options)) }
			},
			CommandDefinition("XMLSetXML", code: "XML stxm", handler: setXML),
			CommandDefinition("XMLGetText", code: "XML gttx") { request in
				try each(request) { _, node in NSAppleEventDescriptor(string: Parsing.text(node)) }
			},
			CommandDefinition("XMLSetText", code: "XML sttx", handler: setText),
			CommandDefinition("XMLAppendText", code: "XML ApTx", handler: appendText),
			CommandDefinition("XMLGetNameSpace", code: "XML gtn1") { request in
				let (_, node) = try direct(request)
				guard let ns = node.pointee.ns else { throw XML.notFound }
				return XMLCommands.namespaceRecord(ns)
			},
			CommandDefinition("XMLGetNameSpaces", code: "XML gtns") { request in
				let (document, node) = try direct(request)
				guard let list = xmlGetNsList(document.doc, node) else { return [NSAppleEventDescriptor]().appleEventDescriptor }
				defer { xmlRelease(list) }
				var result: [NSAppleEventDescriptor] = []
				var index = 0
				while let ns = list[index] {
					result.append(XMLCommands.namespaceRecord(ns).appleEventDescriptor)
					index += 1
				}
				return result.appleEventDescriptor
			},
			CommandDefinition("XMLGetNameSpaceFromPrefix", code: "XML gtn2") { request in
				let (document, node) = try direct(request)
				let prefix = try request.requiredParameter("pref", as: String.self)
				guard let ns = withOptionalXMLString(prefix.isEmpty ? nil : prefix, { xmlSearchNs(document.doc, node, $0) }),
				      let href = ns.pointee.href
				else { throw XML.notFound }
				return String(cString: href)
			},
			CommandDefinition("XMLAddNamespace", code: "XML adns", handler: addNamespace),
			CommandDefinition("XMLFind", code: "XML find", handler: find),
			CommandDefinition("XMLFindText", code: "XML fint", handler: findText),
			CommandDefinition("XMLRegexp", code: "XML grep", handler: regexp),
			CommandDefinition("XMLBase", code: "XML base") { request in
				let (document, node) = try direct(request)
				let target = XMLCommands.isDocument(node) ? (xmlDocGetRootElement(document.doc) ?? node) : node
				guard let base = Parsing.string(xmlNodeGetBase(document.doc, target)) else { throw XML.notFound }
				return try urlResult(base, request)
			},
			CommandDefinition("XMLSetBase", code: "XML Sbas") { request in
				let (document, node) = try direct(request)
				let base = try urlText(request.requiredParameter("to  ", as: AnyDescriptor.self).descriptor)
				modified(document)
				if base.isEmpty {
					withXMLString("http://www.w3.org/XML/1998/namespace") { href in
						withXMLString("base") { _ = xmlUnsetNsProp(node, xmlSearchNsByHref(document.doc, node, href), $0) }
					}
				} else {
					withXMLString(base) { xmlNodeSetBase(node, $0) }
				}
				return nil
			},
			CommandDefinition("XMLAbsoluteURL", code: "XML aURL") { request in
				let relative = try request.requiredDirectParameter(as: String.self)
				let base = try baseURL(request)
				guard let absolute = withXMLString(relative, { r in withXMLString(base) { Parsing.string(xmlBuildURI(r, $0)) } }) else {
					throw XML.invalid
				}
				return try urlResult(absolute, request)
			},
			CommandDefinition("XMLRelativeURL", code: "XML rURL") { request in
				let url = try urlText(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
				let base = try baseURL(request)
				guard let relative = withXMLString(url, { u in withXMLString(base) { Parsing.string(xmlBuildRelativeURI(u, $0)) } }) else {
					throw XML.invalid
				}
				return relative
			},
			CommandDefinition("XMLError", code: "XML lErr") { _ in XMLIssues.lastText },
		]
	}

	// MARK: Opening

	/// A file (alias, file reference, path or file URL), an http(s) URL, or `from string`.
	func open(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		var options = ParseOptions()
		options.keepBlanks = try request.parameter("kbln", default: false)
		options.loadExternalDTD = try request.parameter("LoEx", default: false)
		options.substituteEntities = try request.parameter("SuEn", default: false)
		options.validate = try request.parameter("Vali", default: false)
		options.html = try request.parameter("HTML", default: false)
		options.xmlScript = try request.parameter("xscp", default: false)
		options.noCDATA = try request.parameter("noCD", default: false)
		options.failureLevel = try request.parameter("ErLe", default: settings.errorLevel)
		options.extendedCharacters = settings.extendedCharacters
		options.bypassingNamespace = try request.parameter("bpns", default: false)
		options.encoding = try request.parameter("enco", as: String.self)
		let pool = try request.parameter("pool", as: String.self)

		let data: Data
		var url: URL?
		if let text = try request.parameter("from", as: String.self) {
			// Text is Unicode already: `encoding` applies to files.
			data = Data(text.utf8)
			options.encoding = "UTF-8"
		} else {
			let source = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
			let location = try Network.location(source)
			if location.isFileURL {
				guard let contents = try? Data(contentsOf: location) else {
					throw OSAXError(1549) // XML_IO_LOAD_ERROR, as SatimageOSAX replied
				}
				data = contents
			} else {
				data = try Network.fetch(location, post: request.parameter("post", default: false),
				                         query: request.parameter("qury", as: String.self), headers: request.descriptor(for: "head"))
			}
			url = location
		}
		let doc = try Parsing.parse(data, url: url?.absoluteString, options: options)
		let document = store.add(pool: pool) { XMLDocument(number: $0, pool: $1, doc: doc) }
		document.url = url
		return references.reference(document)
	}

	// MARK: Navigating

	func child(_ request: AppleEventRequest, allNodes: Bool) throws -> NSAppleEventDescriptor {
		let (document, node) = try direct(request)
		let indexDescriptor = try request.requiredParameter("indx", as: AnyDescriptor.self).descriptor
		guard indexDescriptor.descriptorType != typeAEList else { throw OSAXError.coercionFailed }
		let index = try Int(appleEventDescriptor: indexDescriptor)
		let children = XMLCommands.children(of: node, allNodes: allNodes)
		guard children.indices.contains(index - 1) else { throw XML.badIndex }
		return reference(children[index - 1], document)
	}

	func sibling(_ request: AppleEventRequest, next: Bool, allNodes: Bool) throws -> NSAppleEventDescriptor {
		try each(request) { document, node in
			guard let sibling = XMLCommands.sibling(of: node, next: next, allNodes: allNodes) else { throw XML.noSuchNode }
			return reference(sibling, document)
		}
	}

	// MARK: Attributes

	/// An attribute's value (-1728 if missing); with a list of names, a list with `missing value` for missing ones.
	func getAttribute(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let nameDescriptor = try request.requiredParameter("pnam", as: AnyDescriptor.self).descriptor
		let namespace = try request.parameter("nsls", as: String.self)
		let names = try XMLCommands.items(nameDescriptor).map(XMLCommands.text)
		return try each(request) { _, node in
			let values = names.map { name in
				withXMLString(name) { n in
					withOptionalXMLString(namespace) { ns in
						Parsing.string(ns == nil ? xmlGetProp(node, n) : xmlGetNsProp(node, n, ns))
					}
				}
			}
			if nameDescriptor.descriptorType == typeAEList {
				return values.map { $0.map(NSAppleEventDescriptor.init(string:)) ?? .missingValue }.appleEventDescriptor
			}
			guard let value = values[0], XMLCommands.isElement(node) else { throw XML.noSuchNode }
			return NSAppleEventDescriptor(string: value)
		}
	}

	/// Sets attributes; with lists of names and values, `missing value` is ignored, or removes the attribute with
	/// `suppressing`.
	func setAttribute(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let names = try XMLCommands.items(request.requiredParameter("pnam", as: AnyDescriptor.self).descriptor).map(XMLCommands.text)
		let values = XMLCommands.items(try request.requiredParameter("to  ", as: AnyDescriptor.self).descriptor)
		let namespace = try request.parameter("nsls", as: String.self)
		let suppressing = try request.parameter("Supp", default: false)
		for (document, node) in try directNodes(request).nodes {
			guard XMLCommands.isElement(node) else { throw XML.noSuchNode }
			modified(document)
			let ns = try namespace.map { href -> xmlNsPtr in
				guard let found = withXMLString(href, { xmlSearchNsByHref(document.doc, node, $0) }) else { throw XML.notFound }
				return found
			}
			for (name, value) in zip(names, values) {
				if XMLCommands.isMissingValue(value) {
					if suppressing {
						withXMLString(name) { _ = ns == nil ? xmlUnsetProp(node, $0) : xmlUnsetNsProp(node, ns, $0) }
					}
					continue
				}
				let text = try XMLCommands.text(value)
				withXMLString(name) { n in withXMLString(text) { v in _ = ns == nil ? xmlSetProp(node, n, v) : xmlSetNsProp(node, ns, n, v) } }
			}
		}
		return nil
	}

	func removeAttribute(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let names = try XMLCommands.items(request.requiredParameter("pnam", as: AnyDescriptor.self).descriptor).map(XMLCommands.text)
		let namespace = try request.parameter("nsls", as: String.self)
		for (document, node) in try directNodes(request).nodes {
			modified(document)
			let ns = namespace.flatMap { href in withXMLString(href) { xmlSearchNsByHref(document.doc, node, $0) } }
			for name in names {
				withXMLString(name) { _ = ns == nil ? xmlUnsetProp(node, $0) : xmlUnsetNsProp(node, ns, $0) }
			}
		}
		return nil
	}

	// MARK: New nodes

	/// The nodes to insert: parsed from XML text in `context`, or copies of XMLRefs.
	func newNodes(_ request: AppleEventRequest, context: xmlNodePtr, document: XMLDocument) throws -> (nodes: [xmlNodePtr], isList: Bool) {
		let value = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let keepBlanks = try request.parameter("kbln", default: false)
		let items = XMLCommands.items(value)
		if items.allSatisfy(XMLReferences.isReference) {
			let copies = try items.map { item -> xmlNodePtr in
				guard let copy = XMLCommands.copy(try resolve(item).1, into: document) else { throw XML.invalid }
				return copy
			}
			return (copies, value.descriptorType == typeAEList)
		}
		return (try Parsing.fragment(XMLCommands.text(value), in: context, keepBlanks: keepBlanks), false)
	}

	/// Appends XML text or copies of XMLRefs `at` an element; returns the first new node (or one per copied node).
	func newChild(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (document, parent) = try resolve(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
		let nsclean = try request.parameter("NsCl", default: true)
		let isClone = XMLCommands.items(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor).allSatisfy(XMLReferences.isReference)
		let (nodes, isList) = try newNodes(request, context: parent, document: document)
		guard !nodes.isEmpty else { throw XML.invalid }
		modified(document)
		for node in nodes {
			xmlAddChild(parent, node)
			// Only parsed XML is cleaned; clones keep their declarations, as in SatimageOSAX.
			if nsclean, !isClone { XMLCommands.cleanNamespaces(node) }
		}
		let references = nodes.map { reference($0, document) }
		return isList ? references.appleEventDescriptor : references[0]
	}

	/// Inserts XML text or copies `after` or `before` a node (-1700 with neither; -1 beside the root element).
	func newSibling(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let after = request.descriptor(for: "afte")
		guard let anchorDescriptor = after ?? request.descriptor(for: "befo") else { throw OSAXError.coercionFailed }
		let (document, anchor) = try resolve(anchorDescriptor)
		guard let parent = anchor.pointee.parent, !XMLCommands.isDocument(parent) else { throw XML.invalid }
		let (nodes, isList) = try newNodes(request, context: parent, document: document)
		guard !nodes.isEmpty else { throw XML.invalid }
		modified(document)
		var position = anchor
		for node in nodes {
			if after != nil {
				xmlAddNextSibling(position, node)
				position = node
			} else {
				xmlAddPrevSibling(anchor, node)
			}
		}
		let references = nodes.map { reference($0, document) }
		return isList ? references.appleEventDescriptor : references[0]
	}

	/// Replaces an element's contents with parsed XML, or a text node with parsed XML (which SatimageOSAX left the
	/// document unreadable after). Returns the first new node.
	func setXML(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let (document, node) = try direct(request)
		let text = try request.requiredParameter("to  ", as: String.self)
		let isText = node.pointee.type == XML_TEXT_NODE || node.pointee.type == XML_CDATA_SECTION_NODE
		guard let context = isText ? node.pointee.parent : node else { throw XML.invalid }
		let nodes = try Parsing.fragment(text, in: context, keepBlanks: true)
		modified(document)
		if isText {
			// Unlinked first: libxml2 merges a new text node into an adjacent one.
			let next = node.pointee.next
			XMLCommands.remove(node)
			for new in nodes {
				if let next { xmlAddPrevSibling(next, new) } else { xmlAddChild(context, new) }
			}
		} else {
			for child in XMLCommands.children(of: node, allNodes: true) { XMLCommands.remove(child) }
			for new in nodes { xmlAddChild(node, new) }
		}
		return nodes.first.map { reference($0, document) }
	}

	// MARK: Text

	/// Sets text (as it is: `&` is text, not an entity); an element's contents become the one text node. With
	/// lists, `missing value` is ignored, or empties the node with `suppressing`.
	func setText(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let (nodes, _) = try directNodes(request)
		let values = XMLCommands.items(try request.requiredParameter("to  ", as: AnyDescriptor.self).descriptor)
		let suppressing = try request.parameter("Supp", default: false)
		for ((document, node), value) in zip(nodes, values.count == 1 ? Array(repeating: values[0], count: nodes.count) : values) {
			if XMLCommands.isMissingValue(value) {
				guard suppressing else { continue }
				modified(document)
				if XMLCommands.isElement(node) {
					for child in XMLCommands.children(of: node, allNodes: true) { XMLCommands.remove(child) }
				} else {
					XMLCommands.remove(node)
				}
				continue
			}
			let text = try XMLCommands.text(value)
			modified(document)
			if XMLCommands.isElement(node) {
				for child in XMLCommands.children(of: node, allNodes: true) { XMLCommands.remove(child) }
				withXMLString(text) { _ = xmlAddChild(node, xmlNewDocText(document.doc, $0)) }
			} else {
				withXMLString(text) { xmlNodeSetContent(node, $0) }
			}
		}
		return nil
	}

	/// Appends text to a text node, or to an element (to its last text node, or a new one).
	func appendText(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let text = try request.requiredDirectParameter(as: String.self)
		let (document, node) = try resolve(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
		modified(document)
		withXMLString(text) { value in
			if node.pointee.type == XML_TEXT_NODE {
				xmlTextConcat(node, value, Int32(strlen(UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))))
			} else {
				_ = xmlAddChild(node, xmlNewDocText(document.doc, value))
			}
		}
		return nil
	}

	// MARK: Namespaces

	static func namespaceRecord(_ ns: xmlNsPtr) -> RecordFields {
		RecordFields([
			(.code("PREf"), NSAppleEventDescriptor(string: ns.pointee.prefix.map { String(cString: $0) } ?? "")),
			(.code("PUri"), NSAppleEventDescriptor(string: ns.pointee.href.map { String(cString: $0) } ?? "")),
		])
	}

	/// Declares a namespace (`{nsprefix:…, nsurl:…}`) on an element; -1 if the prefix is already declared there.
	func addNamespace(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let record = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard let fields = RecordFields(record), let url = fields[.code("PUri")].flatMap({ $0.stringValue }) else {
			throw OSAXError.coercionFailed
		}
		let prefix = fields[.code("PREf")]?.stringValue ?? ""
		let (document, node) = try resolve(request.requiredParameter("at  ", as: AnyDescriptor.self).descriptor)
		let ns = withXMLString(url) { href in withOptionalXMLString(prefix.isEmpty ? nil : prefix) { xmlNewNs(node, href, $0) } }
		guard ns != nil else { throw XML.invalid }
		modified(document)
		return nil
	}

	// MARK: Searching

	/// Children (not deeper) with a local name and/or an attribute `key` and `value`; not in a document (-50).
	func find(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (document, node) = try direct(request)
		let name = try request.parameter("pnam", as: String.self)
		let key = try request.parameter("key ", as: String.self)
		let value = try request.parameter("val ", as: String.self)
		let all = try request.parameter("WaAl", default: false)
		guard !XMLCommands.isDocument(node) else { throw OSAXError.parameterError }
		guard name != nil || key != nil, (key == nil) == (value == nil) else { throw OSAXError.missingParameter }
		let found = XMLCommands.children(of: node, allNodes: false).filter { child in
			if let name, Parsing.name(child) != name { return false }
			if let key, let value {
				return withXMLString(key) { Parsing.string(xmlGetProp(child, $0)) } == value
			}
			return true
		}
		return try results(found, document, all: all)
	}

	func results(_ nodes: [xmlNodePtr], _ document: XMLDocument, all: Bool) throws -> NSAppleEventDescriptor {
		if all {
			return nodes.map { reference($0, document) }.appleEventDescriptor
		}
		guard let first = nodes.first else { throw XML.notFound }
		return reference(first, document)
	}

	/// Text nodes under a node: text, CDATA and (as in SatimageOSAX) comments.
	static func textNodes(_ node: xmlNodePtr) -> [xmlNodePtr] {
		var result: [xmlNodePtr] = []
		Parsing.walk(node.pointee.children) { child in
			if [XML_TEXT_NODE, XML_CDATA_SECTION_NODE, XML_COMMENT_NODE].contains(child.pointee.type) {
				result.append(child)
			}
		}
		return result
	}

	/// Text nodes containing a string (case-sensitive).
	func findText(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let text = try request.requiredDirectParameter(as: String.self)
		let (document, node) = try resolve(request.requiredParameter("in  ", as: AnyDescriptor.self).descriptor)
		let found = XMLCommands.textNodes(node).filter { Parsing.text($0).contains(text) }
		return try results(found, document, all: request.parameter("WaAl", default: false))
	}

	/// Text nodes matching (or with `conforming` false, not matching) an XML Schema regular expression, which
	/// matches the whole text. An invalid pattern is libxml2's error number (1450).
	func regexp(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let pattern = try request.requiredDirectParameter(as: String.self)
		let (document, node) = try resolve(request.requiredParameter("in  ", as: AnyDescriptor.self).descriptor)
		let conforming = try request.parameter("Wcon", default: true)
		let (compiled, issues) = XMLIssues.collect { withXMLString(pattern) { xmlRegexpCompile($0) } }
		guard let compiled else { throw OSAXError(issues.first?.code ?? 1450) }
		defer { xmlRegFreeRegexp(compiled) }
		let found = XMLCommands.textNodes(node).filter { text in
			withXMLString(Parsing.text(text)) { (xmlRegexpExec(compiled, $0) == 1) == conforming }
		}
		return try results(found, document, all: request.parameter("WaAl", default: false))
	}

	// MARK: URLs

	func urlText(_ descriptor: NSAppleEventDescriptor) throws -> String {
		if [typeUnicodeText, typeUTF8Text, typeChar].contains(descriptor.descriptorType) {
			return descriptor.stringValue ?? ""
		}
		return try URL(appleEventDescriptor: descriptor).absoluteString
	}

	/// `from`: a node (its base; a document's is its own URL) or a URL.
	func baseURL(_ request: AppleEventRequest) throws -> String {
		let from = try request.requiredParameter("from", as: AnyDescriptor.self).descriptor
		if XMLReferences.isReference(from) {
			let (document, node) = try resolve(from)
			return Parsing.string(xmlNodeGetBase(document.doc, node)) ?? document.url?.absoluteString ?? ""
		}
		return try urlText(from)
	}

	/// A URL as text, or `as alias` (for a file URL).
	func urlResult(_ url: String, _ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		if request.descriptor(for: "rtyp")?.typeCodeValue.fourCharString == "alis", let file = URL(string: url), file.isFileURL,
		   let alias = NSAppleEventDescriptor.alias(file)
		{
			return alias
		}
		return NSAppleEventDescriptor(string: url)
	}

	// MARK: Node information

	static let kinds: [UInt32: String] = [
		1: "ELEMENT_NODE", 2: "ATTRIBUTE_NODE", 3: "TEXT_NODE", 4: "CDATA_SECTION_NODE", 5: "ENTITY_REF_NODE", 6: "ENTITY_NODE",
		7: "PI_NODE", 8: "COMMENT_NODE", 9: "DOCUMENT_NODE", 10: "DOCUMENT_TYPE_NODE", 11: "DOCUMENT_FRAG_NODE", 12: "NOTATION_NODE",
		13: "HTML_DOCUMENT_NODE", 14: "DTD_NODE", 15: "ELEMENT_DECL", 16: "ATTRIBUTE_DECL", 17: "ENTITY_DECL", 18: "NAMESPACE_DECL",
		19: "XINCLUDE_START", 20: "XINCLUDE_END",
	]

	/// The `NodeInfo` record: `kind`, and depending on the node its name, attributes, namespace, line
	/// (`paragraph`), and for documents whether they have a DTD and its IDs.
	func nodeInfo(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		if !XMLCommands.items(descriptor).allSatisfy(XMLReferences.isReference) {
			return try XMLCommands.fileInfo(URL(appleEventDescriptor: descriptor)).appleEventDescriptor
		}
		return try each(request) { document, node in XMLCommands.info(node, document).appleEventDescriptor }
	}

	/// The document type declaration or first element of a document's text: skips the XML declaration, comments,
	/// processing instructions and white space. The line is where the tag starts.
	static func firstTag(_ text: String) -> (isDoctype: Bool, name: String, line: Int)? {
		var index = text.startIndex
		while let open = text[index...].firstIndex(of: "<") {
			let rest = text[open...]
			if rest.hasPrefix("<?") || rest.hasPrefix("<!--") {
				let close = rest.hasPrefix("<?") ? "?>" : "-->"
				guard let end = rest.range(of: close) else { return nil }
				index = end.upperBound
				continue
			}
			let line = text[..<open].filter { $0 == "\n" || $0 == "\r\n" }.count + 1
			let isDoctype = rest.uppercased().hasPrefix("<!DOCTYPE")
			let nameStart = isDoctype ? rest.index(open, offsetBy: 9) : rest.index(after: open)
			let name = text[nameStart...].drop { $0.isWhitespace }.prefix { !$0.isWhitespace && !"/>[".contains($0) }
			return (isDoctype, String(name), line)
		}
		return nil
	}

	/// `XMLNodeInfo` of a file: only the start is read, up to its document type declaration or else its root
	/// element (so a file that's malformed further on still works): kind, name, line, whether it has a DTD, and the
	/// encoding its XML declaration names. -43 for a missing file.
	static func fileInfo(_ file: URL) throws -> RecordFields {
		guard let data = try? Data(contentsOf: file) else { throw OSAXError(-43) }
		guard let found = firstTag(String(decoding: data.prefix(65536), as: UTF8.self)) else { throw XML.notFound }
		let isDoctype = found.isDoctype
		var fields: [(key: RecordFields.Key, value: NSAppleEventDescriptor)] = [
			(.code("kind"), NSAppleEventDescriptor(descriptorType: typeChar, data: Data((isDoctype ? "DOCUMENT_TYPE_NODE" : "ELEMENT_NODE").utf8))!),
			(.code("pnam"), NSAppleEventDescriptor(string: found.name)),
			(.code("stnd"), NSAppleEventDescriptor(boolean: true)),
			(.code("hdtd"), NSAppleEventDescriptor(boolean: isDoctype)),
			(.code("cpar"), NSAppleEventDescriptor(int32: Int32(found.line))),
		]
		let start = String(decoding: data.prefix(200), as: UTF8.self)
		if let match = start.firstMatch(of: /^<\?xml[^>]*encoding=["']([^"']+)["']/) {
			fields.append((.code("enco"), NSAppleEventDescriptor(string: String(match.1))))
		}
		return RecordFields(fields)
	}

	static func info(_ node: xmlNodePtr, _ document: XMLDocument) -> RecordFields {
		var fields: [(key: RecordFields.Key, value: NSAppleEventDescriptor)] = [
			(.code("kind"), NSAppleEventDescriptor(descriptorType: typeChar, data: Data((kinds[node.pointee.type.rawValue] ?? "").utf8))!),
		]
		if isDocument(node), let doc = document.doc {
			let dtd = doc.pointee.intSubset ?? doc.pointee.extSubset
			if let dtd {
				if let id = dtd.pointee.ExternalID { fields.append((.code("ExID"), NSAppleEventDescriptor(string: String(cString: id)))) }
				if let id = dtd.pointee.SystemID { fields.append((.code("SyID"), NSAppleEventDescriptor(string: String(cString: id)))) }
			}
			fields.append((.code("hdtd"), NSAppleEventDescriptor(boolean: dtd != nil)))
			if document.isHTML || doc.pointee.standalone == 1 {
				fields.append((.code("stnd"), NSAppleEventDescriptor(boolean: true)))
			}
			fields.append((.code("imod"), NSAppleEventDescriptor(boolean: document.isModified)))
			return RecordFields(fields)
		}
		let type = node.pointee.type
		if type == XML_ELEMENT_NODE || type == XML_PI_NODE || type == XML_ATTRIBUTE_NODE {
			fields.append((.code("pnam"), NSAppleEventDescriptor(string: Parsing.name(node))))
		}
		if type == XML_ELEMENT_NODE {
			if let ns = node.pointee.ns {
				fields.append((.code("nsls"), namespaceRecord(ns).appleEventDescriptor))
			}
			var attributes: [String] = []
			var current = node.pointee.properties
			while let attribute = current {
				let name = attribute.pointee.name.map { String(cString: $0) } ?? ""
				attributes.append(name)
				attributes.append(withXMLString(name) { Parsing.string(xmlGetProp(node, $0)) } ?? "")
				current = attribute.pointee.next
			}
			if !attributes.isEmpty {
				fields.append((.code("attr"), attributes.appleEventDescriptor))
			}
		}
		fields.append((.code("cpar"), NSAppleEventDescriptor(int32: Int32(xmlGetLineNo(node)))))
		return RecordFields(fields)
	}

	// MARK: Output options

	func outputOptions(_ request: AppleEventRequest) throws -> Output.Options {
		var options = Output.Options()
		options.formatting = try request.parameter("smar", default: true)
		options.declaration = try request.parameter("XmlH", default: true)
		options.nsclean = try request.parameter("NsCl", default: true)
		options.html = try request.parameter("HTML", default: false)
		options.encoding = try request.parameter("enco", as: String.self)
		options.indent = settings.indentString
		return options
	}
}
