import AppleEventCore
import Foundation
import PropertyLists
import Testing
@testable import XML

private let library = """
<library xmlns:dc="http://purl.org/dc/elements/1.1/"><book id="b1" lang="en"><title>Moby-Dick</title><dc:creator>Melville</dc:creator>\
<year>1851</year></book><book id="b2" lang="fr"><title>Les Misérables</title><dc:creator>Hugo</dc:creator><year>1862</year><!-- c --></book></library>
"""

private var dc: RecordFields {
	namespace("dc", "http://purl.org/dc/elements/1.1/")
}

private func namespace(_ prefix: String, _ uri: String) -> RecordFields {
	RecordFields([(.code("PREf"), NSAppleEventDescriptor(string: prefix)), (.code("PUri"), NSAppleEventDescriptor(string: uri))])
}

private func type(_ code: String) -> NSAppleEventDescriptor {
	NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: code))
}

extension XMLs {
	func xpath(_ node: NSAppleEventDescriptor, _ expression: String, _ parameters: [String: any AppleEventEncodable] = [:]) -> AppleEventReply {
		send("XML path", parameters.merging(["----": node, "with": expression]) { $1 })
	}

	func texts(_ nodes: NSAppleEventDescriptor?) -> [String] {
		guard let nodes else { return [] }
		return (0 ..< nodes.numberOfItems).map { send("XML gttx", ["----": nodes.atIndex($0 + 1)!]).result?.stringValue ?? "?" }
	}
}

