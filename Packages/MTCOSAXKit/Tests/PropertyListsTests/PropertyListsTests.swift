import AppleEventCore
import Foundation
import Testing
@testable import PropertyLists

/// Sends commands to one set of PropertyList and Pool commands, sharing their documents.
@MainActor
final class Plists {
	let store = DocumentStore()
	private let dispatcher = CommandDispatcher()

	init() {
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

	func new(_ value: any AppleEventEncodable) throws -> NSAppleEventDescriptor {
		try #require(send("PLSTmake", ["----": value]).result)
	}

	func xml(_ reference: NSAppleEventDescriptor) -> String {
		(send("PLSTDISP", ["----": reference]).result?.stringValue ?? "")
			.components(separatedBy: "<plist version=\"1.0\">\n").last!
			.replacingOccurrences(of: "\n</plist>\n", with: "")
			.replacingOccurrences(of: "\n", with: "")
			.replacingOccurrences(of: "\t", with: "")
	}
}

func record(_ fields: KeyValuePairs<String, any AppleEventEncodable>) -> NSAppleEventDescriptor {
	RecordFields(fields.map { (.user($0.key), $0.value.appleEventDescriptor) }).appleEventDescriptor
}

@MainActor
struct PropertyListsCommandTests {
	@Test func everyCommandIsRegistered() {
		// Satimage's 29 PropertyList and 3 Pool commands, and MTC_OSAX's 4 for YAML and TOML.
		#expect(PropertyLists.commands().count == 36)
	}
}

@MainActor
struct DocumentTests {
	@Test func newGetAndClose() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1, "b": AppleEventList(["x", 2.5])]))
		#expect(plists.xml(p) == "<dict><key>a</key><integer>1</integer><key>b</key><array><string>x</string><real>2.5</real></array></dict>")
		#expect(plists.send("PLSTdisp", ["----": p]).result?.stringValue == "dictionary")
		#expect(plists.store.hasOpenDocuments)
		plists.send("PLSTclos", ["----": p])
		#expect(!plists.store.hasOpenDocuments)
		#expect(plists.send("PLSTdisx", ["----": p]).error == OSAXError(-1728))
		#expect(plists.send("PLSTclos", ["----": p]).error == OSAXError(-1728))
		#expect(plists.send("PLSTdisx", ["----": "text"]).error == .coercionFailed)
	}

	/// An element number beyond Int's range used to trap.
	@Test func forgedReferences() throws {
		let plists = Plists()
		_ = try plists.new(record(["a": 1]))
		func reference(_ hex: String) -> NSAppleEventDescriptor {
			let bytes = stride(from: 0, to: hex.count, by: 2).map {
				UInt8(hex.dropFirst($0).prefix(2), radix: 16)!
			}
			return NSAppleEventDescriptor(descriptorType: DocumentStore.referenceType, data: Data(bytes))!
		}
		#expect(plists.send("PLSTdisx", ["----": reference("010000004D544370FFFFFFFFFFFFFFFF")]).error == OSAXError(-1728))
		#expect(plists.send("PLSTdisx", ["----": reference("010000004D544370FFFFFFFFFFFFFF")]).error == OSAXError(-1728))
	}

	@Test func retainNeedsASecondClose() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1]))
		plists.send("PLSTReta", ["----": p])
		plists.send("PLSTclos", ["----": p])
		#expect(plists.send("PLSTcunt", ["----": p]).result?.int32Value == 1)
		plists.send("PLSTclos", ["----": p])
		#expect(!plists.store.hasOpenDocuments)
	}

	@Test func openSaveAndURLs() throws {
		let plists = Plists()
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plists-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let file = folder.appendingPathComponent("a b.plist")
		let p = try plists.new(record(["a": 1]))
		#expect(plists.send("PLSTgurl", ["----": p]).error == OSAXError(-2763))
		#expect(plists.send("PLSTsave", ["----": p]).error == .missingParameter)
		plists.send("PLSTsave", ["----": p, "kfil": file.path, "bina": true])
		#expect(plists.send("PLSTgurl", ["----": p]).result?.stringValue == file.path)
		plists.send("PLSTclos", ["----": p])

		let opened = try #require(plists.send("PLSTopen", ["----": file]).result)
		#expect(plists.send("PLSTIsBi", ["----": opened]).result?.booleanValue == true)
		#expect(plists.send("PLSTgurl", ["----": opened, "rtyp": NSAppleEventDescriptor(typeCode: typeUnicodeText)]).result?.stringValue?.hasSuffix("/a%20b.plist") == true)
		#expect(plists.send("PLSTgurl", ["----": opened, "pare": true]).result?.stringValue?.hasSuffix("/") == true)
		#expect(plists.send("PLSTgfur", ["----": file]).result != nil)
		plists.send("PLSTseta", ["----": opened, "key ": "a", "to  ": 2])
		plists.send("PLSTsave", ["----": opened])
		plists.send("PLSTclos", ["----": opened])
		let reopened = try #require(plists.send("PLSTopen", ["----": file]).result)
		#expect(plists.send("PLSTdisx", ["----": reopened, "key ": "a"]).result?.int32Value == 2)
		#expect(plists.send("PLSTIsBi", ["----": reopened]).result?.booleanValue == true)

		#expect(plists.send("PLSTopen", ["----": folder.appendingPathComponent("nope.plist")]).error == OSAXError(-43))
		try Data("not a plist".utf8).write(to: folder.appendingPathComponent("bad.plist"))
		#expect(plists.send("PLSTopen", ["----": folder.appendingPathComponent("bad.plist")]).error == OSAXError(-1))
		#expect(plists.send("PLSTopen", ["from": "<plist version=\"1.0\"><array><string>x</string></array></plist>"]).result != nil)
	}

	@Test func poolsAndIdentifiers() throws {
		let plists = Plists()
		#expect(plists.send("POOLpool", ["----": "work"]).result?.stringValue == "")
		let p = try plists.new(record(["a": 1]))
		#expect(plists.send("POOLgpoo", ["----": p]).result?.stringValue == "work")
		#expect(plists.send("PLSTList").result?.numberOfItems == 1)
		#expect(plists.send("PLSTList", ["----": ""]).result?.numberOfItems == 0)
		#expect(plists.send("PLSTSDbK", ["----": p, "to  ": "mine"]).result == nil)
		#expect(plists.send("PLSTSDbK", ["----": p, "to  ": "mine"]).result?.stringValue == "mine")
		#expect(plists.send("PLSTGDbK", ["----": "mine"]).result != nil)
		#expect(plists.send("PLSTGDbK", ["----": "mine", "pool": ""]).error == OSAXError(-2763))
		let number = try #require(plists.send("PLSTgID ", ["----": p]).result?.int32Value)
		#expect(plists.send("PLSTgfID", ["----": Int(number)]).result != nil)
		plists.send("POOLdpoo")
		#expect(plists.send("PLSTdisx", ["----": p]).error == OSAXError(-1728))
		#expect(plists.send("POOLpool", ["----": ""]).result?.stringValue == "work")
	}

	/// DeletePool releases each document once, as SatimageOSAX did: a retained one stays until its last close.
	@Test func deletePoolRespectsRetain() throws {
		let plists = Plists()
		let p = try #require(plists.send("PLSTmake", ["----": record(["a": 1]), "pool": "kept"]).result)
		plists.send("PLSTReta", ["----": p])
		plists.send("POOLdpoo", ["----": "kept"])
		#expect(plists.send("PLSTdisx", ["----": p, "key ": "a"]).result?.int32Value == 1)
		#expect(plists.send("POOLgpoo", ["----": p]).result?.stringValue == "kept")
		plists.send("PLSTclos", ["----": p])
		#expect(plists.send("PLSTdisx", ["----": p, "key ": "a"]).error == OSAXError(-1728))
	}
}

