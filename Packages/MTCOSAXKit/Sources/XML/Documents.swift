import AppleEventCore
import CLibXML
import Foundation
import PropertyLists

/// An open XML document: a libxml2 tree, where it came from, and its pool.
///
/// Scripts refer to nodes by number (in XMLRefs). A node gets a number the first time a reference to it is made,
/// kept in the node's `_private` field; when libxml2 frees a node (however it was removed), the deregistration
/// callback forgets its number, so later references give an error instead of reaching freed memory. libxml2's
/// copies (`xmlCopyDoc`, `xmlDocCopyNode`) don't copy `_private`, so a copy starts without numbers.
final class XMLDocument: StoredDocument {
	let number: Int
	var pool: String
	private(set) var doc: xmlDocPtr?
	var url: URL?
	var identifier: String?
	/// `XMLSetExtras`: any value a script keeps with the document.
	var extras: NSAppleEventDescriptor?
	var isModified = false
	/// `XMLSetContext`: namespaces and variables for this document's XPath expressions, in the order they were set.
	var namespaces: [(prefix: String, uri: String)] = []
	var variables: [(name: String, value: NSAppleEventDescriptor)] = []
	/// `XMLCompile`: the document compiled as a stylesheet, used when it's `XMLTransform`'s stylesheet.
	var stylesheet: xsltStylesheetPtr?
	/// `XMLNewIndex`: indexes by name.
	var indexes: [String: XMLIndex] = [:]
	fileprivate var nodes: [Int: xmlNodePtr] = [:]
	private var nextNode = 1

	init(number: Int, pool: String, doc: xmlDocPtr) {
		self.number = number
		self.pool = pool
		self.doc = doc
		doc.pointee._private = Unmanaged.passUnretained(self).toOpaque()
	}

	func didClose() {
		if let stylesheet {
			xsltFreeStylesheet(stylesheet)
			self.stylesheet = nil
		}
		guard let doc else { return }
		self.doc = nil
		doc.pointee._private = nil
		nodes.removeAll()
		xmlFreeDoc(doc)
	}

	var isHTML: Bool {
		doc?.pointee.type == XML_HTML_DOCUMENT_NODE
	}

	/// The node's number, giving it one if it has none. The document node is 0.
	func number(of node: xmlNodePtr) -> Int {
		if UnsafeMutableRawPointer(node) == UnsafeMutableRawPointer(doc) {
			return 0
		}
		precondition(node.pointee.doc == doc, "a node numbered in another document's table")
		if let existing = node.pointee._private {
			return Int(bitPattern: existing)
		}
		let number = nextNode
		nextNode += 1
		node.pointee._private = UnsafeMutableRawPointer(bitPattern: number)
		nodes[number] = node
		return number
	}

	func node(number: Int) -> xmlNodePtr? {
		if number == 0 {
			return doc.map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: xmlNode.self) }
		}
		return nodes[number]
	}

	/// The open document a node belongs to (nil for a copy, like a stylesheet's).
	static func owner(of node: xmlNodePtr) -> XMLDocument? {
		guard let doc = node.pointee.doc, let owner = doc.pointee._private else { return nil }
		return Unmanaged<XMLDocument>.fromOpaque(owner).takeUnretainedValue()
	}

	/// Forgets the numbers of nodes (and what's in them) that are about to be freed without libxml2's callback.
	static func forgetNumbers(in node: xmlNodePtr?) {
		Parsing.walk(node) { node in
			if let number = node.pointee._private, let document = owner(of: node) {
				document.nodes[Int(bitPattern: number)] = nil
				node.pointee._private = nil
			}
		}
	}

	// MARK: libxml2 callbacks

	/// libxml2's node callbacks are per thread: installs the one that forgets freed nodes on this thread.
	/// `xmlDeregisterNodeDefault` sets the default for threads (and turns the callbacks on); a thread whose libxml2
	/// state already exists has its own value, set directly.
	static func installCallbacks() {
		let key = "MTCXMLCallbacks"
		guard Thread.current.threadDictionary[key] == nil else { return }
		Thread.current.threadDictionary[key] = true
		let callback: xmlDeregisterNodeFunc = { node in
			guard let node, let number = node.pointee._private, let doc = node.pointee.doc,
			      UnsafeMutableRawPointer(node) != UnsafeMutableRawPointer(doc), let owner = doc.pointee._private
			else {
				return
			}
			let document = Unmanaged<XMLDocument>.fromOpaque(owner).takeUnretainedValue()
			document.nodes[Int(bitPattern: number)] = nil
		}
		_ = xmlDeregisterNodeDefault(callback)
		__xmlDeregisterNodeDefaultValue().pointee = callback
	}
}

// MARK: - References

/// XMLRefs (`XMLR`): a document's number, "MTCx", and a node's number (0 for the document).
@MainActor
struct XMLReferences {
	nonisolated static let type = FourCharCode(fourCharString: "XMLR")
	let store: DocumentStore

	func reference(_ node: xmlNodePtr, in document: XMLDocument) -> NSAppleEventDescriptor {
		// The document the node is in, whatever the caller thought: numbered in another's table, the number would
		// outlive the node there (only an assert checked, which release builds leave out).
		let isDocumentNode = UnsafeMutableRawPointer(node) == UnsafeMutableRawPointer(document.doc)
		let document = isDocumentNode ? document : XMLDocument.owner(of: node) ?? document
		var data = Data()
		withUnsafeBytes(of: UInt32(document.number).littleEndian) { data.append(contentsOf: $0) }
		data.append(contentsOf: Array("MTCx".utf8))
		withUnsafeBytes(of: UInt64(document.number(of: node)).littleEndian) { data.append(contentsOf: $0) }
		return NSAppleEventDescriptor(descriptorType: Self.type, data: data)!
	}