struct XPathTests {
	@Test func resultsAndErrors() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open(library))
		#expect(xml.texts(xml.xpath(r, "book/title").result) == ["Moby-Dick", "Les Misérables"])
		#expect(xml.xpath(r, "count(book)").result?.descriptorType == typeSInt32)
		#expect(xml.xpath(r, "count(book)").result?.int32Value == 2)
		#expect(xml.xpath(r, "count(book) div 4").result?.doubleValue == 0.5)
		#expect(xml.xpath(r, "string(book[1]/title)").result?.stringValue == "Moby-Dick")
		#expect(xml.xpath(r, "count(book) > 1").result?.booleanValue == true)
		#expect(xml.xpath(r, "nothing").result?.numberOfItems == 0)
		#expect(xml.xpath(r, "book[").error == OSAXError(1207))
		#expect(xml.xpath(r, "nope(1)").error == OSAXError(3))
		#expect(xml.xpath(r, "book/dc:creator").error == OSAXError(3))
		#expect(xml.xpath(r, "$v").error == OSAXError(3))
		#expect(xml.send("XML path", ["----": r]).error == .missingParameter)
		#expect(xml.xpath(r, "$v", ["vars": ["v"]]).error == .coercionFailed)
		let book = try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)
		#expect(xml.xpath([r, book].appleEventDescriptor, "title").result?.numberOfItems == 2)
	}

	@Test func attributesAreNodes() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open(library))
		let ids = try #require(xml.xpath(r, "book/@id").result)
		let id = try #require(ids.atIndex(1))
		#expect(xml.send("XML gttx", ["----": id]).result?.stringValue == "b1")
		#expect(xml.send("XML gtag", ["----": id]).result?.stringValue == "id")
		let info = try #require(xml.send("XML disp", ["----": id]).result.flatMap(RecordFields.init))
		#expect(info[.code("kind")]?.stringValue == "ATTRIBUTE_NODE")
		#expect(info[.code("pnam")]?.stringValue == "id")
	}

	@Test func namespacesAndVariables() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open(library))
		#expect(xml.texts(xml.xpath(r, "book/dc:creator", ["nsls": dc]).result) == ["Melville", "Hugo"])
		#expect(xml.xpath(r, "book/dc:creator", ["nsls": [dc]]).result?.numberOfItems == 2)
		#expect(xml.texts(xml.xpath(r, "book[@id=$v]/title", ["vars": ["v", "b2"]]).result) == ["Les Misérables"])
		let record = RecordFields([(.user("v"), NSAppleEventDescriptor(string: "b1"))])
		#expect(xml.texts(xml.xpath(r, "book[@id=$v]/title", ["vars": record]).result) == ["Moby-Dick"])
		let number: [NSAppleEventDescriptor] = [NSAppleEventDescriptor(string: "n"), NSAppleEventDescriptor(int32: 2)]
		#expect(xml.texts(xml.xpath(r, "book[$n]/title", ["vars": number]).result) == ["Les Misérables"])
		let node: [NSAppleEventDescriptor] = [NSAppleEventDescriptor(string: "b"), r]
		#expect(xml.xpath(r, "count($b/book)", ["vars": node]).result?.int32Value == 2)
	}

	@Test func context() throws {
		let xml = XMLs()
		let d = try xml.open(library)
		let r = try xml.root(d)
		let empty = try #require(xml.send("XML xpNS", ["----": d]).result.flatMap(RecordFields.init))
		#expect(empty[.code("nsls")]?.numberOfItems == 0)
		xml.send("XML xpns", ["----": d, "nsls": [dc], "vars": ["v", "b1"]])
		#expect(xml.texts(xml.xpath(r, "book[@id=$v]/dc:creator").result) == ["Melville"])
		#expect(xml.texts(xml.xpath(r, "book[@id=$v]/title", ["vars": ["v", "b2"]]).result) == ["Les Misérables"])
		let context = try #require(xml.send("XML xpNS", ["----": d]).result.flatMap(RecordFields.init))
		#expect(context[.code("nsls")]?.numberOfItems == 1)
		// XMLXPath's variables are kept too, as in SatimageOSAX.
		#expect(context[.code("vars")]?.atIndex(1)?.atIndex(2)?.stringValue == "b2")
		// Another document has its own context.
		#expect(xml.xpath(try xml.root(xml.open(library)), "book[@id=$v]").error == OSAXError(3))
		// Removing: an empty URL, and missing value.
		let removal = namespace("dc", "")
		let variables: [NSAppleEventDescriptor] = [NSAppleEventDescriptor(string: "v"), .missingValue]
		xml.send("XML xpns", ["----": d, "nsls": [removal], "vars": variables])
		let cleared = try #require(xml.send("XML xpNS", ["----": d]).result.flatMap(RecordFields.init))
		#expect(cleared[.code("nsls")]?.numberOfItems == 0)
		#expect(cleared[.code("vars")]?.numberOfItems == 0)
	}

	@Test func functions() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open(library))
		func value(_ prefix: String, _ uri: String, _ expression: String) -> NSAppleEventDescriptor? {
			xml.xpath(r, expression, ["nsls": namespace(prefix, uri)]).result
		}
		let fn = "http://www.w3.org/2005/xpath-functions"
		#expect(value("fn", fn, "fn:upper-case(string(book[1]/title))")?.stringValue == "MOBY-DICK")
		#expect(value("fn", fn, "fn:compare('a', 'b')")?.int32Value == -1)
		#expect(value("fn", fn, "fn:ends-with('abc', 'bc')")?.booleanValue == true)
		#expect(xml.xpath(r, "fn:upper-case()", ["nsls": namespace("fn", fn)]).error == OSAXError(3))
		#expect(value("m", "http://exslt.org/math", "m:max(//year)")?.int32Value == 1862)
		#expect(value("c", "http://exslt.org/crypto", "c:md5('abc')")?.stringValue == "kAFQmDzST7DWlj99KOF/cg==")
		#expect(value("s", "http://exslt.org/strings", "s:replace('a-b', '-', '+')")?.stringValue == "a+b")
		let satimage = "http://satimage.fr/software/xpath-functions"
		#expect(value("sat", satimage, "sat:parent-uri('http://a.com/b/c.xml')")?.stringValue == "http://a.com/b/")
		#expect(value("sat", satimage, "sat:relative-uri('http://a.com/b/c.xml', 'http://a.com/d/e.xml')")?.stringValue == "../b/c.xml")
		// Only through a declared prefix.
		#expect(xml.xpath(r, "upper-case('a')").error == OSAXError(3))
	}
}

