import AppleEventCore
import CLibXML
import Foundation
import PropertyLists

/// The "XML Documents" suite.
extension XMLCommands {
	var documents: [CommandDefinition] {
		[
			CommandDefinition("XMLURL", code: "XML gurl") { request in
				guard var url = try direct(request).0.url else { throw XML.notFound }
				let parent = try request.parameter("pare", default: false)
				if parent { url = url.deletingLastPathComponent() }
				switch request.descriptor(for: "rtyp")?.typeCodeValue.fourCharString {
				case "alis":
					guard let alias = NSAppleEventDescriptor.alias(url) else { throw OSAXError(-43) }
					return alias
				case "utxt", "TEXT", "ctxt":
					return NSAppleEventDescriptor(string: url.isFileURL ? URL(fileURLWithPath: url.path, isDirectory: parent).absoluteString : url.absoluteString)
				default:
					return NSAppleEventDescriptor(string: url.isFileURL ? url.path + (parent ? "/" : "") : url.absoluteString)
				}
			},
			CommandDefinition("XMLSetURL", code: "XML sURL") { request in
				let (document, _) = try direct(request)
				document.url = try request.requiredParameter("to  ", as: URL.self)
				return nil
			},
			CommandDefinition("XMLDocument", code: "XML gfur") { request in
				// The open documents of a file in the pool: one, or a list when it was opened more than once.
				let file = try request.requiredDirectParameter(as: URL.self)
				let pool = try request.parameter("pool", as: String.self) ?? store.currentPool
				let found = references.documents.filter { document in
					document.pool == pool && document.url.map { $0.isFileURL && XMLCommands.sameLocation($0, file) } == true
				}
				guard !found.isEmpty else { throw XML.notFound }
				let result = found.map { references.reference($0) }
				return found.count == 1 ? result[0] : result.appleEventDescriptor
			},
			CommandDefinition("XMLCatalog", code: "XML cata") { request in
				let id = try request.requiredDirectParameter(as: String.self)
				let resolved = withXMLString(id) { value in
					Parsing.string(xmlCatalogResolvePublic(value)) ?? Parsing.string(xmlCatalogResolveSystem(value))
						?? Parsing.string(xmlCatalogResolveURI(value))
				}
				guard let resolved else { throw XML.notFound }
				return resolved
			},
			CommandDefinition("XMLCloneDocument", code: "XML cdoc") { request in
				let (document, _) = try direct(request)
				guard let copy = xmlCopyDoc(document.doc, 1) else { throw XML.invalid }
				let clone = store.add(pool: try request.parameter("pool", as: String.self)) { XMLDocument(number: $0, pool: $1, doc: copy) }
				return references.reference(clone)
			},
			// Includes can read local files (relative to the document, or anywhere with a file: URL) but not the
			// network: a document from elsewhere could otherwise make the Mac fetch any URL. `XML_PARSE_NONET` alone
			// doesn't do it: libxml2 applies it only to http, and not to text includes.
			CommandDefinition("XMLXInclude", code: "XML Xinc") { request in
				let (document, _) = try direct(request)
				let ((count, refused), issues) = XMLIssues.collect {
					LoadRestrictions.restricted(toFolders: nil) { xmlXIncludeProcessFlags(document.doc, Int32(XML_PARSE_NONET.rawValue)) }
				}
				// libxml2 makes a text include it couldn't load empty text, and keeps includes done before one that
				// failed.
				if count > 0 { modified(document) }
				if let url = refused.first { throw OSAXError(1549, "A document can’t include anything from the network: \(url)") }
				guard count >= 0 else { throw OSAXError(issues.first?.code ?? -1) }
				return Int(count)
			},
			CommandDefinition("XMLGetEncoding", code: "XML genc") { request in
				let (document, _) = try direct(request)
				let name = document.doc?.pointee.encoding.map { String(cString: $0) } ?? "UTF-8"
				return NSAppleEventDescriptor(descriptorType: typeChar, data: Data(name.utf8))!
			},
			CommandDefinition("XMLSetEncoding", code: "XML senc") { request in
				let (document, _) = try direct(request)
				let name = try request.requiredParameter("to  ", as: String.self)
				// The handler is only to check the name; an iconv one is made for each lookup and has to be closed.
				guard let handler = xmlFindCharEncodingHandler(name) else { throw OSAXError.parameterError }
				xmlCharEncCloseFunc(handler)
				guard let doc = document.doc else { throw OSAXError.parameterError }
				if let old = doc.pointee.encoding { xmlRelease(UnsafeMutableRawPointer(mutating: old)) }
				doc.pointee.encoding = withXMLString(name) { UnsafePointer(xmlStrdup($0)) }
				modified(document)
				return nil
			},
			CommandDefinition("XMLSetIndentString", code: "XML Indt") { request in
				let previous = settings.indentString
				settings.indentString = try request.requiredDirectParameter(as: String.self)
				return previous
			},
			CommandDefinition("XMLSave", code: "XML save", handler: save),
			CommandDefinition("XMLErrorLevel", code: "XML ErLe") { request in
				let previous = settings.errorLevel
				if let level = try request.directParameter(as: Int.self) {
					settings.errorLevel = level
				}
				return previous
			},
			CommandDefinition("XMLExtendedChar", code: "XML Vr11") { request in
				let previous = settings.extendedCharacters
				if let extended = try request.directParameter(as: Bool.self) {
					settings.extendedCharacters = extended
				}
				return previous
			},
			CommandDefinition("XMLListDocuments", code: "XML List") { request in
				let pool = try request.directParameter(as: String.self) ?? store.currentPool
				let found = references.documents.filter { $0.pool == pool }
				if request.descriptor(for: "as  ") != nil {
					return found.map { $0.url?.absoluteString ?? "" }.appleEventDescriptor
				}
				return found.map { references.reference($0) }.appleEventDescriptor
			},
			CommandDefinition("XMLSetDocID", code: "XML SDbK") { request in
				let (document, _) = try direct(request)
				let previous = document.identifier
				document.identifier = try request.requiredParameter("to  ", as: String.self)
				return previous
			},
			CommandDefinition("XMLGetDocByID", code: "XML GDbK") { request in
				let identifier = try request.requiredDirectParameter(as: String.self)
				let pool = try request.parameter("pool", as: String.self) ?? store.currentPool
				guard let document = references.documents.first(where: { $0.identifier == identifier && $0.pool == pool }) else {
					throw XML.notFound
				}
				return references.reference(document)
			},
			CommandDefinition("XMLc14n", code: "XML c14n", handler: canonical),
			CommandDefinition("XMLSetExtras", code: "XML Sext") { request in
				try direct(request).0.extras = try request.requiredParameter("to  ", as: AnyDescriptor.self).descriptor
				return nil
			},
			CommandDefinition("XMLGetExtras", code: "XML Gext") { request in
				guard let extras = try direct(request).0.extras else { throw XML.notFound }
				return extras
			},
			CommandDefinition("XMLGetID", code: "XML gID ") { try direct($0).0.number },
			CommandDefinition("XMLFromID", code: "XML gfID") { request in
				let number = try request.requiredDirectParameter(as: Int.self)
				guard let document = references.documents.first(where: { $0.number == number }) else { throw XML.notFound }
				return references.reference(document)
			},
		]
	}