@MainActor
struct ValueTests {
	@Test func typesRoundTrip() throws {
		let plists = Plists()
		let date = Date(timeIntervalSinceReferenceDate: 0)
		let p = try plists.new(record(["t": "é", "i": 7, "r": 2.5, "b": true, "d": date, "l": [1, 2]]))
		let value = try #require(plists.send("PLSTdisx", ["----": p]).result)
		let fields = try #require(RecordFields(value))
		#expect(fields[.user("t")]?.stringValue == "é")
		#expect(fields[.user("i")]?.int32Value == 7)
		#expect(fields[.user("r")]?.doubleValue == 2.5)
		#expect(fields[.user("b")]?.booleanValue == true)
		#expect(fields[.user("d")]?.dateValue == date)
		#expect(fields[.user("l")]?.numberOfItems == 2)
	}

	@Test func otherValuesAreFlattened() throws {
		let plists = Plists()
		let alias = try #require(NSAppleEventDescriptor.alias(URL(fileURLWithPath: "/private/tmp")))
		let fields: [(key: RecordFields.Key, value: NSAppleEventDescriptor)] = [(.user("f"), alias), (.user("m"), .missingValue), (.code("pnam"), NSAppleEventDescriptor(string: "n"))]
		let p = try plists.new(RecordFields(fields))
		#expect(plists.xml(p).contains("<key>«class pnam»</key><string>n</string>"))
		#expect(plists.xml(p).contains("<key>m</key><data>ZGxlMgAAAAB0eXBlAAAABG1zbmc=</data>"))
		let back = try #require(plists.send("PLSTdisx", ["----": p]).result.flatMap(RecordFields.init))
		#expect(back[.user("f")]?.descriptorType == typeAlias)
		#expect(back[.user("f")]?.coerce(toDescriptorType: typeFileURL)?.fileURLValue?.path == "/private/tmp")
		#expect(back[.user("m")]?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		#expect(back[.code("pnam")]?.stringValue == "n")
	}