struct NodePathTests {
	@Test func paths() throws {
		let xml = XMLs()
		let d = try xml.open(library)
		let r = try xml.root(d)
		func path(_ node: NSAppleEventDescriptor, from: NSAppleEventDescriptor? = nil) -> String? {
			var parameters: [String: any AppleEventEncodable] = ["----": node]
			if let from { parameters["from"] = from }
			return xml.send("XML NoPa", parameters).result?.stringValue
		}
		let year = try #require(xml.xpath(r, "book[2]/year").result?.atIndex(1))
		#expect(path(year) == "xpointer(/library[1]/book[2]/year[1])")
		#expect(path(d) == "xpointer(/)")
		#expect(path(try #require(xml.xpath(r, "book[1]/@lang").result?.atIndex(1))) == "xpointer(/library[1]/book[1]/@lang)")
		#expect(path(try #require(xml.xpath(r, "book[1]/title/text()").result?.atIndex(1))) == "xpointer(/library[1]/book[1]/title[1]/text()[1])")
		#expect(path(try #require(xml.xpath(r, "book[2]/comment()").result?.atIndex(1))) == "xpointer(/library[1]/book[2]/comment())")
		#expect(path(try #require(xml.xpath(r, "book[1]/*[2]").result?.atIndex(1))) == "xpointer(/library[1]/book[1]/*[2])")
		#expect(path(year, from: r) == "book[2]/year[1]")
		#expect(path(year, from: try #require(xml.send("XML chld", ["----": r, "indx": 2]).result)) == "year[1]")
		#expect(path(year, from: try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)) == "xpointer(/library[1]/book[2]/year[1])")

		let several = try xml.root(xml.open("<a><!--1--><!--2--><?p x?><b/>t<b/><?p y?></a>"))
		func child(_ index: Int) throws -> NSAppleEventDescriptor { try #require(xml.send("XML chld", ["----": several, "indx": index]).result) }
		#expect(path(try child(2)) == "xpointer(/a[1]/comment()[2])")
		#expect(path(try child(3)) == "xpointer(/a[1]/processing-instruction('p')[1])")
		#expect(path(try child(5)) == "xpointer(/a[1]/text()[1])")
		#expect(path(try child(6)) == "xpointer(/a[1]/b[2])")
	}
}

struct XPointerTests {
	@Test func escapeAndGet() throws {
		let xml = XMLs()
		#expect(xml.send("XML ExXp", ["----": "it's (a) test ^ here"]).result?.stringValue == "it's ^(a^) test ^^ here")
		let r = try xml.root(xml.open("<a><b/></a>"))
		let b = try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)
		#expect(xml.send("XML gxpt", ["----": b]).result?.stringValue == "#xpointer(/a[1]/b[1])")
		#expect(xml.send("XML gxpt", ["----": b, "suff": "c"]).result?.stringValue == "#xpointer(/a[1]/b[1]/c)")
		#expect(xml.send("XML gxpt", ["----": b, "suff": "/c"]).result?.stringValue == "#xpointer(/a[1]/b[1]/c)")
		#expect(xml.send("XML gxpt", ["----": try #require(xml.send("XML pare", ["----": r]).result)]).error == .parameterError)
	}

	@Test func local() throws {
		let xml = XMLs()
		let d = try xml.open("<!DOCTYPE a [<!ATTLIST p id ID #IMPLIED>]><a><p id='p1'>One</p><p id='p2'>Two<q>x</q></p></a>")
		#expect(xml.texts(xml.send("XML xptr", ["----": "#xpointer(//p[2])", "from": d]).result) == ["Twox"])
		#expect(xml.texts(xml.send("XML xptr", ["----": "#p1", "from": d]).result) == ["One"])
		#expect(xml.send("XML xptr", ["----": "#zz", "from": d]).result?.numberOfItems == 0)
		#expect(xml.send("XML xptr", ["----": "#xpointer(((", "from": d]).error == OSAXError(1216))
		let p2 = try #require(xml.send("XML xptr", ["----": "#p2", "from": d]).result?.atIndex(1))
		#expect(xml.texts(xml.send("XML xptr", ["----": "#xpointer(q)", "from": p2]).result) == ["x"])
	}

