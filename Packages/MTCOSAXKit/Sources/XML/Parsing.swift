import AppleEventCore
import CLibXML
import Foundation

/// The XML suites' settings, one set per app (per set of commands, so tests don't share them).
@MainActor
final class XMLSettings {
	/// `XMLErrorLevel`: which problems make parsing fail (1 warnings, 2 errors, 3 only fatal errors); 2 at launch.
	var errorLevel = 2
	/// `XMLExtendedChar`: whether XML 1.1's control characters (`&#1;` to `&#31;`) are allowed; true at launch.
	var extendedCharacters = true
	/// `XMLSetIndentString`: a tab at launch.
	var indentString = "\t"
}

/// The options of `XMLOpen` and the commands that parse fragments.
struct ParseOptions {
	var keepBlanks = false
	var loadExternalDTD = false
	var substituteEntities = false
	var validate = false
	var html = false
	var xmlScript = false
	var noCDATA = false
	var failureLevel = 2
	var extendedCharacters = true
	var bypassingNamespace = false
	var encoding: String?

	/// Without `XML_PARSE_HUGE` (as in SatimageOSAX), so libxml2's limits hold: 10 MB text nodes, nesting depth,
	/// and the check that stops entities expanding without end ("billion laughs").
	var libxmlOptions: Int32 {
		var options: UInt32 = 0
		if !keepBlanks { options |= XML_PARSE_NOBLANKS.rawValue }
		if loadExternalDTD { options |= XML_PARSE_DTDLOAD.rawValue }
		if substituteEntities { options |= XML_PARSE_NOENT.rawValue }
		if validate { options |= XML_PARSE_DTDVALID.rawValue }
		if noCDATA { options |= XML_PARSE_NOCDATA.rawValue }
		return Int32(options)
	}

	var htmlOptions: Int32 {
		var options = HTML_PARSE_RECOVER.rawValue
		if !keepBlanks { options |= HTML_PARSE_NOBLANKS.rawValue }
		return Int32(options)
	}
}

enum Parsing {
	/// Parses a document. Error: the first problem at or above the failure level (libxml2's error number), -1 for
	/// empty input.
	static func parse(_ data: Data, url: String?, options: ParseOptions) throws -> xmlDocPtr {
		guard !data.isEmpty else {
			throw OSAXError(-1)
		}
		let input = options.extendedCharacters ? ExtendedCharacters.encode(data) : data
		let length = try Int32(length: input.count)
		let (parsed, issues) = XMLIssues.collect { () -> xmlDocPtr? in
			input.withUnsafeBytes { bytes in
				let base = bytes.baseAddress!.assumingMemoryBound(to: CChar.self)
				if options.html {
					return htmlReadMemory(base, length, url, options.encoding, options.htmlOptions)
				}
				return xmlReadMemory(base, length, url, options.encoding, options.libxmlOptions)
			}
		}
		guard let doc = parsed else {
			throw OSAXError(issues.first?.code ?? -1)
		}
		// HTML is parsed leniently; XML fails on problems at or above the failure level.
		if !options.html, let failure = issues.first(where: { $0.level >= options.failureLevel }) {
			xmlFreeDoc(doc)
			throw OSAXError(failure.code)
		}
		if options.html, options.xmlScript {
			try checkScripts(doc)
		}
		if options.bypassingNamespace {
			removeDefaultNamespaces(xmlDocGetRootElement(doc))
		}
		if options.extendedCharacters {
			ExtendedCharacters.decode(xmlDocGetRootElement(doc))
		}
		return doc
	}

	/// `xmlscript`: the contents of HTML script elements must be well-formed XML.
	private static func checkScripts(_ doc: xmlDocPtr) throws {
		var failure: Int?
		walk(xmlDocGetRootElement(doc)) { node in
			guard failure == nil, node.pointee.type == XML_ELEMENT_NODE, name(node).lowercased() == "script" else { return }
			let content = text(node)
			let wrapped = Data("<script>\(content)</script>".utf8)
			// A script can't be longer than the document it came from, which was under 2 GB.
			let (parsed, issues) = XMLIssues.collect { () -> xmlDocPtr? in
				wrapped.withUnsafeBytes { xmlReadMemory($0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(clamping: $0.count), nil, "UTF-8", 0) }
			}
			if let parsed { xmlFreeDoc(parsed) }
			if let issue = issues.first(where: { $0.level >= 2 }) {
				failure = issue.code
			}
		}
		if let failure {
			xmlFreeDoc(doc)
			throw OSAXError(failure)
		}
	}