	@Test func largeIntegersBecomeReals() throws {
		let plists = Plists()
		let p = try #require(plists.send("PLSTopen", ["from": "<plist version=\"1.0\"><integer>1099511627776</integer></plist>"]).result)
		#expect(plists.send("PLSTdisx", ["----": p]).result?.doubleValue == 1_099_511_627_776)
	}

	@Test func untypedAndRawData() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1]))
		plists.send("PLSTseta", ["----": p, "key ": "a", "to  ": 5, "flat": false])
		#expect(plists.xml(p) == "<dict><key>a</key><data>BQAAAA==</data></dict>")
		#expect(plists.send("PLSTdisx", ["----": p, "key ": "a", "rtyp": NSAppleEventDescriptor(typeCode: typeSInt32)]).result?.int32Value == 5)
		let untyped = try #require(plists.send("PLSTmake", ["----": record(["a": 5, "l": [1]]), "flat": false]).result)
		#expect(plists.xml(untyped).contains("<key>a</key><data>BQAAAA==</data>"))
		#expect(plists.xml(untyped).contains("<key>l</key><array><data>AQAAAA==</data></array>"))
	}

	@Test func keysKeepCoreFoundationOrder() throws {
		let plists = Plists()
		// SatimageOSAX returned these keys in this order (its Core Foundation dictionaries' hashing).
		let p = try plists.new(record(["t": 1, "i": 1, "r": 1, "b": 1, "d": 1, "l": 1, "rec": 1]))
		#expect(plists.send("PLSTJSON", ["----": p]).result?.stringValue == #"{"rec":1,"t":1,"l":1,"d":1,"i":1,"r":1,"b":1}"#)
		#expect(plists.send("PLSTgkey", ["----": p]).result?.numberOfItems == 7)
	}
}

@MainActor
struct SelectorTests {
	@Test func paths() throws {
		#expect(try Selector.steps("a/b[2][3]/c") == [.key("a"), .key("b"), .index(2), .index(3), .key("c")])
		#expect(try Selector.steps("/a/") == [.key("a")])
		#expect(throws: OSAXError(-1)) { try Selector.steps("[1]") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("a[+1]") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("a[x") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("") }
		// Indices start at 1; the smallest Int trapped when 1 was taken from it.
		#expect(throws: OSAXError(-1)) { try Selector.steps("a[0]") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("a[-9223372036854775808]") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("a[99999999999999999999]") }
		let plists = Plists()
		let p = try plists.new(record(["l": ["a", "b"]]))
		for code in ["PLSTdisx", "PLSTchld", "PLSTremc"] {
			#expect(plists.send(code, ["----": p, "by  ": "l[-9223372036854775808]"]).error == OSAXError(-1), "\(code)")
		}
		#expect(plists.send("PLSTdisx", ["----": p, "by  ": "l[9223372036854775807]"]).error == OSAXError(-1))
		// A new child goes in one place: no key, or several, is -1 (no keys trapped; more than one used the first).
		#expect(plists.send("PLSTaddc", ["----": "v", "at  ": p, "key ": [String]()]).error == OSAXError(-1))
		#expect(plists.send("PLSTaddc", ["----": "v", "at  ": p, "key ": ["x", "y"]]).error == OSAXError(-1))
		#expect(plists.send("PLSTaddc", ["----": "v", "at  ": p, "key ": ["x"]]).error == nil)
		#expect(plists.send("PLSTdisx", ["----": p, "key ": "x"]).result?.stringValue == "v")
	}

