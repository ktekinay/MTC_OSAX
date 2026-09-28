import AppleEventCore
import Foundation
import PropertyLists
import Testing
@testable import XML

/// Sends commands to one set of XML (and PropertyList, for pools) commands, sharing their documents.
final class XMLs {
	let store = DocumentStore()
	private let dispatcher = CommandDispatcher()

	init() {
		dispatcher.register(XML.commands(store: store))
		dispatcher.register(PropertyLists.commands(store: store))
	}

	@discardableResult
	func send(_ code: String, _ parameters: [String: any AppleEventEncodable] = [:]) -> AppleEventReply {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
		for (keyword, value) in parameters {
			event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
		}
		return dispatcher.dispatch(event)
	}

	func open(_ text: String) throws -> NSAppleEventDescriptor {
		try #require(send("XML open", ["from": text]).result)
	}

	func root(_ document: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
		try #require(send("XML root", ["----": document]).result)
	}
}

struct XMLCommandTests {
	@Test func libxml2IsLinked() {
		#expect(XML.libxmlVersion.hasPrefix("209"))
	}

	@Test func removedNodesAreInvalid() throws {
		let xml = XMLs()
		let d = try xml.open("<a><b><c/></b></a>")
		let b = try #require(xml.send("XML chld", ["----": try xml.root(d), "indx": 1]).result)
		let c = try #require(xml.send("XML chld", ["----": b, "indx": 1]).result)
		xml.send("XML remo", ["----": b])
		#expect(xml.send("XML gtag", ["----": b]).error == OSAXError(-1728))
		#expect(xml.send("XML gtag", ["----": c]).error == OSAXError(-1728))
		#expect(xml.send("XML Exis", ["----": c]).result?.booleanValue == false)
	}

	/// A node number beyond Int's range used to trap.
	@Test func forgedReference() throws {
		let xml = XMLs()
		let root = try xml.root(xml.open("<a/>"))
		var data = root.data
		data.replaceSubrange(8 ..< 16, with: [UInt8](repeating: 0xFF, count: 8))
		let forged = try #require(NSAppleEventDescriptor(descriptorType: root.descriptorType, data: data))
		#expect(xml.send("XML gtag", ["----": forged]).error == OSAXError(-1728))
	}
}

struct XMLOpenTests {
	@Test func errorsAndLevels() throws {
		let xml = XMLs()
		#expect(xml.send("XML open", ["from": "<a><b></a>"]).error == OSAXError(76))
		#expect(xml.send("XML lErr").result?.stringValue?.contains("Opening and ending tag mismatch") == true)
		#expect(xml.send("XML open", ["from": ""]).error == OSAXError(-1))
		#expect(xml.send("XML open", ["----": URL(fileURLWithPath: "/nonexistent.xml")]).error == OSAXError(1549))
		_ = try xml.open("<a/>")
		#expect(xml.send("XML lErr").result?.stringValue == "")
		#expect(xml.send("XML ErLe").result?.int32Value == 2)
		#expect(xml.send("XML ErLe", ["----": 3]).result?.int32Value == 2)
		#expect(xml.send("XML ErLe").result?.int32Value == 3)
	}

	@Test func options() throws {
		let xml = XMLs()
		let spaced = "<a>\n  <b/>\n  <c/>\n</a>"
		#expect(xml.send("XML cunt", ["----": try xml.root(xml.open(spaced))]).result?.int32Value == 2)
		let kept = try #require(xml.send("XML open", ["from": spaced, "kbln": true]).result)
		#expect(xml.send("XML cunt", ["----": try xml.root(kept)]).result?.int32Value == 5)
		#expect(xml.send("XML ecun", ["----": try xml.root(kept)]).result?.int32Value == 2)
		let html = try #require(xml.send("XML open", ["from": "<p>Hi<br>there", "HTML": true]).result)
		#expect(xml.send("XML disp", ["----": html]).result.flatMap(RecordFields.init)?[.code("kind")]?.stringValue == "HTML_DOCUMENT_NODE")
		let bypassed = try #require(xml.send("XML open", ["from": "<a xmlns=\"urn:x\"><b/></a>", "bpns": true]).result)
		#expect(xml.send("XML gtn1", ["----": try xml.root(bypassed)]).error == OSAXError(-2763))
	}