	@Test func otherFiles() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-xptr-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		try "<a><b>B</b></a>".write(to: folder.appendingPathComponent("other.xml"), atomically: true, encoding: .utf8)
		try "<main/>".write(to: folder.appendingPathComponent("main.xml"), atomically: true, encoding: .utf8)
		let xml = XMLs()
		let d = try #require(xml.send("XML open", ["----": folder.appendingPathComponent("main.xml")]).result)
		#expect(xml.send("XML xptr", ["----": "other.xml#xpointer(/a/b)", "from": d, "CnOp": false]).error == OSAXError(11))
		#expect(xml.texts(xml.send("XML xptr", ["----": "other.xml#xpointer(/a/b)", "from": d]).result) == ["B"])
		// Now open in the pool: found again, even without permission to open it.
		#expect(xml.texts(xml.send("XML xptr", ["----": "other.xml#xpointer(/a/b)", "from": d, "CnOp": false]).result) == ["B"])
		#expect(xml.texts(xml.send("XML xptr", ["----": "other.xml#xpointer(/a/b)", "burl": folder.absoluteString + "/", "pool": "mtc-p"]).result) == ["B"])
		#expect(xml.store.allDocuments.count == 3)
	}
}

struct XSLTTests {
	private let titles = """
	<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:param name="label" select="'Titles'"/>\
	<xsl:template match="/"><titles label="{$label}"><xsl:for-each select="//book"><t><xsl:value-of select="title"/></t></xsl:for-each></titles>\
	</xsl:template></xsl:stylesheet>
	"""
	private let text = """
	<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:output method="text"/>\
	<xsl:template match="/"><xsl:for-each select="//title"><xsl:value-of select="."/>;</xsl:for-each></xsl:template></xsl:stylesheet>
	"""

