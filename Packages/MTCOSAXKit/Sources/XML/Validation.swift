import AppleEventCore
import CLibXML
import Foundation

/// The "XML Validation" suite: DTDs, XML Schema and RelaxNG, IDs and names. Errors are libxml2's numbers for the
/// first problem, and `XMLError` lists the problems.
extension XMLCommands {
	var validation: [CommandDefinition] {
		[
			CommandDefinition("XMLValidate", code: "XML vali", handler: validate),
			CommandDefinition("XMLSchema", code: "XML Schm", handler: schema),
			CommandDefinition("XMLRelaxNG", code: "XML rlax", handler: relaxNG),
			CommandDefinition("XMLCheckDTD", code: "XML Pdtd") { request in
				let dtd = try Validation.dtd(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
				xmlFreeDtd(dtd)
				return nil
			},
			CommandDefinition("XMLGetByID", code: "XML geti", handler: getByID),
			CommandDefinition("XMLGetxmlID", code: "XML geID") { request in
				let (document, node) = try direct(request)
				guard XMLCommands.isElement(node) else { throw XML.notFound }
				var attribute = node.pointee.properties
				while let current = attribute {
					if xmlIsID(document.doc, node, current) != 0 {
						return Parsing.text(UnsafeMutableRawPointer(current).assumingMemoryBound(to: xmlNode.self))
					}
					attribute = current.pointee.next
				}
				throw XML.notFound
			},
			CommandDefinition("XMLValidName", code: "XML Isnm") { try validNames($0) { xmlValidateName($0, 0) } },
			CommandDefinition("XMLValidNCName", code: "XML Isnc") { try validNames($0) { xmlValidateNCName($0, 0) } },
			CommandDefinition("XMLDu", code: "XML du  ") { request in
				let (_, node) = try direct(request)
				return XMLCommands.outline(node)
			},
		]
	}

	// MARK: DTDs

	/// Validates a document, or an element, against its DTD or the DTD `against`. Fails on the first problem at or
	/// above the failure level (2, errors, by default); 522 without a DTD.
	func validate(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let (document, node) = try direct(request)
		guard let doc = document.doc else { throw XML.noSuchNode }
		let failureLevel = try request.parameter("ErLe", default: 2)
		let dtd = try request.descriptor(for: "agai").map(Validation.dtd)
		defer { xmlFreeDtd(dtd) }
		guard let context = xmlNewValidCtxt() else { throw XML.invalid }
		defer { xmlFreeValidCtxt(context) }
		var (_, issues) = XMLIssues.collect { () -> Int32 in
			if XMLCommands.isDocument(node) {
				return dtd.map { xmlValidateDtd(context, doc, $0) } ?? xmlValidateDocument(context, doc)
			}
			return Validation.withSubset(dtd, of: doc) { xmlValidateElement(context, doc, node) }
		}
		if !XMLCommands.isDocument(node) {
			// Validating an element registers its IDs again; only real duplicates count (SatimageOSAX gave 513 for any).
			issues = Validation.withoutRepeatedIDs(issues, in: node, doc: doc)
		}
		if let failure = issues.first(where: { $0.level >= failureLevel }) {
			throw OSAXError(failure.code)
		}
		XMLIssues.lastText = XMLIssues.text(issues)
		return nil
	}

	// MARK: Schemas

	/// Validates a document or an element against an XML Schema (`with respect to`, or the document's
	/// `xsi:schemaLocation` or `xsi:noNamespaceSchemaLocation`), or only checks the schema. -1701 with neither.
	func schema(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let target = try request.descriptor(for: Keyword.directObject).map(resolve)
		let with = request.descriptor(for: "With")
		guard target != nil || with != nil else { throw OSAXError.missingParameter }

		var schema: xmlSchemaPtr?
		if let with {
			let source = try Validation.Source(with, references: references)
			defer { source.release() }
			let parser: xmlSchemaParserCtxtPtr? = switch source {
			case let .url(url): xmlSchemaNewParserCtxt(url)
			case let .text(text): xmlSchemaNewMemParserCtxt(text, Int32(strlen(text)))
			case let .document(doc): xmlSchemaNewDocParserCtxt(doc)
			}
			guard let parser else { throw XML.invalid }
			defer { xmlSchemaFreeParserCtxt(parser) }
			let (parsed, issues) = XMLIssues.collect { xmlSchemaParse(parser) }
			guard let parsed else { throw Validation.parseFailure(issues) }
			schema = parsed
		}
		defer { xmlSchemaFree(schema) }
		guard let (document, node) = target, let doc = document.doc else { return nil }
		// Without a schema, libxml2 follows the document's xsi: locations.
		guard let context = xmlSchemaNewValidCtxt(schema) else { throw XML.invalid }
		defer { xmlSchemaFreeValidCtxt(context) }
		let (result, issues) = XMLIssues.collect {
			XMLCommands.isDocument(node) ? xmlSchemaValidateDoc(context, doc) : xmlSchemaValidateOneElement(context, node)
		}
		guard result == 0 else { throw OSAXError(issues.first(where: { $0.level >= 2 })?.code ?? Int(result)) }
		return nil
	}

	/// Validates a document or an element against a RelaxNG schema (`with respect to`, required), or only checks
	/// the schema.
	func relaxNG(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let target = try request.descriptor(for: Keyword.directObject).map(resolve)
		guard let with = request.descriptor(for: "With") else { throw OSAXError.missingParameter }
		let source = try Validation.Source(with, references: references)
		defer { source.release() }
		let parser: xmlRelaxNGParserCtxtPtr? = switch source {
		case let .url(url): xmlRelaxNGNewParserCtxt(url)
		case let .text(text): xmlRelaxNGNewMemParserCtxt(text, Int32(strlen(text)))
		case let .document(doc): xmlRelaxNGNewDocParserCtxt(doc)
		}
		guard let parser else { throw XML.invalid }
		defer { xmlRelaxNGFreeParserCtxt(parser) }
		let (parsed, parseIssues) = XMLIssues.collect { xmlRelaxNGParse(parser) }
		guard let schema = parsed else { throw Validation.parseFailure(parseIssues) }
		defer { xmlRelaxNGFree(schema) }
		guard let (document, node) = target, let doc = document.doc else { return nil }
		guard let context = xmlRelaxNGNewValidCtxt(schema) else { throw XML.invalid }
		defer { xmlRelaxNGFreeValidCtxt(context) }
		let (result, issues) = XMLIssues.collect { () -> Int32 in
			if XMLCommands.isDocument(node) {
				return xmlRelaxNGValidateDoc(context, doc)
			}
			// An element is validated as the root of a document of its own.
			let scratch = xmlNewDoc(nil)
			defer { xmlFreeDoc(scratch) }
			let copy = xmlDocCopyNode(node, scratch, 1)
			XMLDocument.clearNumbers(copy)
			xmlDocSetRootElement(scratch, copy)
			return xmlRelaxNGValidateDoc(context, scratch)
		}
		guard result == 0 else { throw OSAXError(issues.first?.code ?? Int(result)) }
		return nil
	}

	// MARK: IDs and names

	/// The element with an ID (xml:id, or an ID attribute of the DTD): -2763 if there's none; for a list of IDs, a
	/// list with `missing value` for those that aren't found.
	func getByID(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let (document, _) = try direct(request)
		let ids = try request.requiredParameter("xlmi", as: AnyDescriptor.self).descriptor
		func element(_ id: String) -> xmlNodePtr? {
			withXMLString(id) { xmlGetID(document.doc, $0) }?.pointee.parent
		}
		if ids.descriptorType == typeAEList {
			return try XMLCommands.items(ids).map { id in
				try element(XMLCommands.text(id)).map { reference($0, document) } ?? .missingValue
			}.appleEventDescriptor
		}
		guard let found = element(try XMLCommands.text(ids)) else { throw XML.notFound }
		return reference(found, document)
	}

	/// Whether every name is valid (SatimageOSAX gave error 1821 for an invalid one).
	func validNames(_ request: AppleEventRequest, _ check: (UnsafePointer<xmlChar>) -> Int32) throws -> Bool {
		let names = try XMLCommands.items(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor).map(XMLCommands.text)
		return names.allSatisfy { name in !name.isEmpty && withXMLString(name, check) == 0 }
	}

	/// `XMLDu`: the element names under a node, one per line, indented with tabs; a document starts with `/`.
	static func outline(_ node: xmlNodePtr) -> String {
		var result = isDocument(node) ? "/\n" : ""
		func add(_ element: xmlNodePtr, depth: Int) {
			result += String(repeating: "\t", count: depth) + Parsing.name(element) + "\n"
			for child in children(of: element, allNodes: false) {
				add(child, depth: depth + 1)
			}
		}
		for element in isDocument(node) ? children(of: node, allNodes: false) : isElement(node) ? [node] : [] {
			add(element, depth: 0)
		}
		return result
	}
}

enum Validation {
	/// Where a schema comes from: a file or URL, XML text (a copy libxml2 reads while parsing), or an open document.
	enum Source {
		case url(String)
		case text(UnsafeMutablePointer<CChar>)
		case document(xmlDocPtr)