	@Test func childrenAndErrors() throws {
		let plists = Plists()
		let p = try plists.new(record(["d": record(["x": 1]), "l": ["a", "b"], "s": "text"]))
		let get = { (parameters: [String: any AppleEventEncodable]) in plists.send("PLSTdisx", parameters.merging(["----": p]) { $1 }) }
		#expect(get(["by  ": "d/x"]).result?.int32Value == 1)
		#expect(get(["by  ": "l[2]"]).result?.stringValue == "b")
		#expect(get(["by  ": "d/"]).result?.numberOfItems == 1)
		#expect(get(["by  ": "d/nope"]).error == OSAXError(-2763))
		#expect(get(["by  ": "nope/x"]).error == OSAXError(-1))
		#expect(get(["key ": "nope"]).error == OSAXError(-1728))
		#expect(get(["indx": 1]).error == OSAXError(-1))
		#expect(get(["key ": "d", "indx": 1]).error == OSAXError(-1))
		#expect(get(["key ": ["s", "nope"]]).result?.atIndex(2)?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		let list = try #require(plists.send("PLSTchld", ["----": p, "key ": "l"]).result)
		#expect(plists.send("PLSTchld", ["----": list, "indx": 3]).error == OSAXError(-1))
		#expect(plists.send("PLSTchld", ["----": list, "key ": "a"]).error == OSAXError(-1))
		#expect(plists.send("PLSTchld", ["----": p]).result?.numberOfItems == 3)
		#expect(plists.send("PLSTgkey", ["----": list]).error == OSAXError(-10001))
		let text = try #require(plists.send("PLSTchld", ["----": p, "key ": "s"]).result)
		#expect(plists.send("PLSTcunt", ["----": text]).error == OSAXError(-1))
	}
}

@MainActor
struct ChangeTests {
	@Test func setNewChildAndRemove() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1, "l": ["x", "y"], "d": record(["e": 1])]))
		let list = try #require(plists.send("PLSTchld", ["----": p, "key ": "l"]).result)
		plists.send("PLSTseta", ["----": list, "indx": 3, "to  ": "z"])
		plists.send("PLSTaddc", ["----": "w", "at  ": list, "indx": 1])
		#expect(plists.send("PLSTdisx", ["----": list]).result?.numberOfItems == 4)
		#expect(plists.send("PLSTseta", ["----": list, "indx": 9, "to  ": "q"]).error == OSAXError(-1))
		plists.send("PLSTseta", ["----": p, "by  ": "d/f", "to  ": 6])
		#expect(plists.send("PLSTseta", ["----": p, "by  ": "q/r", "to  ": 7]).error == OSAXError(-1))
		plists.send("PLSTseta", ["----": p, "key ": ["a", "b"], "to  ": AppleEventList([5, NSAppleEventDescriptor.missingValue])])
		#expect(!plists.xml(p).contains("<key>b</key>"))
		plists.send("PLSTseta", ["----": p, "key ": ["a", "b"], "to  ": AppleEventList([5, NSAppleEventDescriptor.missingValue]), "Supp": false])
		#expect(plists.xml(p).contains("<key>b</key><data>"))

		let d = try #require(plists.send("PLSTchld", ["----": p, "key ": "d"]).result)
		plists.send("PLSTseta", ["----": p, "key ": "copy", "to  ": d])
		plists.send("PLSTseta", ["----": d, "key ": "e", "to  ": 99])
		#expect(plists.send("PLSTdisx", ["----": p, "by  ": "copy/e"]).result?.int32Value == 1)
		plists.send("PLSTremc", ["----": p, "key ": "d"])
		#expect(plists.send("PLSTdisx", ["----": d]).error == OSAXError(-1728))
		#expect(plists.send("PLSTremc", ["----": p, "key ": "nope"]).error == nil)
	}

	@Test func addEqualExistAndMatch() throws {
		let plists = Plists()
		let r = try plists.new(record(["a": 1, "b": 2]))
		plists.send("PLSTconc", ["----": record(["b": 3, "c": 4]), "afte": r])
		#expect(plists.xml(r) == "<dict><key>a</key><integer>1</integer><key>b</key><integer>2</integer><key>c</key><integer>4</integer></dict>")
		plists.send("PLSTconc", ["----": record(["b": 3]), "befo": r])
		#expect(plists.send("PLSTdisx", ["----": r, "key ": "b"]).result?.int32Value == 3)
		let array = try plists.new(["a", "b"])
		plists.send("PLSTconc", ["----": ["c"], "befo": array])
		#expect(plists.xml(array) == "<array><string>c</string><string>a</string><string>b</string></array>")
		#expect(plists.send("PLSTconc", ["----": record(["x": 1]), "afte": array]).error == .coercionFailed)

		#expect(plists.send("PLSTequa", ["----": try plists.new(record(["a": 1])), "to  ": try plists.new(record(["a": 1.0]))]).result?.booleanValue == true)
		#expect(plists.send("PLSTcont", ["----": "b", "in  ": array]).result?.atIndex(1)?.int32Value == 3)
		#expect(plists.send("PLSTcont", ["----": ["a", "c"], "in  ": array, "List": true]).result?.numberOfItems == 2)
		#expect(plists.send("PLSTcont", ["----": 4, "in  ": r]).result?.atIndex(1)?.stringValue == "c")

		let people = try plists.new(AppleEventList([record(["age": 30, "first": "Ann"]), record(["age": 40]), "text"]))
		#expect(plists.send("PLSTmatc", ["----": people, "key ": "age"]).result?.numberOfItems == 2)
		#expect(plists.send("PLSTmatc", ["----": people, "key ": "age", "to  ": 40]).result?.numberOfItems == 1)
		#expect(plists.send("PLSTmatc", ["----": people, "by  ": "first"]).result?.numberOfItems == 1)
	}
}