	/// `bypassing namespace`: removes default namespace declarations, and the default namespace from elements.
	/// The declarations are freed only after the whole walk, since descendants visited later still point at them.
	private static func removeDefaultNamespaces(_ root: xmlNodePtr?) {
		var removed: [xmlNsPtr] = []
		defer { removed.forEach { xmlFreeNs($0) } }
		walk(root) { node in
			guard node.pointee.type == XML_ELEMENT_NODE else { return }
			if let ns = node.pointee.ns, ns.pointee.prefix == nil {
				node.pointee.ns = nil
			}
			var previous: xmlNsPtr?
			var current = node.pointee.nsDef
			while let ns = current {
				let next = ns.pointee.next
				if ns.pointee.prefix == nil {
					if let previous { previous.pointee.next = next } else { node.pointee.nsDef = next }
					ns.pointee.next = nil
					removed.append(ns)
				} else {
					previous = ns
				}
				current = next
			}
		}
	}

	/// Parses a fragment (`XMLNewChild`, `XMLSetXML`) in the context of `parent`, so its namespace prefixes resolve;
	/// the nodes aren't attached. Error: libxml2's error number.
	static func fragment(_ text: String, in parent: xmlNodePtr, keepBlanks: Bool) throws -> [xmlNodePtr] {
		let data = Data(text.utf8)
		let length = try Int32(length: data.count)
		var list: xmlNodePtr?
		let (status, issues) = XMLIssues.collect { () -> xmlParserErrors in
			data.withUnsafeBytes { bytes in
				xmlParseInNodeContext(parent, bytes.baseAddress!.assumingMemoryBound(to: CChar.self), length,
				                      Int32(keepBlanks ? 0 : Int(XML_PARSE_NOBLANKS.rawValue)), &list)
			}
		}
		guard status == XML_ERR_OK else {
			xmlFreeNodeList(list)
			throw OSAXError(issues.first?.code ?? Int(status.rawValue))
		}
		var nodes: [xmlNodePtr] = []
		var current = list
		while let node = current {
			current = node.pointee.next
			node.pointee.next = nil
			node.pointee.prev = nil
			node.pointee.parent = nil
			nodes.append(node)
		}
		return nodes
	}

	// MARK: Tree helpers

	/// Visits a node, what's in it and the siblings after it, depth first. It doesn't go into an entity reference or
	/// a DTD, as libxml2's own walks don't: their children are declarations, not content. (An entity reference's
	/// child is its entity's declaration, whose siblings are the rest of the DTD, so the walk used to visit the
	/// whole DTD, and went round in circles when an entity referred to one declared before it.)
	static func walk(_ node: xmlNodePtr?, _ visit: (xmlNodePtr) -> Void) {
		var current = node
		while let node = current {
			visit(node)
			if node.pointee.type != XML_ENTITY_REF_NODE, node.pointee.type != XML_DTD_NODE {
				walk(node.pointee.children, visit)
			}
			current = node.pointee.next
		}
	}

	static func name(_ node: xmlNodePtr) -> String {
		node.pointee.name.map { String(cString: $0) } ?? ""
	}

	/// libxml2's text content of a node (text of all its descendants, entities resolved).
	static func text(_ node: xmlNodePtr) -> String {
		guard let content = xmlNodeGetContent(node) else { return "" }
		defer { xmlRelease(content) }
		return String(cString: content)
	}

	static func string(_ pointer: UnsafeMutablePointer<xmlChar>?) -> String? {
		guard let pointer else { return nil }
		defer { xmlRelease(pointer) }
		return String(cString: pointer)
	}
}