	/// Saves the whole document (whichever node is given) to `in` (a file, or a path, which SatimageOSAX refused),
	/// or to its own file (-1701 if it has none), in its encoding unless `encoding` is given.
	func save(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let (document, _) = try direct(request)
		guard let url = try request.parameter("kfil", as: URL.self) ?? document.url.flatMap({ $0.isFileURL ? $0 : nil }) else {
			throw OSAXError.missingParameter
		}
		guard let root = document.node(number: 0) else { throw XML.noSuchNode }
		let bytes = try Output.serialize(root, options: outputOptions(request))
		do {
			try bytes.writeReplacing(url)
		} catch {
			throw OSAXError(1524) // XML_IO_ENOENT, as SatimageOSAX replied
		}
		document.url = url
		return nil
	}

	/// Canonical XML, as text, a SHA1 or MD5 digest (base64), or written to `in`. An XMLRef stands for its whole
	/// document; a list of XMLRefs or an `XPathRef` record is a document subset (only those nodes, as xml-c14n11
	/// defines it), and so is `nodelist`, which SatimageOSAX ignored. An empty list is -1700, as in SatimageOSAX.
	func canonical(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor? {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let prefixes = try request.descriptor(for: "Incl").map { try XMLCommands.items($0).map(XMLCommands.text) } ?? []
		let digest = try request.parameter("Meth", as: String.self)
		let comments = try request.parameter("comm", default: true)
		let exclusive = try request.parameter("Excl", default: false)
		let whole = XMLReferences.isReference(descriptor) ? try resolve(descriptor).0 : nil
		let data: Data
		if let subset = request.descriptor(for: "Nset") ?? (whole == nil ? descriptor : nil) {
			data = try withNodeSet(subset) { document, nodes in
				let document = whole ?? document
				guard let doc = document?.doc else { throw XML.noSuchNode }
				// (A namespace node is an xmlNs, which has no `doc`.)
				guard XPath.nodes(nodes).allSatisfy({ $0.pointee.type == XML_NAMESPACE_DECL || $0.pointee.doc == doc }) else {
					throw OSAXError(-50, "The nodes must all be in the same document.")
				}
				return try Output.canonical(doc, nodes: nodes, comments: comments, exclusive: exclusive, prefixes: prefixes, digest: digest)
			}
		} else {
			guard let doc = whole?.doc else { throw XML.noSuchNode }
			data = try Output.canonical(doc, comments: comments, exclusive: exclusive, prefixes: prefixes, digest: digest)
		}
		if let file = try request.parameter("in  ", as: URL.self) {
			do {
				try data.writeReplacing(file)
			} catch {
				throw OSAXError(1524)
			}
			return nil
		}
		return NSAppleEventDescriptor(string: digest == nil ? String(decoding: data, as: UTF8.self) : data.base64EncodedString())
	}
}

/// Fetching documents over http and https (`XMLOpen` of a URL).
enum Network {
	/// Where a document comes from: a file (alias, file reference, path, or file URL text) or a URL.
	static func location(_ descriptor: NSAppleEventDescriptor) throws -> URL {
		if [typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType),
		   let text = descriptor.stringValue, let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme)
		{
			return url
		}
		// A URL value (a `furl`) can hold an http URL too.
		if descriptor.descriptorType == typeFileURL, let url = descriptor.fileURLValue,
		   let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme)
		{
			return url
		}
		return try URL(appleEventDescriptor: descriptor)
	}

	/// The body of a GET (with `query` after a `?`) or a POST (with `query` as a form body), with extra `headers`
	/// from a record. Error 1549 (libxml2's "failed to load") if it can't be fetched or the status isn't a success.
	static func fetch(_ url: URL, post: Bool, query: String?, headers: NSAppleEventDescriptor?) throws -> Data {
		var target = url
		if let query, !post {
			target = appending(query: query, to: url)
		}
		var request = URLRequest(url: target)
		if post {
			request.httpMethod = "POST"
			request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
			request.httpBody = Data((query ?? "").utf8)
		}
		if let headers, let fields = RecordFields(headers) {
			for (key, value) in fields.fields {
				guard case let .user(name) = key, let text = value.stringValue else { continue }
				request.setValue(text, forHTTPHeaderField: name)
			}
		}
		let result = Result<Data, Error>.fetch(request)
		guard case let .success(data) = result else {
			throw OSAXError(1549)
		}
		return data
	}

	/// `url` with `query` added to its query. Characters a query can't hold (spaces, quotes, non-ASCII, a `%` that
	/// doesn't start an escape) are percent-encoded; escapes already in `query` are kept.
	static func appending(query: String, to url: URL) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove("%")
		var encoded = ""
		let characters = Array(query)
		func isHexDigit(_ index: Int) -> Bool {
			index < characters.count && characters[index].isASCII && characters[index].isHexDigit
		}
		for (index, character) in characters.enumerated() {
			let isEscape = character == "%" && isHexDigit(index + 1) && isHexDigit(index + 2)
			if isEscape || character.unicodeScalars.allSatisfy(allowed.contains) {
				encoded.append(character)
			} else {
				encoded += String(character).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
			}
		}
		components.percentEncodedQuery = [components.percentEncodedQuery, encoded].compactMap { $0 }.joined(separator: "&")
		return components.url ?? url
	}
}

