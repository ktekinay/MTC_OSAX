import AppleEventCore
import CLibXML
import Foundation
import PropertyLists

/// XSLT: `XMLTransform` and `XMLCompile`, with libxslt and EXSLT.
extension XMLCommands {
	var xslt: [CommandDefinition] {
		[
			CommandDefinition("XMLTransform", code: "XML xslt", handler: transform),
			CommandDefinition("XMLCompile", code: "XML pxsl") { request in
				let document = try direct(request).0
				guard let doc = document.doc else { throw XML.noSuchNode }
				let style = try Stylesheets.compile(Stylesheets.copy(doc))
				if let old = document.stylesheet { xsltFreeStylesheet(old) }
				document.stylesheet = style
				return nil
			},
		]
	}

	/// Transforms a document, or a node (the stylesheet's templates applied to it), with the stylesheet `with`
	/// (a file, a path or URL, an XMLRef, or XSLT text), or the one the document's `xml-stylesheet` processing
	/// instruction names (-1701 if none). The result is a new document in the pool, `as string` its text,
	/// `as CFRef` a property list, or written to the file `in`.
	///
	/// A stylesheet the script gives can write files (`exsl:document`), as the script itself could. One the document
	/// chooses is code from the document, which may not be trusted: it can't write files, make folders or use the
	/// network, and it (and what it imports and reads) must come from the document's folder (error 1535, libxml2's
	/// "not permitted", as SatimageOSAX's sandbox gave). Otherwise it could read any file and send it anywhere.
	func transform(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let (document, node) = try direct(request)
		guard let doc = document.doc else { throw XML.noSuchNode }
		let target = XMLCommands.isDocument(node) ? nil : node
		let style = try stylesheet(request, document: document, node: target)
		defer { if style.owned { xsltFreeStylesheet(style.pointer) } }

		var parameters: [(String, String)] = try XPath.variables(request.descriptor(for: "varx")).map { ($0.name, try XMLCommands.text($0.value)) }
		parameters += try XPath.variables(request.descriptor(for: "vaxs")).map { ($0.name, Stylesheets.quoted(try XMLCommands.text($0.value))) }
		// libxslt removes the blank text that `xsl:strip-space` names from the document it's given, which made the
		// script's references to those nodes invalid: such a stylesheet transforms a copy.
		let source = Stylesheets.stripsSpace(style.pointer) ? Stylesheets.copy(doc) : doc
		defer { if source != doc { xmlFreeDoc(source) } }
		let (outcome, _) = XMLIssues.collect { () -> (result: (output: xmlDocPtr?, refused: Bool), refused: [String]) in
			guard style.chosenByDocument else {
				return (Stylesheets.apply(style.pointer, to: source, parameters: parameters), [])
			}
			return LoadRestrictions.restricted(toFolders: Stylesheets.folders(of: document)) {
				Stylesheets.apply(style.pointer, to: source, parameters: parameters, trusted: false)
			}
		}
		let (applied, refusedLoads) = (outcome.result, outcome.refused)
		guard !applied.refused, refusedLoads.isEmpty else {
			if let output = applied.output { xmlFreeDoc(output) }
			throw Stylesheets.refusal(refusedLoads.first)
		}
		guard let output = applied.output else { throw XPath.failed }

		if let file = try request.parameter("kfil", as: URL.self) {
			defer { xmlFreeDoc(output) }
			var memory: UnsafeMutablePointer<xmlChar>?
			var length: Int32 = 0
			guard Output.withIndentString(settings.indentString, { xsltSaveResultToString(&memory, &length, output, style.pointer) }) >= 0 else {
				throw OSAXError(1524)
			}
			defer { xmlRelease(memory) }
			do {
				try Data(memory.map { UnsafeBufferPointer(start: $0, count: Int(length)) } ?? UnsafeBufferPointer(start: nil, count: 0))
					.writeReplacing(file)
			} catch {
				throw OSAXError(1524)
			}
			return nil
		}
		switch request.descriptor(for: "rtyp")?.typeCodeValue.fourCharString {
		case "TEXT", "utxt", "ctxt", "ut16", "utf8":
			defer { xmlFreeDoc(output) }
			if let method = style.pointer.pointee.method, String(cString: method) == "text" {
				var memory: UnsafeMutablePointer<xmlChar>?
				var length: Int32 = 0
				_ = Output.withIndentString(settings.indentString) { xsltSaveResultToString(&memory, &length, output, style.pointer) }
				defer { xmlRelease(memory) }
				return NSAppleEventDescriptor(string: memory.map { String(decoding: UnsafeBufferPointer(start: $0, count: Int(length)), as: UTF8.self) } ?? "")
			}
			var options = Output.Options()
			options.indent = settings.indentString
			return NSAppleEventDescriptor(string: try Output.xml(UnsafeMutableRawPointer(output).assumingMemoryBound(to: xmlNode.self), options: options))
		case "CFob":
			defer { xmlFreeDoc(output) }
			var options = Output.Options()
			options.indent = settings.indentString
			let data = try Output.serialize(UnsafeMutableRawPointer(output).assumingMemoryBound(to: xmlNode.self), options: options)
			return try PropertyLists.open(data, pool: request.parameter("pool", as: String.self), store: store)
		default:
			let result = store.add(pool: try request.parameter("pool", as: String.self)) { XMLDocument(number: $0, pool: $1, doc: output) }
			return references.reference(result)
		}
	}