/// XML 1.1's control characters (`XMLExtendedChar`), which libxml2 rejects: character references to them are
/// replaced before parsing by private characters (U+10FF01 to U+10FF1F), turned back into the control characters
/// in the tree afterwards.
enum ExtendedCharacters {
	private static let reference = try! NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);")

	/// Markup whose content is literal, so `&#1;` in it is text rather than a character reference.
	private static let literalMarkup = [(open: "<!--", close: "-->"), (open: "<![CDATA[", close: "]]>"), (open: "<?", close: "?>")]

	/// Rewrites references to control characters in text and attribute values (not in comments, CDATA sections
	/// or processing instructions, where they're literal text).
	static func encode(_ data: Data) -> Data {
		guard data.firstRange(of: Data("&#".utf8)) != nil, let text = String(data: data, encoding: .utf8) else {
			return data
		}
		var result = ""
		var changed = false
		var segment = text.startIndex
		var index = text.startIndex
		while let open = text[index...].firstIndex(of: "<") {
			guard let markup = literalMarkup.first(where: { text[open...].hasPrefix($0.open) }) else {
				index = text.index(after: open)
				continue
			}
			changed = rewrite(text[segment ..< open], into: &result) || changed
			let content = text.index(open, offsetBy: markup.open.count)
			let end = text[content...].range(of: markup.close)?.upperBound ?? text.endIndex
			result += text[open ..< end]
			segment = end
			index = end
		}
		changed = rewrite(text[segment...], into: &result) || changed
		return changed ? Data(result.utf8) : data
	}

	/// Appends `text` with its control character references rewritten; whether there were any.
	private static func rewrite(_ text: Substring, into result: inout String) -> Bool {
		let string = String(text)
		var last = string.startIndex
		for match in reference.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
			let range = Range(match.range, in: string)!
			let digits = string[Range(match.range(at: 1), in: string)!]
			let value = digits.hasPrefix("x") ? Int(digits.dropFirst(), radix: 16) : Int(digits)
			guard let value, (1 ... 31).contains(value), ![9, 10, 13].contains(value) else { continue }
			result += string[last ..< range.lowerBound] + String(format: "&#x10FF%02X;", value)
			last = range.upperBound
		}
		result += string[last...]
		return last != string.startIndex
	}

	/// Turns the private characters back into control characters, in text and in attribute values.
	static func decode(_ root: xmlNodePtr?) {
		Parsing.walk(root) { node in
			if node.pointee.type == XML_TEXT_NODE || node.pointee.type == XML_CDATA_SECTION_NODE {
				decodeContent(node)
			}
			var attribute = node.pointee.type == XML_ELEMENT_NODE ? node.pointee.properties : nil
			while let current = attribute {
				var child = current.pointee.children
				while let text = child {
					// Not an entity reference: its content is the entity's own, which setting it would free.
					if text.pointee.type == XML_TEXT_NODE {
						XMLCommands.changingValue(of: text) { decodeContent(text) }
					}
					child = text.pointee.next
				}
				attribute = current.pointee.next
			}
		}
	}

	private static func decodeContent(_ node: xmlNodePtr) {
		guard let content = node.pointee.content else { return }
		let text = String(cString: content)
		guard text.unicodeScalars.contains(where: { (0x10FF01 ... 0x10FF1F).contains($0.value) }) else { return }
		let decoded = String(String.UnicodeScalarView(text.unicodeScalars.map {
			(0x10FF01 ... 0x10FF1F).contains($0.value) ? Unicode.Scalar($0.value - 0x10FF00)! : $0
		}))
		withXMLString(decoded) { xmlNodeSetContent(node, $0) }
	}
}

/// A Swift string as libxml2's `const xmlChar *`.
func withXMLString<T>(_ string: String, _ body: (UnsafePointer<xmlChar>) throws -> T) rethrows -> T {
	try string.withCString { try body(UnsafeRawPointer($0).assumingMemoryBound(to: xmlChar.self)) }
}

func withOptionalXMLString<T>(_ string: String?, _ body: (UnsafePointer<xmlChar>?) throws -> T) rethrows -> T {
	guard let string else { return try body(nil) }
	return try withXMLString(string, body)
}

/// Frees memory libxml2 allocated. libxml2's `xmlFree` is a global function pointer, which is the C library's
/// `free` unless an app replaces libxml2's allocator (MTC_OSAX doesn't).
func xmlRelease(_ pointer: UnsafeMutableRawPointer?) {
	free(pointer)
}

func xmlRelease<T>(_ pointer: UnsafeMutablePointer<T>?) {
	free(pointer)
}