		func release() {
			if case let .text(text) = self { free(text) }
		}

		/// An alias or file, a path, URL or XML text, or an XMLRef.
		init(_ descriptor: NSAppleEventDescriptor, references: XMLReferences) throws {
			if XMLReferences.isReference(descriptor) {
				guard let doc = try references.resolve(descriptor).0.doc else { throw XML.noSuchNode }
				self = .document(doc)
			} else if let text = try Validation.text(descriptor) {
				self = text.drop(while: \.isWhitespace).hasPrefix("<") ? .text(strdup(text)) : .url(Validation.url(text))
			} else {
				self = .url(try URL(appleEventDescriptor: descriptor).absoluteString)
			}
		}
	}

	/// A schema that didn't parse: the first problem's number (1549 if it can't be loaded).
	static func parseFailure(_ issues: [XMLIssue]) -> OSAXError {
		OSAXError(issues.first?.code ?? 1549)
	}

	static func text(_ descriptor: NSAppleEventDescriptor) throws -> String? {
		[typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType)
			? try XMLCommands.text(descriptor) : nil
	}

	/// A path or URL as a URL for libxml2.
	static func url(_ text: String) -> String {
		if let url = URL(string: text), let scheme = url.scheme, scheme.count > 1 {
			return text
		}
		return URL(fileURLWithPath: text).absoluteString
	}