/// Unsigned integers past Int64.max, which a property list file can hold, were read as their bits, negative.
@MainActor
struct LargeIntegerTests {
	@Test func unsignedIntegers() throws {
		let plists = Plists()
		let text = "<plist version=\"1.0\"><array><integer>18446744073709551615</integer><integer>9223372036854775807</integer><integer>-5</integer></array></plist>"
		let document = try PropertyLists.document(Data(text.utf8), pool: nil, store: plists.store)
		let values = document.root.children.map(\.content)
		guard case let .real(big) = values[0], case let .integer(max) = values[1], case let .integer(negative) = values[2] else {
			Issue.record("\(values)")
			return
		}
		#expect(big == 18446744073709551615.0 && max == Int64.max && negative == -5)
	}
}

@MainActor
struct JSONTests {
	@Test func toJSON() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1, "l": ["x", "y"], "d": record(["e": 1])]))
		#expect(plists.send("PLSTJSON", ["----": p]).result?.stringValue == #"{"a":1,"l":["x","y"],"d":{"e":1}}"#)
		#expect(plists.send("PLSTJSON", ["----": p, "smar": true]).result?.stringValue == "{\n\t\"a\": 1,\n\t\"l\": [\n\t\t\"x\",\n\t\t\"y\"\n\t],\n\t\"d\": {\n\t\t\"e\": 1\n\t}\n}")
		#expect(plists.send("PLSTJSON", ["----": p, "rplc": "function(k, v) { return typeof v === 'number' ? v * 10 : v; }"]).result?.stringValue == #"{"a":10,"l":["x","y"],"d":{"e":10}}"#)
		// A `__proto__` key is a key (it set the object's prototype instead, and was left out); NaN is null.
		let proto = try #require(plists.send("PLSTNOSJ", ["----": #"{"__proto__":{"x":1},"a":1}"#]).result)
		#expect(plists.send("PLSTJSON", ["----": proto]).result?.stringValue?.contains(#""__proto__":{"x":1}"#) == true)
		let seen = plists.send("PLSTJSON", ["----": proto, "rplc": "function(k, v) { return k === 'x' ? 'own' : v; }"]).result?.stringValue
		#expect(seen?.contains(#""x":"own""#) == true)
		#expect(plists.send("PLSTJSON", ["----": try plists.new(AppleEventList([Double.nan, 1]))]).result?.stringValue == "[null,1]")
		#expect(plists.send("PLSTJSON", ["----": p, "rplc": "not ("]).error == OSAXError(-1))
		#expect(plists.send("PLSTToJa", ["----": p]).result?.stringValue == #"{"a":1, "l":["x", "y"], "d":{"e":1}}"#)
		let dated = try plists.new(record(["w": Date(timeIntervalSince1970: 0), "b": NSAppleEventDescriptor.missingValue]))
		#expect(plists.send("PLSTJSON", ["----": dated]).result?.stringValue?.contains(#""w":"1970-01-01T00:00:00Z""#) == true)
		// missing value used to be written as base64 of its flattened descriptor.
		#expect(plists.send("PLSTJSON", ["----": dated]).result?.stringValue?.contains(#""b":null"#) == true)
		let back = try #require(plists.send("PLSTNOSJ", ["----": #"{"n":null,"l":[1,null]}"#]).result)
		#expect(plists.send("PLSTJSON", ["----": back]).result?.stringValue == #"{"n":null,"l":[1,null]}"#)
	}

	@Test func fromJSON() throws {
		let plists = Plists()
		let p = try #require(plists.send("PLSTNOSJ", ["----": #"{"i": 3, "n": null, "a": [true]}"#]).result)
		#expect(plists.xml(p).contains("<key>i</key><real>3</real>"))
		#expect(plists.send("PLSTdisx", ["----": p, "key ": "n"]).result?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		#expect(plists.send("PLSTNOSJ", ["----": "{not json}"]).error == OSAXError(-1))
		#expect(plists.send("PLSTNOSJ", ["----": ""]).error == OSAXError(-1))
	}

	/// Many records there and back, as JavaScriptCore converts them all at once.
	@Test func roundTripOfManyRecords() throws {
		let plists = Plists()
		let records = (1 ... 2_000).map { record(["id": $0, "name": "item \($0)", "tags": ["a", "b"], "price": Double($0) / 4]) }
		let p = try plists.new(records)
		let json = try #require(plists.send("PLSTJSON", ["----": p]).result?.stringValue)
		#expect(json.contains(#""name":"item 2000""#))
		let q = try #require(plists.send("PLSTNOSJ", ["----": json]).result)
		#expect(plists.send("PLSTJSON", ["----": q]).result?.stringValue == json)
		#expect(plists.xml(q).contains("<key>id</key><real>2000</real>"))
	}
}