	/// The open XML document with that number.
	func document(number: Int) -> XMLDocument? {
		store.allDocuments.first { $0.number == number } as? XMLDocument
	}

	func reference(_ document: XMLDocument) -> NSAppleEventDescriptor {
		reference(document.node(number: 0)!, in: document)
	}

	nonisolated static func isReference(_ descriptor: NSAppleEventDescriptor) -> Bool {
		descriptor.descriptorType == type
	}

	/// The document and node an XMLRef refers to: -1700 if it isn't one, -1728 if the document was closed or the
	/// node removed.
	func resolve(_ descriptor: NSAppleEventDescriptor) throws -> (XMLDocument, xmlNodePtr) {
		guard Self.isReference(descriptor) else {
			throw OSAXError.coercionFailed
		}
		let data = descriptor.data
		guard data.count == 16, data[4 ..< 8] == Data("MTCx".utf8) else {
			throw XML.noSuchNode
		}
		let number = data[0 ..< 4].withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
		let nodeNumber = data[8 ..< 16].withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
		// A forged or corrupted number beyond Int's range is just a node that doesn't exist.
		guard let nodeNumber = Int(exactly: nodeNumber),
		      let document = store.allDocuments.first(where: { $0.number == number }) as? XMLDocument,
		      let node = document.node(number: nodeNumber)
		else {
			throw XML.noSuchNode
		}
		return (document, node)
	}

	/// The XML documents in the store.
	var documents: [XMLDocument] {
		store.allDocuments.compactMap { $0 as? XMLDocument }
	}
}

// MARK: - Errors

/// A libxml2 error or warning.
struct XMLIssue {
	var code: Int
	/// 1 warning, 2 error, 3 fatal (libxml2's levels).
	var level: Int
	var line: Int
	var file: String?
	var message: String
}

/// Collects libxml2's errors while a command runs, for its error number and for `XMLError`. libxml2's error
/// handler is per thread, so the collection is too.
enum XMLIssues {
	private final class Box {
		var issues: [XMLIssue] = []
		/// libxslt's text so far, which comes in pieces: each line is a problem.
		var xsltText = ""
	}

	private static var box: Box {
		let key = "MTCXMLIssues"
		if let box = Thread.current.threadDictionary[key] as? Box {
			return box
		}
		let box = Box()
		Thread.current.threadDictionary[key] = box
		installXSLTErrors()
		xmlSetStructuredErrorFunc(nil) { _, error in
			guard let error else { return }
			let message = error.pointee.message.map { String(cString: $0) } ?? ""
			XMLIssues.box.issues.append(XMLIssue(
				code: Int(error.pointee.code),
				level: Int(error.pointee.level.rawValue),
				line: Int(error.pointee.line),
				file: error.pointee.file.map { String(cString: $0) },
				message: message.trimmingCharacters(in: .newlines)
			))
		}
		return box
	}

	/// libxslt's errors (a stylesheet that doesn't compile, a failing transform) go into the same collection, one
	/// problem per line, so `XMLError` says what went wrong. Its callback is global, but it's called on the thread
	/// doing the work, whose collection it adds to.
	private static func installXSLTErrors() {
		_ = xsltInstallation
	}

	private static let xsltInstallation: Void = mtc_xslt_set_error_sink { text in
		guard let text else { return }
		let box = XMLIssues.box
		box.xsltText += String(cString: text)
		while let newline = box.xsltText.firstIndex(of: "\n") {
			addXSLTLine(String(box.xsltText[..<newline]), to: box)
			box.xsltText = String(box.xsltText[box.xsltText.index(after: newline)...])
		}
	}

	private static func addXSLTLine(_ line: String, to box: Box) {
		let message = line.trimmingCharacters(in: .whitespaces)
		if !message.isEmpty {
			box.issues.append(XMLIssue(code: 3, level: 2, line: 0, file: nil, message: message))
		}
	}

	/// Adds a problem of MTC_OSAX's own to the current collection, as a warning like libxml2's own "failed to load
	/// external entity" (1549).
	static func warn(_ message: String) {
		box.issues.append(XMLIssue(code: 1549, level: 1, line: 0, file: nil, message: message))
	}

	/// The text of the last collection on this thread, for `XMLError`.
	static var lastText: String {
		get { Thread.current.threadDictionary["MTCXMLIssuesText"] as? String ?? "" }
		set { Thread.current.threadDictionary["MTCXMLIssuesText"] = newValue }
	}

	/// Runs `body`, collecting libxml2's errors, and returns them with its result.
	static func collect<T>(_ body: () throws -> T) rethrows -> (T, [XMLIssue]) {
		let box = self.box
		box.issues = []
		box.xsltText = ""
		let result = try body()
		addXSLTLine(box.xsltText, to: box)
		box.xsltText = ""
		let issues = box.issues
		box.issues = []
		lastText = text(issues)
		return (result, issues)
	}

	/// SatimageOSAX's format: `show "file URL" selection <line>:` (or `line <line>` without a file), the message,
	/// and a blank line.
	static func text(_ issues: [XMLIssue]) -> String {
		issues.map { issue in
			if let file = issue.file, !file.isEmpty {
				return "show \"\(file)\" selection \(issue.line):\n\(issue.message)\n\n"
			}
			// Without a file or a line (a file that can't be loaded), only the message.
			return issue.line > 0 ? "line \(issue.line)\n\(issue.message)\n\n" : "\(issue.message)\n\n"
		}.joined()
	}
}