/// What libxml2 and libxslt load by URL themselves (external DTDs and entities, `xsl:import`, `document()`,
/// XInclude, schemas): http and https through `Network.fetch`, so with TLS rather than libxml2's own cleartext
/// client, which can't do https; ftp not at all. Anything else (files) is left to libxml2. Nothing is fetched
/// under `LoadRestrictions` (which its entity loader checks first too).
enum NetworkInput {
	/// Installs the callbacks, once. Callbacks registered later are asked first, so libxml2's own are
	/// registered (by initializing it) before these. Documents can't name catalogs of their own
	/// (`<?oasis-xml-catalog?>`), which would let them send what they load elsewhere.
	static func install() {
		_ = installation
	}

	private static let installation: Void = {
		xmlInitParser()
		xmlCatalogSetDefaults(XML_CATA_ALLOW_GLOBAL)
		_ = xmlRegisterInputCallbacks(matches, open, read, close)
	}()

	/// A URL these callbacks answer for: http, https or ftp.
	static func scheme(_ name: UnsafePointer<CChar>?) -> String? {
		guard let name else { return nil }
		let text = String(cString: name)
		guard let colon = text.firstIndex(of: ":"), text[colon...].hasPrefix("://") else { return nil }
		let scheme = text[..<colon].lowercased()
		return ["http", "https", "ftp"].contains(scheme) ? scheme : nil
	}