	/// The stylesheet, and whether it's this command's to free. A node to transform gets a stylesheet of its own,
	/// with a template for the root that applies the templates to the node.
	func stylesheet(_ request: AppleEventRequest, document: XMLDocument, node: xmlNodePtr?) throws
		-> (pointer: xsltStylesheetPtr, owned: Bool, chosenByDocument: Bool)
	{
		guard let with = request.descriptor(for: "with") else {
			guard let doc = document.doc else { throw XML.noSuchNode }
			let ((style, refused), _) = XMLIssues.collect {
				LoadRestrictions.restricted(toFolders: Stylesheets.folders(of: document)) { xsltLoadStylesheetPI(doc) }
			}
			guard refused.isEmpty else {
				if let style { xsltFreeStylesheet(style) }
				throw Stylesheets.refusal(refused.first)
			}
			guard let style else { throw OSAXError.missingParameter }
			return (style, true, true)
		}
		let source: xmlDocPtr
		if XMLReferences.isReference(with) {
			let styleDocument = try resolve(with).0
			if node == nil, let compiled = styleDocument.stylesheet {
				return (compiled, false, false)
			}
			guard let doc = styleDocument.doc else { throw XML.noSuchNode }
			source = Stylesheets.copy(doc)
		} else {
			source = try Stylesheets.read(with)
		}
		if let node {
			Stylesheets.addRootTemplate(source, applyingTo: node)
		}
		return (try Stylesheets.compile(source), true, false)
	}
}

@MainActor
enum Stylesheets {
	/// libxslt's parsing options for stylesheets.
	static let parseOptions = Int32(XML_PARSE_NOENT.rawValue | XML_PARSE_DTDLOAD.rawValue | XML_PARSE_DTDATTR.rawValue | XML_PARSE_NOCDATA.rawValue)
	static let namespace = "http://www.w3.org/1999/XSL/Transform"

	/// EXSLT's functions and elements, for every stylesheet (registering is global and done once, when the commands
	/// are made: XMLCompile needs them too, or `func:function` definitions are missed).
	static func registerEXSLT() {
		_ = registration
	}

	private static let registration: Void = exsltRegisterAll()

	/// Whether a stylesheet, or one it imports, strips blank text (`xsl:strip-space`).
	static func stripsSpace(_ style: xsltStylesheetPtr) -> Bool {
		if style.pointee.stripSpaces != nil || style.pointee.stripAll != 0 {
			return true
		}
		var imported = style.pointee.imports
		while let current = imported {
			if stripsSpace(current) {
				return true
			}
			imported = current.pointee.next
		}
		return false
	}

	/// A copy of a document (to compile, since libxslt keeps the document it compiles, or to transform). Like any
	/// libxml2 copy, it has none of MTC_OSAX's node numbers.
	static func copy(_ doc: xmlDocPtr) -> xmlDocPtr {
		xmlCopyDoc(doc, 1)!
	}

