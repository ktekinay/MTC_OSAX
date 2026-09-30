import AppleEventCore
import Foundation
import Testing
@testable import XML

private let dtd = "<!ELEMENT people (person*)><!ELEMENT person (#PCDATA)><!ATTLIST person id ID #REQUIRED>"
private let valid = "<people><person id='p1'>Ann</person><person id='p2'>Bob</person></people>"
private let invalid = "<people><person>Ann</person><extra/></people>"
private let xsd = """
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="people"><xs:complexType><xs:sequence>\
<xs:element name="person" maxOccurs="unbounded"><xs:complexType><xs:simpleContent><xs:extension base="xs:string">\
<xs:attribute name="id" type="xs:ID" use="required"/></xs:extension></xs:simpleContent></xs:complexType></xs:element>\
</xs:sequence></xs:complexType></xs:element></xs:schema>
"""
private let rng = """
<element name="people" xmlns="http://relaxng.org/ns/structure/1.0"><zeroOrMore><element name="person">\
<attribute name="id"><text/></attribute><text/></element></zeroOrMore></element>
"""

/// A temporary folder with files, removed afterwards.
private func withFiles<T>(_ files: [String: String], _ body: (URL) throws -> T) throws -> T {
	let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-valid-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: folder) }
	for (name, text) in files {
		try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}
	return try body(folder)
}

@MainActor
struct DTDValidationTests {
	@Test func documents() throws {
		let xml = XMLs()
		let good = try xml.open("<!DOCTYPE people [\(dtd)]>" + valid)
		#expect(xml.send("XML vali", ["----": good]).error == nil)
		#expect(xml.send("XML lErr").result?.stringValue == "")
		let bad = try xml.open("<!DOCTYPE people [\(dtd)]>" + invalid)
		#expect(xml.send("XML vali", ["----": bad]).error == OSAXError(504))
		#expect(xml.send("XML lErr").result?.stringValue?.contains("No declaration for element extra") == true)
		#expect(xml.send("XML vali", ["----": bad, "ErLe": 3]).error == nil)
		#expect(xml.send("XML vali", ["----": try xml.open(valid)]).error == OSAXError(522))
	}

	@Test func elements() throws {
		let xml = XMLs()
		let r = try xml.root(xml.open("<!DOCTYPE people [\(dtd)]>" + valid))
		#expect(xml.send("XML vali", ["----": r]).error == nil)
		#expect(xml.send("XML vali", ["----": try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)]).error == nil)
		// A repeated ID inside the element still counts.
		let text = "<!DOCTYPE people [\(dtd)]><people><person id='p1'>A</person><person id='p1'>B</person></people>"
		let repeated = try xml.root(#require(xml.send("XML open", ["from": text, "ErLe": 3]).result))
		#expect(xml.send("XML vali", ["----": repeated]).error != nil)
	}

	@Test func against() throws {
		try withFiles(["people.dtd": dtd, "bad.dtd": "<!ELEMENT people (person*>"]) { folder in
			let xml = XMLs()
			let good = try xml.open(valid)
			#expect(xml.send("XML vali", ["----": good, "agai": folder.appendingPathComponent("people.dtd")]).error == nil)
			#expect(xml.send("XML vali", ["----": good, "agai": folder.appendingPathComponent("people.dtd").path]).error == nil)
			#expect(xml.send("XML vali", ["----": try xml.open(invalid), "agai": folder.appendingPathComponent("people.dtd")]).error == OSAXError(504))
			#expect(xml.send("XML vali", ["----": good, "agai": folder.appendingPathComponent("bad.dtd")]).error == OSAXError(55))
			#expect(xml.send("XML vali", ["----": good, "agai": folder.appendingPathComponent("nope.dtd")]).error == OSAXError(1549))
			#expect(xml.send("XML lErr").result?.stringValue?.hasPrefix("failed to load external entity") == true)
		}
	}

	@Test func checkDTD() throws {
		try withFiles(["people.dtd": dtd]) { folder in
			let xml = XMLs()
			#expect(xml.send("XML Pdtd", ["----": folder.appendingPathComponent("people.dtd")]).error == nil)
			#expect(xml.send("XML Pdtd", ["----": folder.appendingPathComponent("people.dtd").path]).error == nil)
			#expect(xml.send("XML Pdtd", ["----": dtd]).error == nil)
			#expect(xml.send("XML Pdtd", ["----": "<!ELEMENT a (b>"]).error == OSAXError(55))
			#expect(xml.send("XML lErr").result?.stringValue?.hasPrefix("line 1\n") == true)
		}
	}
}

@MainActor
struct SchemaValidationTests {
	@Test func xmlSchema() throws {
		try withFiles(["people.xsd": xsd, "located.xml": "<people xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:noNamespaceSchemaLocation='people.xsd'><person>A</person></people>"]) { folder in
			let xml = XMLs()
			let schema = folder.appendingPathComponent("people.xsd")
			#expect(xml.send("XML Schm", ["----": try xml.open(valid), "With": schema]).error == nil)
			#expect(xml.send("XML Schm", ["----": try xml.open(valid), "With": xsd]).error == nil)
			#expect(xml.send("XML Schm", ["----": try xml.open(valid), "With": try xml.open(xsd)]).error == nil)
			#expect(xml.send("XML Schm", ["----": try xml.open(invalid), "With": schema]).error == OSAXError(1868))
			#expect(xml.send("XML Schm", ["----": try xml.root(xml.open(valid)), "With": schema]).error == nil)
			let located = try #require(xml.send("XML open", ["----": folder.appendingPathComponent("located.xml")]).result)
			#expect(xml.send("XML Schm", ["----": located]).error == OSAXError(1868))
			#expect(xml.send("XML Schm", ["With": schema]).error == nil)
			#expect(xml.send("XML Schm", ["With": "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'><xs:element name='a' type='xs:nothing'/></xs:schema>"]).error == OSAXError(3004))
			#expect(xml.send("XML Schm", ["With": folder.appendingPathComponent("nope.xsd")]).error == OSAXError(1549))
			#expect(xml.send("XML Schm").error == .missingParameter)
		}
	}