@MainActor
struct FilterIntoTests {
	@Test func addsEntries() throws {
		let plists = Plists()
		let p = try plists.new(record(["z": 0]))
		try PropertyLists.add([("a", "1"), ("b", ["2", "3"])], to: p, store: plists.store)
		#expect(plists.xml(p).contains("<key>b</key><array><string>2</string><string>3</string></array>"))
		#expect(throws: OSAXError(-1)) { try PropertyLists.add([("a", "1")], to: try plists.new(["x"]), store: plists.store) }
	}
}

@MainActor
struct PlistKeyTests {
	@Test func codeKeys() {
		#expect(RecordFields.Key(plistKey: "«class pnam»") == .code("pnam"))
		#expect(RecordFields.Key(plistKey: "«class ab»") == .user("«class ab»"))
		// This crashed the app when the record was made.
		#expect(RecordFields.Key(plistKey: "«class 😀😀😀😀»") == .user("«class 😀😀😀😀»"))
	}

	/// A property list file with such a key.
	@Test func fileWithOddClassKey() throws {
		let plists = Plists()
		let text = "<plist version=\"1.0\"><dict><key>«class 😀😀😀😀»</key><integer>1</integer></dict></plist>"
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("key-\(UUID().uuidString).plist")
		try Data(text.utf8).write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }
		let p = try #require(plists.send("PLSTopen", ["----": file]).result)
		let value = try #require(plists.send("PLSTdisx", ["----": p]).result)
		#expect(RecordFields(value)?[.user("«class 😀😀😀😀»")]?.int32Value == 1)
	}
}

@MainActor
struct ElementTableTests {
	/// Every element ever made kept an entry in its document's table.
	@Test func tableStaysSmall() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1]))
		for value in 0 ..< 5000 {
			plists.send("PLSTseta", ["----": p, "key ": "a", "to  ": AppleEventList([value, "x"])])
		}
		let document = try plists.store.node(p).document
		#expect(document.elements.count < 2100)
		#expect(plists.xml(p) == "<dict><key>a</key><array><integer>4999</integer><string>x</string></array></dict>")
	}
}

@MainActor
struct IntegerTests {
	/// 64-bit integers used to be stored as 0.
	@Test func sixtyFourBits() throws {
		let plists = Plists()
		var value: Int64 = 1 << 40
		let big = try #require(NSAppleEventDescriptor(descriptorType: typeSInt64, bytes: &value, length: 8))
		let p = try plists.new(AppleEventList([big]))
		#expect(plists.xml(p) == "<array><integer>1099511627776</integer></array>")
	}
}