	@Test func transform() throws {
		let xml = XMLs()
		let d = try xml.open(library)
		let t = try #require(xml.send("XML xslt", ["----": d, "with": titles]).result)
		#expect(xml.send("XML disx", ["----": t]).result?.stringValue
			== "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<titles label=\"Titles\">\n\t<t>Moby-Dick</t>\n\t<t>Les Misérables</t>\n</titles>\n")
		#expect(xml.send("XML gurl", ["----": t]).error == OSAXError(-2763))
		#expect(xml.send("XML xslt", ["----": d, "with": text, "rtyp": type("utxt")]).result?.stringValue == "Moby-Dick;Les Misérables;")
		#expect(xml.send("XML xslt", ["----": d]).error == .missingParameter)
		#expect(xml.send("XML xslt", ["----": d, "with": "<xsl:stylesheet version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform'><xsl:template match='/'><xsl:value-of select='(('/></xsl:template></xsl:stylesheet>"]).error == OSAXError(3))
		// libxslt's messages used to go to the console, leaving XMLError empty.
		#expect(xml.send("XML lErr").result?.stringValue?.contains("value-of") == true)
		#expect(xml.send("XML xslt", ["----": d, "with": URL(fileURLWithPath: "/nonexistent.xsl")]).error == OSAXError(4))
		#expect(xml.send("XML xslt", ["----": d, "with": "/nonexistent.xsl"]).error == OSAXError(4))
	}

	/// A stylesheet the script gives may write files; one the document picks with `xml-stylesheet` may not.
	@Test func writingFiles() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xslt-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		func stylesheet(_ name: String, id: String = "") -> String {
			"<xsl:stylesheet \(id)version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform' xmlns:exsl='http://exslt.org/common' "
				+ "extension-element-prefixes='exsl'><xsl:template match='xsl:stylesheet'/><xsl:template match='/'>"
				+ "<exsl:document href='\(folder.path)/\(name)' method='text'>written</exsl:document><r/></xsl:template></xsl:stylesheet>"
		}
		let xml = XMLs()
		let d = try xml.open("<a/>")
		#expect(xml.send("XML xslt", ["----": d, "with": stylesheet("given.txt")]).error == nil)
		#expect(try String(contentsOf: folder.appendingPathComponent("given.txt"), encoding: .utf8) == "written")
		let chosen = try xml.open("<?xml-stylesheet type='text/xsl' href='#s'?><!DOCTYPE a [<!ATTLIST xsl:stylesheet id ID #IMPLIED>]><a>"
			+ stylesheet("chosen.txt", id: "id='s' ") + "</a>")
		#expect(xml.send("XML xslt", ["----": chosen]).error?.number == 1535)
		#expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("chosen.txt").path))
		// Folders aren't made either, and a stylesheet that doesn't write is fine.
		let nested = try xml.open("<?xml-stylesheet type='text/xsl' href='#s'?><!DOCTYPE a [<!ATTLIST xsl:stylesheet id ID #IMPLIED>]><a>"
			+ stylesheet("sub/chosen.txt", id: "id='s' ") + "</a>")
		#expect(xml.send("XML xslt", ["----": nested]).error?.number == 1535)
		#expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("sub").path))
		let harmless = try xml.open("<?xml-stylesheet type='text/xsl' href='#s'?><!DOCTYPE a [<!ATTLIST xsl:stylesheet id ID #IMPLIED>]><a>"
			+ "<xsl:stylesheet id='s' version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform'><xsl:template match='/'><r/></xsl:template></xsl:stylesheet></a>")
		#expect(xml.send("XML xslt", ["----": harmless, "rtyp": type("utxt")]).result?.stringValue?.contains("<r/>") == true)
	}

	/// `~` and HFS paths: a stylesheet's path was rebuilt from the text, and a schema's never understood them.
	@Test func scriptPaths() throws {
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		#expect(Validation.url("~/x.xsd") == URL(fileURLWithPath: home + "/x.xsd").absoluteString)
		#expect(Validation.url("http://example.com/x.xsd") == "http://example.com/x.xsd")
		#expect(Validation.url("/tmp/a b.xsd") == "file:///tmp/a%20b.xsd")
		let volume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		#expect(Validation.url("\(volume):tmp:x.xsd") == "file:///tmp/x.xsd")
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("style-\(UUID().uuidString).xsl").resolvingSymlinksInPath()
		try Data(text.utf8).write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }
		let hfs = volume + file.path.replacingOccurrences(of: "/", with: ":")
		let xml = XMLs()
		let d = try xml.open(library)
		#expect(xml.send("XML xslt", ["----": d, "with": hfs, "rtyp": type("utxt")]).result?.stringValue == "Moby-Dick;Les Misérables;")
	}

	/// EXSLT was registered by the first XMLTransform, so a stylesheet compiled before that missed its
	/// `func:function` definitions.
	@Test func compiledStylesheetWithFunctions() throws {
		let xml = XMLs()
		let style = try xml.open("""
		<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:func="http://exslt.org/functions" \
		xmlns:my="urn:my" extension-element-prefixes="func"><xsl:output method="text"/>\
		<func:function name="my:twice"><xsl:param name="x"/><func:result select="$x * 2"/></func:function>\
		<xsl:template match="/"><xsl:value-of select="my:twice(21)"/></xsl:template></xsl:stylesheet>
		""")
		#expect(xml.send("XML pxsl", ["----": style]).error == nil)
		#expect(xml.send("XML xslt", ["----": try xml.open("<a/>"), "with": style, "rtyp": type("utxt")]).result?.stringValue == "42")
	}

	@Test func parameters() throws {
		let xml = XMLs()
		let d = try xml.open(library)
		func label(_ parameters: [String: any AppleEventEncodable]) throws -> String? {
			let t = try #require(xml.send("XML xslt", parameters.merging(["----": d, "with": titles]) { $1 }).result)
			return xml.send("XML geta", ["----": try xml.root(t), "pnam": "label"]).result?.stringValue
		}
		#expect(try label(["varx": ["label", "'Books'"]]) == "Books")
		#expect(try label(["varx": ["label", "count(//book)"]]) == "2")
		#expect(try label(["varx": RecordFields([(.user("label"), NSAppleEventDescriptor(string: "'R'"))])]) == "R")
		#expect(try label(["vaxs": ["label", "It's \"quoted\""]]) == "It's \"quoted\"")
	}

	@Test func nodesStylesheetsAndResults() throws {
		let xml = XMLs()
		let d = try xml.open(library)
		let r = try xml.root(d)
		let book = try #require(xml.send("XML chld", ["----": r, "indx": 2]).result)
		let t = try #require(xml.send("XML xslt", ["----": book, "with": titles]).result)
		#expect(xml.send("XML disx", ["----": t]).result?.stringValue == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\nLes MisérablesHugo1862\n")

		let s = try xml.open(titles)
		xml.send("XML pxsl", ["----": s])
		let compiled = try #require(xml.send("XML xslt", ["----": d, "with": s, "pool": "mtc-x"]).result)
		#expect(xml.send("POOLgpoo", ["----": compiled]).result?.stringValue == "mtc-x")
		#expect(xml.send("XML pxsl", ["----": d]).error == OSAXError(3))

		let plist = """
		<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:template match="/"><plist version="1.0"><dict>\
		<xsl:for-each select="//book"><key><xsl:value-of select="@id"/></key><string><xsl:value-of select="title"/></string></xsl:for-each>\
		</dict></plist></xsl:template></xsl:stylesheet>
		"""
		let p = try #require(xml.send("XML xslt", ["----": d, "with": plist, "rtyp": type("CFob")]).result)
		let values = try #require(xml.send("PLSTdisx", ["----": p]).result.flatMap(RecordFields.init))
		#expect(values[.user("b1")]?.stringValue == "Moby-Dick")

		let file = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-xslt-\(UUID().uuidString).txt")
		defer { try? FileManager.default.removeItem(at: file) }
		#expect(xml.send("XML xslt", ["----": d, "with": text, "kfil": file]).result == nil)
		#expect(try String(contentsOf: file, encoding: .utf8) == "Moby-Dick;Les Misérables;")
	}

	@Test func processingInstructionAndEXSLT() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-xslt-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		try text.write(to: folder.appendingPathComponent("text.xsl"), atomically: true, encoding: .utf8)
		try "<?xml-stylesheet type=\"text/xsl\" href=\"text.xsl\"?><l><title>One</title></l>"
			.write(to: folder.appendingPathComponent("pi.xml"), atomically: true, encoding: .utf8)
		let xml = XMLs()
		let d = try #require(xml.send("XML open", ["----": folder.appendingPathComponent("pi.xml")]).result)
		#expect(xml.send("XML xslt", ["----": d, "rtyp": type("utxt")]).result?.stringValue == "One;")
		let exslt = """
		<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:str="http://exslt.org/strings" \
		extension-element-prefixes="str"><xsl:output method="text"/><xsl:template match="/">\
		<xsl:for-each select="str:tokenize('a,b', ',')"><xsl:value-of select="."/>|</xsl:for-each></xsl:template></xsl:stylesheet>
		"""
		#expect(xml.send("XML xslt", ["----": d, "with": exslt, "rtyp": type("utxt")]).result?.stringValue == "a|b|")
	}

	@Test func quoting() {
		#expect(Stylesheets.quoted("a") == "'a'")
		#expect(Stylesheets.quoted("it's") == "\"it's\"")
		#expect(Stylesheets.quoted("it's \"x\"") == "concat('it', \"'\", 's \"x\"')")
	}
}