	/// Compiles (and takes) a document; error 3 if it isn't a stylesheet.
	static func compile(_ doc: xmlDocPtr) throws -> xsltStylesheetPtr {
		let (style, _) = XMLIssues.collect { xsltParseStylesheetDoc(doc) }
		guard let style else {
			xmlFreeDoc(doc)
			throw XPath.failed
		}
		return style
	}

	/// A stylesheet's document from XSLT text, an http(s) URL, or a file (a path, file URL, alias or file
	/// reference; error 4 if it can't be read).
	static func read(_ descriptor: NSAppleEventDescriptor) throws -> xmlDocPtr {
		let isText = [typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType)
		let text = isText ? try XMLCommands.text(descriptor) : nil
		var url: URL?
		let data: Data
		if let text, text.drop(while: \.isWhitespace).hasPrefix("<") {
			data = Data(text.utf8)
		} else {
			if let text {
				// An http(s) URL, or a path as scripts give them (POSIX, `~`, a file URL, HFS); anything else is
				// relative to the working folder. (The path used to be rebuilt from the text, so `~` was a folder.)
				url = (try? Network.location(descriptor)) ?? URL(fileURLWithPath: text)
			} else {
				url = try URL(appleEventDescriptor: descriptor)
			}
			guard let url else { throw OSAXError(4) }
			if url.isFileURL {
				guard let contents = try? Data(contentsOf: url) else { throw OSAXError(4) }
				data = contents
			} else {
				data = try Network.fetch(url, post: false, query: nil, headers: nil)
			}
		}
		let length = try Int32(length: data.count)
		let (doc, issues) = XMLIssues.collect { () -> xmlDocPtr? in
			data.withUnsafeBytes { bytes in
				xmlReadMemory(bytes.baseAddress!.assumingMemoryBound(to: CChar.self), length, url?.absoluteString, nil, parseOptions)
			}
		}
		guard let doc else { throw OSAXError(issues.first?.code ?? 4) }
		return doc
	}

	/// Adds to a stylesheet a template for the root, ahead of any other, that applies the templates to `node`
	/// (found by its path), so a transformation of the document transforms the node.
	static func addRootTemplate(_ doc: xmlDocPtr, applyingTo node: xmlNodePtr) {
		guard let root = xmlDocGetRootElement(doc), let ns = root.pointee.ns, let href = ns.pointee.href,
		      String(cString: href) == namespace
		else { return }
		let path = templatePath(to: node)
		withXMLString("template") { name in
			let template = xmlNewDocNode(doc, ns, name, nil)
			withXMLString("match") { a in withXMLString("/") { _ = xmlSetProp(template, a, $0) } }
			withXMLString("priority") { a in withXMLString("1000000") { _ = xmlSetProp(template, a, $0) } }
			let apply = withXMLString("apply-templates") { xmlNewChild(template, ns, $0, nil) }
			withXMLString("select") { a in withXMLString(path) { _ = xmlSetProp(apply, a, $0) } }
			xmlAddChild(root, template)
		}
	}

	/// A node's path for the root template. It's evaluated after `xsl:strip-space` has taken blank text out, and
	/// in the stylesheet's namespaces, so (unlike `XMLGetNodePath`'s) it counts nothing stripping removes and uses no
	/// prefixes: `text()[n]` could name another node after stripping, and `@p:name` failed without `p` declared.
	static func templatePath(to node: xmlNodePtr) -> String {
		func isBlank(_ text: xmlNodePtr) -> Bool {
			Parsing.text(text).allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
		}
		func position(of node: xmlNodePtr, among matches: (xmlNodePtr) -> Bool) -> Int {
			var index = 1
			var sibling = node.pointee.prev
			while let current = sibling {
				if matches(current) { index += 1 }
				sibling = current.pointee.prev
			}
			return index
		}
		func quoted(_ text: String) -> String { Stylesheets.quoted(text) }
		var steps: [String] = []
		var current: xmlNodePtr? = node
		while let node = current, !XMLCommands.isDocument(node) {
			let type = node.pointee.type
			let isText = { (other: xmlNodePtr) in [XML_TEXT_NODE, XML_CDATA_SECTION_NODE].contains(other.pointee.type) }
			switch type {
			case XML_ATTRIBUTE_NODE:
				let uri = XMLCommands.namespace(of: node)?.pointee.href.map { String(cString: $0) } ?? ""
				steps.insert("@*[local-name()=\(quoted(Parsing.name(node))) and namespace-uri()=\(quoted(uri))]", at: 0)
			case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
				// Stripping takes out all of an element's blank text or none, so blank text that's still there
				// is where it was, and other text is counted among other text.
				steps.insert(isBlank(node)
					? "text()[\(position(of: node, among: isText))]"
					: "text()[normalize-space()][\(position(of: node) { isText($0) && !isBlank($0) })]", at: 0)
			case XML_COMMENT_NODE:
				steps.insert("comment()[\(position(of: node) { $0.pointee.type == XML_COMMENT_NODE })]", at: 0)
			case XML_PI_NODE:
				steps.insert("processing-instruction()[\(position(of: node) { $0.pointee.type == XML_PI_NODE })]", at: 0)
			default:
				steps.insert("*[\(position(of: node, among: XMLCommands.isElement))]", at: 0)
			}
			current = node.pointee.parent
		}
		return "/" + steps.joined(separator: "/")
	}