	/// A DTD from a file (alias, file, path or URL) or its text. Error: libxml2's number for the first problem
	/// (1549 if it can't be read).
	static func dtd(_ descriptor: NSAppleEventDescriptor) throws -> xmlDtdPtr {
		let (dtd, issues) = try XMLIssues.collect { () -> xmlDtdPtr? in
			if let text = try Validation.text(descriptor), text.contains("<") {
				let data = Data(text.utf8)
				let buffer = data.withUnsafeBytes { xmlParserInputBufferCreateMem($0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), XML_CHAR_ENCODING_UTF8) }
				return xmlIOParseDTD(nil, buffer, XML_CHAR_ENCODING_UTF8)
			}
			let url = try Validation.text(descriptor).map(Validation.url) ?? URL(appleEventDescriptor: descriptor).absoluteString
			return withXMLString(url) { xmlParseDTD(nil, $0) }
		}
		guard let dtd, !issues.contains(where: { $0.level >= 2 }) else {
			xmlFreeDtd(dtd)
			throw OSAXError(issues.first?.code ?? 1549)
		}
		return dtd
	}

	/// Runs `body` with `dtd`, if given, as the document's only DTD.
	static func withSubset<T>(_ dtd: xmlDtdPtr?, of doc: xmlDocPtr, _ body: () -> T) -> T {
		guard let dtd else { return body() }
		let (internalSubset, externalSubset) = (doc.pointee.intSubset, doc.pointee.extSubset)
		doc.pointee.intSubset = nil
		doc.pointee.extSubset = dtd
		defer {
			doc.pointee.intSubset = internalSubset
			doc.pointee.extSubset = externalSubset
		}
		return body()
	}

	/// Leaves out "ID already defined" (513) unless an ID really is repeated in the element.
	static func withoutRepeatedIDs(_ issues: [XMLIssue], in node: xmlNodePtr, doc: xmlDocPtr) -> [XMLIssue] {
		var seen = Set<String>()
		var repeated = false
		Parsing.walk(node) { element in
			guard element == node || isInside(element, node) else { return }
			var attribute = element.pointee.properties
			while let current = attribute {
				if xmlIsID(doc, element, current) != 0 {
					repeated = !seen.insert(Parsing.text(UnsafeMutableRawPointer(current).assumingMemoryBound(to: xmlNode.self))).inserted || repeated
				}
				attribute = current.pointee.next
			}
		}
		return repeated ? issues : issues.filter { $0.code != 513 }
	}

	private static func isInside(_ node: xmlNodePtr, _ ancestor: xmlNodePtr) -> Bool {
		var current = node.pointee.parent
		while let parent = current {
			if parent == ancestor { return true }
			current = parent.pointee.parent
		}
		return false
	}
}
