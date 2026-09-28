import AppleEventCore
import CLibXML
import CommonCrypto
import CryptoKit
import Foundation

/// Writing XML: `XMLDisplayXML`, `XMLSave` and `XMLc14n`.
enum Output {
	struct Options {
		var formatting = true
		var declaration = true
		var nsclean = true
		var html = false
		var encoding: String?
		var indent = "\t"
	}

	/// A node as XML text, as SatimageOSAX wrote it. Documents end with a newline and have an XML declaration
	/// unless asked not to; an element gets the namespace declarations it needs (`nsclean`); a text node is its
	/// text; `encoding` changes the declaration and escapes characters it can't hold.
	static func xml(_ node: xmlNodePtr, options: Options) throws -> String {
		let type = node.pointee.type
		if type == XML_TEXT_NODE || type == XML_CDATA_SECTION_NODE {
			return Parsing.text(node)
		}
		let bytes = try serialize(node, options: options)
		let name = options.encoding ?? node.pointee.doc?.pointee.encoding.map { String(cString: $0) }
		let encoding = name.flatMap(stringEncoding) ?? .utf8
		return String(data: bytes, encoding: encoding) ?? String(decoding: bytes, as: UTF8.self)
	}

	/// The bytes of a node in its (or the given) encoding; -50 for an encoding libxml2 doesn't know (it used to give
	/// nothing, and `XMLSave` wrote an empty file).
	static func serialize(_ node: xmlNodePtr, options: Options) throws -> Data {
		try withIndentString(options.indent) {
			let isDocument = node.pointee.type == XML_DOCUMENT_NODE || node.pointee.type == XML_HTML_DOCUMENT_NODE
			// An HTML document as HTML: libxml2's HTML writer (named entities, no added <meta>), as SatimageOSAX wrote it.
			if isDocument, options.html, node.pointee.type == XML_HTML_DOCUMENT_NODE {
				let doc = UnsafeMutableRawPointer(node).assumingMemoryBound(to: xmlDoc.self)
				var memory: UnsafeMutablePointer<xmlChar>?
				var size: Int32 = 0
				htmlDocDumpMemoryFormat(doc, &memory, &size, options.formatting ? 1 : 0)
				defer { xmlRelease(memory) }
				return memory.map { Data(bytes: $0, count: Int(size)) } ?? Data()
			}
			let buffer = xmlBufferCreate()
			defer { xmlBufferFree(buffer) }
			var saveOptions: Int32 = 0
			if options.formatting { saveOptions |= Int32(XML_SAVE_FORMAT.rawValue) }
			// Any other document as HTML: HTML syntax, in UTF-8.
			if isDocument, options.html { saveOptions |= Int32(XML_SAVE_AS_HTML.rawValue) }
			if !options.declaration { saveOptions |= Int32(XML_SAVE_NO_DECL.rawValue) }
			// A document without an encoding is written as UTF-8, with the encoding in its declaration.
			let doc = node.pointee.doc
			let encoding = options.encoding ?? doc?.pointee.encoding.map { String(cString: $0) } ?? "UTF-8"
			guard let context = xmlSaveToBuffer(buffer, encoding, saveOptions) else {
				throw OSAXError(-50, "“\(encoding)” isn’t an encoding MTC_OSAX knows.")
			}
			if isDocument {
				xmlSaveDoc(context, UnsafeMutableRawPointer(node).assumingMemoryBound(to: xmlDoc.self))
			} else if options.nsclean, node.pointee.type == XML_ELEMENT_NODE {
				// A copy in a document of its own: copying declares on it the namespaces it uses from its ancestors.
				let scratch = xmlNewDoc(nil)
				defer { xmlFreeDoc(scratch) }
				let copy = xmlDocCopyNode(node, scratch, 1)
				xmlDocSetRootElement(scratch, copy)
				XMLDocument.clearNumbers(copy)
				xmlSaveTree(context, copy)
				xmlSaveClose(context)
				return Data(bytes: xmlBufferContent(buffer), count: Int(xmlBufferLength(buffer)))
			} else {
				xmlSaveTree(context, node)
			}
			xmlSaveClose(context)
			return Data(bytes: xmlBufferContent(buffer), count: Int(xmlBufferLength(buffer)))
		}
	}

	/// Runs `body` with libxml2's indent string set to `XMLSetIndentString`'s (a tab by default).
	static func withIndentString<T>(_ indent: String, _ body: () throws -> T) rethrows -> T {
		let pointer = __xmlTreeIndentString()!
		let previous = pointer.pointee
		let copy = strdup(indent)!
		pointer.pointee = UnsafePointer(copy)
		defer {
			pointer.pointee = previous
			free(copy)
		}
		return try body()
	}

	static func stringEncoding(_ name: String) -> String.Encoding? {
		let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
		guard encoding != kCFStringEncodingInvalidId else { return nil }
		return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
	}

	// MARK: Canonicalization

	/// Canonical XML of a document: with or without comments, exclusive (with `inclusive prefixes`) or not; or its
	/// SHA1 or MD5 digest (base64 unless written to a file). Other digests are -1.
	static func canonical(_ doc: xmlDocPtr, nodes: xmlNodeSetPtr? = nil, comments: Bool, exclusive: Bool, prefixes: [String],
	                      digest: String?) throws -> Data
	{
		var memory: UnsafeMutablePointer<xmlChar>?
		let mode = Int32(exclusive ? XML_C14N_EXCLUSIVE_1_0.rawValue : XML_C14N_1_0.rawValue)
		var cStrings = prefixes.map { strdup($0) }
		defer { cStrings.forEach { free($0) } }
		cStrings.append(nil)
		let size = cStrings.withUnsafeMutableBufferPointer { buffer -> Int32 in
			let list = exclusive && prefixes.count > 0
				? UnsafeMutableRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UnsafeMutablePointer<xmlChar>?.self) : nil
			return xmlC14NDocDumpMemory(doc, nodes, mode, list, comments ? 1 : 0, &memory)
		}
		guard size >= 0, let memory else {
			throw OSAXError(-1)
		}
		defer { xmlRelease(memory) }
		let data = Data(bytes: memory, count: Int(size))
		guard let digest else {
			return data
		}
		switch digest.uppercased() {
		case "SHA1":
			var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
			data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash) }
			return Data(hash)
		case "MD5":
			// CryptoKit's MD5: CommonCrypto's is deprecated.
			return Data(Insecure.MD5.hash(data: data))
		default:
			throw OSAXError(-1)
		}
	}
}