	@Test func queryIsEncoded() throws {
		let base = try #require(URL(string: "http://example.com/x?a=1"))
		#expect(Network.appending(query: "name=hello world", to: base).absoluteString == "http://example.com/x?a=1&name=hello%20world")
		#expect(Network.appending(query: "q=<\"{é}\">&p=50%25&r=%zz", to: base).absoluteString
			== "http://example.com/x?a=1&q=%3C%22%7B%C3%A9%7D%22%3E&p=50%25&r=%25zz")
		// A query with spaces used to abort the app; now it's only a failed fetch (nothing listens on port 9).
		let xml = XMLs()
		let reply = xml.send("XML open", ["----": "http://127.0.0.1:9/", "qury": "name=hello world"])
		#expect(reply.error == OSAXError(1549))
	}

	@Test func extendedCharacters() throws {
		let xml = XMLs()
		let d = try xml.open("<a>x&#1;y</a>")
		#expect(xml.send("XML gttx", ["----": try xml.root(d)]).result?.stringValue == "x\u{1}y")
		#expect(xml.send("XML Vr11", ["----": false]).result?.booleanValue == true)
		#expect(xml.send("XML open", ["from": "<a>x&#1;y</a>"]).error == OSAXError(9))
	}
}

struct XMLNavigationTests {
	private let text = "<?xml version=\"1.0\"?><!-- c --><r><a id=\"1\">A</a>text<b/><!-- d --></r>"

	@Test func childrenAndSiblings() throws {
		let xml = XMLs()
		let d = try xml.open(text)
		let r = try xml.root(d)
		#expect(xml.send("XML cunt", ["----": r]).result?.int32Value == 4)
		#expect(xml.send("XML cunt", ["----": r, "ANot": false]).result?.int32Value == 2)
		#expect(xml.send("XML cunt", ["----": d]).result?.int32Value == 2)
		let second = try #require(xml.send("XML echl", ["----": r, "indx": 2]).result)
		#expect(xml.send("XML gtag", ["----": second]).result?.stringValue == "b")
		#expect(xml.send("XML chld", ["----": r, "indx": 5]).error == OSAXError(-1719))
		#expect(xml.send("XML chld", ["----": r, "indx": [1]]).error == .coercionFailed)
		#expect(xml.send("XML chld", ["----": r]).error == .missingParameter)
		let a = try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)
		#expect(xml.send("XML gtag", ["----": try #require(xml.send("XML sibl", ["----": a]).result)]).result?.stringValue == "text")
		#expect(xml.send("XML gtag", ["----": try #require(xml.send("XML esib", ["----": a]).result)]).result?.stringValue == "b")
		#expect(xml.send("XML psib", ["----": a]).error == OSAXError(-1728))
		#expect(xml.send("XML pare", ["----": d]).error == OSAXError(-1728))
		#expect(xml.send("XML gtag", ["----": [a, r]]).result?.numberOfItems == 2)
	}

	@Test func nodeInfo() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open(text))
		let a = try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)
		let info = try #require(xml.send("XML disp", ["----": a]).result.flatMap(RecordFields.init))
		#expect(info[.code("kind")]?.stringValue == "ELEMENT_NODE")
		#expect(info[.code("pnam")]?.stringValue == "a")
		#expect(info[.code("attr")]?.numberOfItems == 2)
		#expect(info[.code("cpar")]?.int32Value == 1)
	}
}

struct XMLChangeTests {
	@Test func attributesAndText() throws {
		let xml = XMLs()
		let d = try xml.open("<a x=\"1\"><t>old</t></a>")
		let a = try xml.root(d)
		#expect(xml.send("XML geta", ["----": a, "pnam": "x"]).result?.stringValue == "1")
		#expect(xml.send("XML geta", ["----": a, "pnam": "y"]).error == OSAXError(-1728))
		#expect(xml.send("XML geta", ["----": a, "pnam": ["x", "y"]]).result?.atIndex(2)?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		xml.send("XML seta", ["----": a, "pnam": ["x", "y"], "to  ": AppleEventList([NSAppleEventDescriptor.missingValue, "2"])])
		#expect(xml.send("XML geta", ["----": a, "pnam": "x"]).result?.stringValue == "1")
		xml.send("XML seta", ["----": a, "pnam": ["x"], "to  ": AppleEventList([NSAppleEventDescriptor.missingValue]), "Supp": true])
		#expect(xml.send("XML geta", ["----": a, "pnam": "x"]).error == OSAXError(-1728))
		let t = try #require(xml.send("XML chld", ["----": a, "indx": 1]).result)
		xml.send("XML sttx", ["----": t, "to  ": "a & <b>"])
		#expect(xml.send("XML disx", ["----": t]).result?.stringValue == "<t>a &amp; &lt;b&gt;</t>")
		xml.send("XML ApTx", ["----": "!", "at  ": t])
		#expect(xml.send("XML gttx", ["----": t]).result?.stringValue == "a & <b>!")
	}