	@Test func relaxNG() throws {
		let xml = XMLs()
		#expect(xml.send("XML rlax", ["----": try xml.open(valid), "With": rng]).error == nil)
		#expect(xml.send("XML rlax", ["----": try xml.open(valid), "With": try xml.open(rng)]).error == nil)
		#expect(xml.send("XML rlax", ["----": try xml.open(invalid), "With": rng]).error == OSAXError(24))
		#expect(xml.send("XML rlax", ["----": try xml.root(xml.open(valid)), "With": rng]).error == nil)
		#expect(xml.send("XML rlax", ["With": rng]).error == nil)
		#expect(xml.send("XML rlax", ["With": "<element name='a' xmlns='http://relaxng.org/ns/structure/1.0'><nothing/></element>"]).error == OSAXError(1115))
		#expect(xml.send("XML rlax", ["----": try xml.open(valid)]).error == .missingParameter)
	}
}

@MainActor
struct IDAndNameTests {
	@Test func ids() throws {
		let xml = XMLs()
		let d = try xml.open("<doc><sec xml:id='s1'>One</sec><sec xml:id='s2'>Two<sub xml:id='s3'>Three</sub></sec><sec>Four</sec></doc>")
		let r = try xml.root(d)
		#expect(xml.send("XML gttx", ["----": try #require(xml.send("XML geti", ["----": d, "xlmi": "s3"]).result)]).result?.stringValue == "Three")
		#expect(xml.send("XML geti", ["----": r, "xlmi": "zz"]).error == OSAXError(-2763))
		let list = try #require(xml.send("XML geti", ["----": d, "xlmi": ["s1", "zz"]]).result)
		#expect(list.numberOfItems == 2)
		#expect(XMLCommands.isMissingValue(try #require(list.atIndex(2))))
		let first = try #require(xml.send("XML chld", ["----": r, "indx": 1]).result)
		#expect(xml.send("XML geID", ["----": first]).result?.stringValue == "s1")
		#expect(xml.send("XML geID", ["----": try #require(xml.send("XML chld", ["----": r, "indx": 3]).result)]).error == OSAXError(-2763))
		#expect(xml.send("XML geID", ["----": d]).error == OSAXError(-2763))
		// IDs from the DTD.
		let people = try xml.open("<!DOCTYPE people [\(dtd)]>" + valid)
		#expect(xml.send("XML gttx", ["----": try #require(xml.send("XML geti", ["----": people, "xlmi": "p2"]).result)]).result?.stringValue == "Bob")
	}

	/// Changing an ID attribute's text didn't change libxml2's table of IDs, so the old ID still led to the
	/// attribute, and after it was removed, to freed memory (AddressSanitizer: heap-use-after-free).
	@Test func changedIDs() throws {
		let xml = XMLs()
		let d = try xml.open("<doc><a xml:id='x'/><b xml:id='p'/><c xml:id='q'/></doc>")
		func id(_ value: String) -> OSAXError? { xml.send("XML geti", ["----": d, "xlmi": value]).error }
		func attribute(_ path: String) throws -> NSAppleEventDescriptor {
			try #require(xml.send("XML path", ["----": d, "with": path]).result?.atIndex(1))
		}
		// Set, appended to, and emptied (by removing its text).
		#expect(xml.send("XML sttx", ["----": try attribute("//a/@xml:id"), "to  ": "y"]).error == nil)
		#expect(xml.send("XML ApTx", ["----": "2", "at  ": try attribute("//b/@xml:id")]).error == nil)
		let text = try #require(xml.send("XML chld", ["----": try attribute("//c/@xml:id"), "indx": 1]).result)
		#expect(xml.send("XML remo", ["----": text]).error == nil)
		#expect(id("x") == XML.notFound && id("p") == XML.notFound && id("q") == XML.notFound)
		#expect(id("y") == nil && id("p2") == nil)
		// Then the elements go: the IDs go with them.
		xml.send("XML remo", ["----": try xml.root(d)])
		for value in ["x", "y", "p", "p2", "q", ""] {
			#expect(id(value) == XML.notFound)
		}
	}

	@Test func names() {
		let xml = XMLs()
		#expect(xml.send("XML Isnm", ["----": "a:b"]).result?.booleanValue == true)
		#expect(xml.send("XML Isnc", ["----": "a:b"]).result?.booleanValue == false)
		#expect(xml.send("XML Isnm", ["----": "1a"]).result?.booleanValue == false)
		#expect(xml.send("XML Isnm", ["----": ""]).result?.booleanValue == false)
		#expect(xml.send("XML Isnm", ["----": "é"]).result?.booleanValue == true)
		#expect(xml.send("XML Isnm", ["----": ["a", "b"]]).result?.booleanValue == true)
		#expect(xml.send("XML Isnm", ["----": ["a", "1"]]).result?.booleanValue == false)
	}

	@Test func outline() throws {
		let xml = XMLs()
		let d = try xml.open("<a x='1'><b>t</b><b/><!--c--><c><d/></c></a>")
		#expect(xml.send("XML du  ", ["----": d]).result?.stringValue == "/\na\n\tb\n\tb\n\tc\n\t\td\n")
		#expect(xml.send("XML du  ", ["----": try xml.root(d)]).result?.stringValue == "a\n\tb\n\tb\n\tc\n\t\td\n")
	}
}