	/// What was fetched, or nil for a stream whose first read fails. libxml2 goes on to its own clients when an
	/// open callback gives nil, so a refused or failed load is a stream that fails instead.
	private final class Stream {
		let data: Data?
		var offset = 0

		init(_ data: Data?) {
			self.data = data
		}
	}

	private static let matches: xmlInputMatchCallback = { name in
		scheme(name) == nil ? 0 : 1
	}

	/// A failing stream for ftp, under `LoadRestrictions`, or when the fetch fails.
	private static let open: xmlInputOpenCallback = { name in
		var data: Data?
		let text = name.map { String(cString: $0) } ?? ""
		if scheme(name) == "ftp" {
			XMLIssues.warn("ftp isn’t supported: \(text)")
		} else if let restrictions = LoadRestrictions.current {
			_ = restrictions.allows(text)
		} else if let url = URL(string: text) {
			data = try? Network.fetch(url, post: false, query: nil, headers: nil)
			if data == nil { XMLIssues.warn("Couldn’t load \(text)") }
		}
		return Unmanaged.passRetained(Stream(data)).toOpaque()
	}

	private static let read: xmlInputReadCallback = { context, buffer, length in
		guard let context, let buffer else { return -1 }
		let stream = Unmanaged<Stream>.fromOpaque(context).takeUnretainedValue()
		guard let data = stream.data else { return -1 }
		let count = min(Int(length), data.count - stream.offset)
		guard count > 0 else { return 0 }
		data.withUnsafeBytes { bytes in
			UnsafeMutableRawPointer(buffer).copyMemory(from: bytes.baseAddress! + stream.offset, byteCount: count)
		}
		stream.offset += count
		return Int32(count)
	}

	private static let close: xmlInputCloseCallback = { context in
		if let context { Unmanaged<Stream>.fromOpaque(context).release() }
		return 0
	}
}

extension Result where Success == Data, Failure == Error {
	/// The session for fetching. The main thread waits for each fetch, and with it every script using MTC_OSAX, so a
	/// slow server gets 30 seconds between packets and a minute in all (URLSession's defaults are a minute and a
	/// week), well within AppleScript's two-minute timeout for a command.
	static let session: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.timeoutIntervalForRequest = 30
		configuration.timeoutIntervalForResource = 60
		return URLSession(configuration: configuration)
	}()

	/// A synchronous URL request (commands run one at a time on the main thread; the session works on its own).
	static func fetch(_ request: URLRequest) -> Result<Data, Error> {
		let semaphore = DispatchSemaphore(value: 0)
		nonisolated(unsafe) var result: Result<Data, Error> = .failure(URLError(.unknown))
		session.dataTask(with: request) { data, response, error in
			// Only a success status counts; a 404 page isn't the document.
			if let status = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(status) {
				result = .failure(URLError(.badServerResponse))
			} else {
				result = data.map { .success($0) } ?? .failure(error ?? URLError(.unknown))
			}
			semaphore.signal()
		}.resume()
		semaphore.wait()
		return result
	}
}