	@Test func newNodesAndRemoving() throws {
		let xml = XMLs()
		let d = try xml.open("<a xmlns:n=\"urn:n\"><b/></a>")
		let a = try xml.root(d)
		let c = try #require(xml.send("XML addc", ["----": "<n:c/>", "at  ": a]).result)
		#expect(xml.send("XML gtn1", ["----": c]).result.flatMap(RecordFields.init)?[.code("PUri")]?.stringValue == "urn:n")
		let b = try #require(xml.send("XML chld", ["----": a, "indx": 1]).result)
		xml.send("XML adds", ["----": "<first/>", "befo": b])
		#expect(xml.send("XML gtag", ["----": try #require(xml.send("XML chld", ["----": a, "indx": 1]).result)]).result?.stringValue == "first")
		#expect(xml.send("XML adds", ["----": "<x/>", "afte": a]).error == OSAXError(-1))
		#expect(xml.send("XML addc", ["----": "<bad>", "at  ": a]).error != nil)
		xml.send("XML remc", ["----": a])
		#expect(xml.send("XML cunt", ["----": a]).result?.int32Value == 0)
		#expect(xml.send("XML Exis", ["----": [a, b]]).result?.booleanValue == false)
	}

	/// libxml2 merges new text into adjacent text and frees the new node; the references returned used to point at
	/// freed memory. They now refer to the node the text was merged into.
	@Test func mergedTextNodes() throws {
		let xml = XMLs()
		let d = try xml.open("<a>hello</a>")
		let a = try xml.root(d)
		let added = try #require(xml.send("XML addc", ["----": "!", "at  ": a]).result)
		#expect(xml.send("XML gttx", ["----": added]).result?.stringValue == "hello!")
		let hello = try #require(xml.send("XML chld", ["----": a, "indx": 1]).result)
		let siblings = try #require(xml.send("XML adds", ["----": "x<i/>y", "afte": hello]).result)
		#expect(xml.send("XML disx", ["----": a, "smar": false]).result?.stringValue == "<a>hello!x<i/>y</a>")
		#expect(xml.send("XML gttx", ["----": siblings]).result?.stringValue == "hello!x")
		xml.send("XML adds", ["----": "<j/>z", "befo": try #require(xml.send("XML chld", ["----": a, "indx": 3]).result)])
		#expect(xml.send("XML disx", ["----": a, "smar": false]).result?.stringValue == "<a>hello!x<i/><j/>zy</a>")
		// Clones of text nodes merge too.
		let clones = try #require(xml.send("XML addc", ["----": AppleEventList([hello, hello]), "at  ": a]).result)
		#expect(clones.numberOfItems == 2)
		#expect(xml.send("XML gttx", ["----": try #require(clones.atIndex(2))]).result?.stringValue == "zyhello!xhello!x")
		// XMLSetXML of a text node next to text.
		let t = try xml.root(xml.open("<t><b/>one<!---->two</t>"))
		let one = try #require(xml.send("XML chld", ["----": t, "indx": 2]).result)
		xml.send("XML remo", ["----": try #require(xml.send("XML chld", ["----": t, "indx": 3]).result)])
		let set = try #require(xml.send("XML stxm", ["----": one, "to  ": "1"]).result)
		#expect(xml.send("XML gttx", ["----": set]).result?.stringValue == "1two")
		#expect(xml.send("XML disx", ["----": t, "smar": false]).result?.stringValue == "<t><b/>1two</t>")
	}

	@Test func setXMLOfTextNode() throws {
		let xml = XMLs()
		let a = try xml.root(xml.open("<a>one<b/>two</a>"))
		let one = try #require(xml.send("XML chld", ["----": a, "indx": 1]).result)
		xml.send("XML stxm", ["----": one, "to  ": "<i>x</i> y"])
		#expect(xml.send("XML cunt", ["----": a]).result?.int32Value == 4)
		#expect(xml.send("XML disx", ["----": a, "smar": false]).result?.stringValue == "<a><i>x</i> y<b/>two</a>")
	}
}

struct XMLSearchTests {
	@Test func findAndRegexp() throws {
		let xml = XMLs()
		let d = try xml.open("<r><item k=\"1\">one</item><item k=\"2\">two</item><other>2020</other><!-- note --></r>")
		let r = try xml.root(d)
		#expect(xml.send("XML find", ["----": r, "pnam": "item", "WaAl": true]).result?.numberOfItems == 2)
		#expect(xml.send("XML geta", ["----": try #require(xml.send("XML find", ["----": r, "key ": "k", "val ": "2"]).result), "pnam": "k"]).result?.stringValue == "2")
		#expect(xml.send("XML find", ["----": r, "key ": "k"]).error == .missingParameter)
		#expect(xml.send("XML find", ["----": d, "pnam": "item"]).error == .parameterError)
		#expect(xml.send("XML find", ["----": r, "pnam": "nope"]).error == OSAXError(-2763))
		#expect(xml.send("XML fint", ["----": "note", "in  ": r, "WaAl": true]).result?.numberOfItems == 1)
		#expect(xml.send("XML grep", ["----": "[0-9]{4}", "in  ": r, "WaAl": true]).result?.numberOfItems == 1)
		#expect(xml.send("XML grep", ["----": "^[0-9]{4}$", "in  ": r, "WaAl": true]).result?.numberOfItems == 0)
		#expect(xml.send("XML grep", ["----": "([", "in  ": r]).error == OSAXError(1450))
	}

	@Test func namespaces() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open("<r xmlns=\"urn:d\" xmlns:a=\"urn:a\"><a:x/></r>"))
		#expect(xml.send("XML gtns", ["----": r]).result?.numberOfItems == 2)
		#expect(xml.send("XML gtn2", ["----": r, "pref": "a"]).result?.stringValue == "urn:a")
		#expect(xml.send("XML gtn2", ["----": r, "pref": "zz"]).error == OSAXError(-2763))
		let ns = RecordFields([(.code("PREf"), NSAppleEventDescriptor(string: "n")), (.code("PUri"), NSAppleEventDescriptor(string: "urn:n"))])
		xml.send("XML adns", ["----": ns, "at  ": r])
		#expect(xml.send("XML gtns", ["----": r]).result?.numberOfItems == 3)
		#expect(xml.send("XML adns", ["----": ns, "at  ": r]).error == OSAXError(-1))
	}
}

struct XMLDocumentTests {
	@Test func saveURLsAndEncodings() throws {
		let xml = XMLs()
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xml-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let d = try xml.open("<a>café</a>")
		#expect(xml.send("XML save", ["----": d]).error == .missingParameter)
		#expect(xml.send("XML gurl", ["----": d]).error == OSAXError(-2763))
		let file = folder.appendingPathComponent("a.xml")
		xml.send("XML save", ["----": d, "kfil": file.path])
		#expect(try String(contentsOf: file, encoding: .utf8) == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<a>café</a>\n")
		#expect(xml.send("XML gurl", ["----": d]).result?.stringValue == file.path)
		xml.send("XML senc", ["----": d, "to  ": "ISO-8859-1"])
		xml.send("XML save", ["----": d])
		#expect(try Data(contentsOf: file).contains(0xE9))
		#expect(xml.send("XML senc", ["----": d, "to  ": "nonsense"]).error == .parameterError)
		#expect(xml.send("XML save", ["----": d, "kfil": folder.appendingPathComponent("nope/a.xml")]).error == OSAXError(1524))
	}

	@Test func displayOptions() throws {
		let xml = XMLs()
		let d = try xml.open("<a><b>x</b></a>")
		#expect(xml.send("XML disx", ["----": d]).result?.stringValue == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<a>\n\t<b>x</b>\n</a>\n")
		#expect(xml.send("XML disx", ["----": d, "smar": false, "XmlH": false]).result?.stringValue == "<a><b>x</b></a>\n")
		#expect(xml.send("XML Indt", ["----": "  "]).result?.stringValue == "\t")
		#expect(xml.send("XML disx", ["----": try xml.root(d)]).result?.stringValue == "<a>\n  <b>x</b>\n</a>")
	}

	@Test func canonicalization() throws {
		let xml = XMLs()
		let d = try xml.open("<a b=\"2\" a=\"1\"><!-- c --><x/></a>")
		#expect(xml.send("XML c14n", ["----": d]).result?.stringValue == "<a a=\"1\" b=\"2\"><!-- c --><x></x></a>")
		#expect(xml.send("XML c14n", ["----": d, "comm": false]).result?.stringValue == "<a a=\"1\" b=\"2\"><x></x></a>")
		#expect(xml.send("XML c14n", ["----": d, "Meth": "SHA1"]).result?.stringValue?.count == 28)
		#expect(xml.send("XML c14n", ["----": d, "Meth": "SHA256"]).error == OSAXError(-1))
	}

	/// Document subsets, as recorded from SatimageOSAX (which ignored `nodelist`); an empty list used to trap.
	@Test func canonicalSubsets() throws {
		let xml = XMLs()
		let d = try xml.open("<a><b x='1'>t<!--c--><i/></b><c/></a>")
		func nodes(_ path: String) throws -> NSAppleEventDescriptor {
			try #require(xml.send("XML path", ["----": d, "with": path]).result)
		}
		func c14n(_ parameters: [String: any AppleEventEncodable]) -> String? {
			xml.send("XML c14n", parameters).result?.stringValue
		}
		let b = try #require(try nodes("//b").atIndex(1))
		let whole = "<a><b x=\"1\">t<!--c--><i></i></b><c></c></a>"
		#expect(c14n(["----": try nodes("//b")]) == "<b></b>")
		#expect(c14n(["----": try nodes("//b/descendant-or-self::node()|//b//@*")]) == "<b x=\"1\">t<!--c--><i></i></b>")
		#expect(c14n(["----": try nodes("//b|//b/@x|//i")]) == "<b x=\"1\"><i></i></b>")
		let xpathRef = RecordFields([(.code("XMLR"), b), (.code("xpat"), NSAppleEventDescriptor(string: "descendant-or-self::node()|.//@*"))])
		#expect(c14n(["----": xpathRef.appleEventDescriptor]) == "<b x=\"1\">t<!--c--><i></i></b>")
		#expect(c14n(["----": b]) == whole)
		#expect(c14n(["----": d, "Nset": try nodes("//i")]) == "<i></i>")
		#expect(c14n(["----": d, "Nset": xpathRef.appleEventDescriptor, "comm": false]) == "<b x=\"1\">t<i></i></b>")
		#expect(xml.send("XML c14n", ["----": AppleEventList([Int]())]).error == .coercionFailed)
		let other = try xml.open("<z/>")
		#expect(xml.send("XML c14n", ["----": d, "Nset": try xml.root(other)]).error?.number == -50)
	}

	@Test func documentsPoolsAndIdentifiers() throws {
		let xml = XMLs()
		let d = try #require(xml.send("XML open", ["from": "<a/>", "pool": "p"]).result)
		#expect(xml.send("POOLgpoo", ["----": d]).result?.stringValue == "p")
		#expect(xml.send("XML List", ["----": "p"]).result?.numberOfItems == 1)
		xml.send("XML SDbK", ["----": d, "to  ": "id"])
		#expect(xml.send("XML GDbK", ["----": "id", "pool": "p"]).result != nil)
		#expect(xml.send("XML GDbK", ["----": "id"]).error == OSAXError(-2763))
		xml.send("XML Sext", ["----": d, "to  ": "extra"])
		#expect(xml.send("XML Gext", ["----": d]).result?.stringValue == "extra")
		let number = try #require(xml.send("XML gID ", ["----": d]).result?.int32Value)
		#expect(xml.send("XML gfID", ["----": Int(number)]).result != nil)
		let clone = try #require(xml.send("XML cdoc", ["----": d]).result)
		#expect(xml.send("XML gurl", ["----": clone]).error == OSAXError(-2763))
		xml.send("POOLdpoo", ["----": "p"])
		#expect(xml.send("XML root", ["----": d]).error == OSAXError(-1728))
		#expect(xml.store.hasOpenDocuments)
		xml.send("XML clos", ["----": clone])
		#expect(!xml.store.hasOpenDocuments)
	}
}

struct XMLFileInfoTests {
	@Test func firstTag() {
		#expect(XMLCommands.firstTag("<?xml version=\"1.0\"?>\n<!-- c -->\n<root a=\"1\">")! == (false, "root", 3))
		#expect(XMLCommands.firstTag("<!DOCTYPE people [\n]>\n<people/>")! == (true, "people", 1))
		#expect(XMLCommands.firstTag("no tags") == nil)
	}

	@Test func fileInfo() throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("info-\(UUID().uuidString).xml")
		try Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<a><b></a>".utf8).write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }
		let xml = XMLs()
		let info = try #require(xml.send("XML disp", ["----": file]).result.flatMap(RecordFields.init))
		#expect(info[.code("pnam")]?.stringValue == "a")
		#expect(info[.code("cpar")]?.int32Value == 2)
		#expect(info[.code("enco")]?.stringValue == "UTF-8")
		#expect(xml.send("XML disp", ["----": URL(fileURLWithPath: "/nonexistent.xml")]).error == OSAXError(-43))
	}
}