struct IndexTests {
	@Test func indexes() throws {
		let xml = XMLs()
		let d = try xml.open("<a><b n='m'/><b n='c'/><b n='z'/><b n='a'/><b n='c'/><b n='q'/></a>")
		xml.send("XML NKey", ["----": "k", "matc": "//b", "use ": "@n", "at  ": d])
		#expect(try [String](appleEventDescriptor: #require(xml.send("XML LKey", ["----": "k", "at  ": d]).result)) == ["m", "c", "q", "z", "a"])
		#expect(try [String](appleEventDescriptor: #require(xml.send("XML LKey", ["----": "k", "at  ": d, "dupl": true]).result)) == ["c"])
		#expect(xml.send("XML LKey", ["----": "k", "at  ": d, "dupl": false]).result?.numberOfItems == 4)
		#expect(xml.send("XML GKey", ["----": "c", "by  ": "k", "at  ": d]).result?.numberOfItems == 2)
		#expect(xml.send("XML GKey", ["----": "x", "by  ": "k", "at  ": d]).result?.numberOfItems == 0)
		#expect(xml.send("XML GKey", ["----": "c", "by  ": "nope", "at  ": d]).error == OSAXError(-1))
		#expect(xml.send("XML NKey", ["----": "e", "matc": "//none", "use ": "@n", "at  ": d]).error == OSAXError(3))
		xml.send("XML NKey", ["----": "k", "matc": "", "use ": "@n", "at  ": d])
		#expect(xml.send("XML LKey", ["----": "k", "at  ": d]).error == OSAXError(-1))
		#expect(xml.send("XML idoc", ["----": d]).error == nil)
	}