@MainActor
struct FlattenedDescriptorTests {
	private func bytes(_ hex: String) -> Data {
		Data(stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! })
	}

	@Test func roundTrip() {
		let flat = PropertyLists.flatten(NSAppleEventDescriptor(string: "hi"))
		#expect(flat == bytes("646C653200000000757478740000000400680069"))
		#expect(PropertyLists.unflatten(flat)?.stringValue == "hi")
	}

	/// Data from a file can claim more bytes than it has; AEUnflattenDesc read past the end (returning heap memory,
	/// or crashing), so such data is now just data.
	@Test func lengthBeyondTheData() {
		#expect(PropertyLists.unflatten(bytes("646C653200000000757478740010000000680069")) == nil)
		#expect(PropertyLists.unflatten(bytes("646C6532000000007574787400000004006800")) == nil)
		#expect(PropertyLists.unflatten(bytes("646C6532")) == nil)
	}
}

/// Deep nesting used to recurse until the stack ran out (a JSON file of a million `[`s crashed the app). Runs on the
/// main thread, as the app runs commands, with its 8 MB stack (other test threads have much smaller ones).
@MainActor
struct NestingTests {
	/// A binary property list whose objects are `objects` (each already encoded), with 4-byte offsets and 2-byte
	/// references, the last object at the top.
	private func binaryPlist(_ objects: [[UInt8]]) -> Data {
		var data = Data("bplist00".utf8)
		var offsets: [Int] = []
		for object in objects {
			offsets.append(data.count)
			data.append(contentsOf: object)
		}
		let table = data.count
		for offset in offsets { withUnsafeBytes(of: UInt32(offset).bigEndian) { data.append(contentsOf: $0) } }
		data.append(contentsOf: [0, 0, 0, 0, 0, 0, 4, 2])
		for value in [objects.count, objects.count - 1, table] { withUnsafeBytes(of: UInt64(value).bigEndian) { data.append(contentsOf: $0) } }
		return data
	}

	private func reference(_ index: Int) -> [UInt8] { [UInt8(index >> 8), UInt8(index & 0xFF)] }

	/// A script could build a document deeper than a file may be (a CFRef of a deep part put under another deep part,
	/// or one level at a time), until writing it out or reading it ran out of stack.
	@Test func scriptsCantBuildTooDeep() throws {
		let plists = Plists()
		let root = try plists.new(record(["a": 1]))
		var deepest = root
		// Dictionaries down to level 511, whose values are at 512, the most there may be.
		for _ in 1 ... 511 {
			deepest = try #require(plists.send("PLSTaddc", ["----": record(["a": 1]), "at  ": deepest, "key ": "d"]).result)
		}
		#expect(plists.send("PLSTaddc", ["----": record(["a": 1]), "at  ": deepest, "key ": "d"]).error == PropertyLists.tooDeep)
		#expect(plists.send("PLSTseta", ["----": deepest, "key ": "x", "to  ": record(["b": 2])]).error == PropertyLists.tooDeep)
		#expect(plists.send("PLSTaddc", ["----": 1, "at  ": deepest, "key ": "x"]).error == nil)
		// A deep part under a deep part.
		let half = try #require(plists.send("PLSTchld", ["----": root, "by  ": String(repeating: "d/", count: 300)]).result)
		#expect(plists.send("PLSTseta", ["----": half, "key ": "copy", "to  ": root]).error == PropertyLists.tooDeep)
		#expect(plists.send("PLSTconc", ["----": record(["copy": half]), "afte": half]).error == PropertyLists.tooDeep)
		// What fits is fine, and the document can still be written.
		#expect(plists.send("PLSTseta", ["----": half, "key ": "small", "to  ": record(["b": 2])]).error == nil)
		#expect(plists.send("PLSTDISP", ["----": root]).error == nil)
	}