	/// The folders a stylesheet the document chooses may load from: the document's (none for a document that isn't
	/// a file, such as one opened from text).
	static func folders(of document: XMLDocument) -> [URL] {
		guard let url = document.url, url.isFileURL else { return [] }
		return [url.deletingLastPathComponent()]
	}

	/// Error 1535 for what a stylesheet the document chose may not do: load from `location`, or (without one) write
	/// or use the network.
	static func refusal(_ location: String?) -> OSAXError {
		let start = "A stylesheet chosen by the document’s xml-stylesheet instruction"
		guard let location else { return OSAXError(1535, "\(start) can’t write files or use the network.") }
		return OSAXError(1535, "\(start) can only load files from the document’s folder, and nothing from the network: \(location)")
	}

	/// Applies a stylesheet with parameters (XPath expressions). An untrusted one (chosen by the document) can't write
	/// or use the network: what it tries is refused, and `refused` says so.
	static func apply(_ style: xsltStylesheetPtr, to doc: xmlDocPtr, parameters: [(String, String)], trusted: Bool = true)
		-> (output: xmlDocPtr?, refused: Bool)
	{
		guard let context = xsltNewTransformContext(style, doc) else { return (nil, false) }
		defer { xsltFreeTransformContext(context) }
		let prefs = trusted ? nil : xsltNewSecurityPrefs()
		defer { if let prefs { xsltFreeSecurityPrefs(prefs) } }
		if let prefs {
			for option in [XSLT_SECPREF_WRITE_FILE, XSLT_SECPREF_CREATE_DIRECTORY, XSLT_SECPREF_WRITE_NETWORK, XSLT_SECPREF_READ_NETWORK] {
				xsltSetSecurityPrefs(prefs, option, refuse)
			}
			xsltSetCtxtSecurityPrefs(prefs, context)
		}
		var refused = false
		var strings: [UnsafeMutablePointer<CChar>?] = parameters.flatMap { [strdup($0.0), strdup($0.1)] }
		defer { strings.forEach { free($0) } }
		strings.append(nil)
		let output = withUnsafeMutablePointer(to: &refused) { flag in
			// The refusal callback finds the flag through the context.
			context.pointee._private = UnsafeMutableRawPointer(flag)
			defer { context.pointee._private = nil }
			return strings.withUnsafeMutableBufferPointer { buffer in
				buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
					xsltApplyStylesheetUser(style, doc, $0, nil, nil, context)
				}
			}
		}
		return (output, refused)
	}

	/// libxslt's security check that says no, noting it in the flag `apply` put in the context.
	private static let refuse: xsltSecurityCheck = { _, context, _ in
		context?.pointee._private?.assumingMemoryBound(to: Bool.self).pointee = true
		return 0
	}

	/// Text as an XPath string literal.
	static func quoted(_ text: String) -> String {
		if !text.contains("'") { return "'\(text)'" }
		if !text.contains("\"") { return "\"\(text)\"" }
		return "concat('" + text.components(separatedBy: "'").joined(separator: "', \"'\", '") + "')"
	}
}