	/// Nodes of another document (through `xpath variables`) used to be numbered in this document's table.
	@Test func indexOfAnotherDocumentsNodes() throws {
		let xml = XMLs()
		let a = try xml.open("<a/>")
		let b = try xml.open("<b><c n='x'/><d/></b>")
		let c = try #require(xml.send("XML path", ["----": b, "with": "//c"]).result)
		xml.send("XML NKey", ["----": "k", "matc": "$other", "use ": "@n", "at  ": a, "vars": AppleEventList(["other", c])])
		let found = try #require(xml.send("XML GKey", ["----": "x", "by  ": "k", "at  ": a]).result?.atIndex(1))
		#expect(xml.send("XML gtag", ["----": found]).result?.stringValue == "c")
		#expect(xml.send("XML path", ["----": b, "with": "name(//d)"]).result?.stringValue == "d")
		#expect(xml.send("XML gtag", ["----": try #require(xml.send("XML path", ["----": b, "with": "//d"]).result?.atIndex(1))]).result?.stringValue == "d")
		xml.send("XML clos", ["----": b])
		#expect(xml.send("XML GKey", ["----": "x", "by  ": "k", "at  ": a]).result?.numberOfItems == 0)
	}

	@Test func hashOrder() {
		func order(_ keys: [String]) -> [String] {
			var order = HashOrder()
			keys.forEach { order.insert($0) }
			return order.keys
		}
		#expect(order(["x", "y", "x"]) == ["y", "x"])
		#expect(order(["en", "fr"]) == ["fr", "en"])
		// Enough keys to grow the table: all still there, once.
		let many = (0 ..< 5000).map { "key\($0)" }
		#expect(Set(order(many + many)) == Set(many))
		#expect(order(many).count == many.count)
	}
}

struct LocalizeTests {
	@Test func stringsAndLocalize() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open("<a>x<b>y<c>z</c></b><d/>w</a>"))
		#expect(xml.send("XML DCon", ["----": r]).result?.stringValue == "x%1$sy%2$sz%3$s%4$s%5$sw")
		let texts = try #require(xml.xpath(r, "//text()").result)
		#expect(xml.send("XML DCon", ["----": texts]).result?.numberOfItems == 4)
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-\(UUID().uuidString).strings")
		defer { try? FileManager.default.removeItem(at: file) }
		try "\"y\" = \"Y!\";".write(to: file, atomically: true, encoding: .utf8)
		xml.send("XML LoCo", ["----": texts, "in  ": file])
		xml.send("XML LoCo", ["----": r, "in  ": file])
		#expect(xml.texts(texts) == ["x", "Y!", "z", "w"])
	}
}