	/// A binary file can use one array in two places, the array holding it in two places, and so on: 200 bytes
	/// stood for 2⁴⁰ values, which PlistOpen went through for days, then ran out of memory making. Or one long
	/// text a thousand times.
	@Test func repeatedValues() throws {
		let plists = Plists()
		func open(_ data: Data) throws -> AppleEventReply {
			let file = FileManager.default.temporaryDirectory.appendingPathComponent("repeated-\(UUID().uuidString).plist")
			try data.write(to: file)
			defer { try? FileManager.default.removeItem(at: file) }
			return plists.send("PLSTopen", ["----": file])
		}
		func doubling(_ levels: Int) -> Data {
			binaryPlist([[0x51, 0x78]] + (1 ... levels).map { [0xA2] + reference($0 - 1) + reference($0 - 1) })
		}
		#expect(doubling(40).count < 500)
		let start = Date()
		#expect(try open(doubling(40)).error == PropertyLists.tooRepetitive)
		#expect(Date().timeIntervalSince(start) < 5)
		// Up to a million repeated values is fine.
		let fine = try #require(open(doubling(10)).result)
		#expect(plists.xml(fine).components(separatedBy: "<string>x</string>").count == 1025)
		#expect(try open(doubling(18)).error == nil)
		#expect(try open(doubling(20)).error == PropertyLists.tooRepetitive)
		// Text: a megabyte in 50 places is fine, in 200 it isn't (100 MB).
		let megabyte = [0x5F, 0x12] + [0x00, 0x10, 0x00, 0x00] + [UInt8](repeating: 0x61, count: 1 << 20)
		func text(_ times: Int) -> Data { binaryPlist([megabyte, [0xAF, 0x11] + reference(times) + (0 ..< times).flatMap { _ in reference(0) }]) }
		#expect(try open(text(50)).error == nil)
		#expect(try open(text(200)).error == PropertyLists.tooRepetitive)
		// Shared arrays count towards the depth wherever they are.
		var objects: [[UInt8]] = [[0xA0]]
		for level in 1 ... 520 { objects.append([0xA1] + reference(level - 1)) }
		#expect(try open(binaryPlist(objects)).error?.number != nil)
		// A file Foundation writes, which stores equal text once, is fine however often it's used.
		let records = (0 ..< 20000).map { _ in ["name": "same", "kind": "same"] } as NSArray
		#expect(try open(try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)).error == nil)
	}

	@Test func tooDeepIsAnError() throws {
		#expect(Thread.isMainThread)
		let plists = Plists()
		func nested(_ depth: Int) -> String { String(repeating: "[", count: depth) + String(repeating: "]", count: depth) }
		#expect(plists.send("PLSTNOSJ", ["----": nested(100)]).error == nil)
		#expect(plists.send("PLSTNOSJ", ["----": nested(1000)]).error?.number == -50)
		#expect(plists.send("PLSTNOSJ", ["----": nested(1_000_000)]).error?.number == -50)
		// The innermost (empty) array is at depth 512 here, and 513 in the next.
		#expect(plists.send("PLSTNOSJ", ["----": nested(513)]).error == nil)
		#expect(plists.send("PLSTNOSJ", ["----": nested(514)]).error?.number == -50)
		// Brackets in text don't count; text that isn't JSON is -1 however deep.
		#expect(plists.send("PLSTNOSJ", ["----": #"["\#(String(repeating: "[{\\\"", count: 1000))"]"#]).error == nil)
		#expect(plists.send("PLSTNOSJ", ["----": String(repeating: "[", count: 1000)]).error?.number == -1)
		#expect(plists.send("MTCpFYML", ["----": "a: " + nested(1000)]).error?.number == -50)
		#expect(plists.send("MTCpFYML", ["----": "a: " + nested(100)]).error == nil)
		// Nothing is left open after the error.
		let before = plists.store.allDocuments.count
		#expect(plists.send("PLSTNOSJ", ["----": nested(1000)]).error?.number == -50)
		#expect(plists.store.allDocuments.count == before)
		// Property list files: Apple's reader stops at about 512 levels itself (-1).
		func open(_ depth: Int) throws -> AppleEventReply {
			let text = "<plist version=\"1.0\">" + String(repeating: "<array>", count: depth) + String(repeating: "</array>", count: depth) + "</plist>"
			let file = FileManager.default.temporaryDirectory.appendingPathComponent("deep-\(UUID().uuidString).plist")
			try Data(text.utf8).write(to: file)
			defer { try? FileManager.default.removeItem(at: file) }
			return plists.send("PLSTopen", ["----": file])
		}
		#expect(try open(500).error == nil)
		#expect(try open(600).error?.number == -1)
		// AppleScript values too.
		var list = NSAppleEventDescriptor.list()
		for _ in 0 ..< 600 {
			let outer = NSAppleEventDescriptor.list()
			outer.insert(list, at: 1)
			list = outer
		}
		#expect(plists.send("PLSTmake", ["----": list]).error?.number == -50)
	}
}
