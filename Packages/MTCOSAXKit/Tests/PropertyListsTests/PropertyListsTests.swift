import AppleEventCore
import Foundation
import Testing
@testable import PropertyLists

/// Sends commands to one set of PropertyList and Pool commands, sharing their documents.
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

struct PropertyListsCommandTests {
	@Test func everyCommandIsRegistered() {
		// Satimage's 29 PropertyList and 3 Pool commands, and MTC_OSAX's 4 for YAML and TOML.
		#expect(PropertyLists.commands().count == 36)
	}
}

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
}

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

struct SelectorTests {
	@Test func paths() throws {
		#expect(try Selector.steps("a/b[2][3]/c") == [.key("a"), .key("b"), .index(2), .index(3), .key("c")])
		#expect(try Selector.steps("/a/") == [.key("a")])
		#expect(throws: OSAXError(-1)) { try Selector.steps("[1]") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("a[x") }
		#expect(throws: OSAXError(-1)) { try Selector.steps("") }
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

struct JSONTests {
	@Test func toJSON() throws {
		let plists = Plists()
		let p = try plists.new(record(["a": 1, "l": ["x", "y"], "d": record(["e": 1])]))
		#expect(plists.send("PLSTJSON", ["----": p]).result?.stringValue == #"{"a":1,"l":["x","y"],"d":{"e":1}}"#)
		#expect(plists.send("PLSTJSON", ["----": p, "smar": true]).result?.stringValue == "{\n\t\"a\": 1,\n\t\"l\": [\n\t\t\"x\",\n\t\t\"y\"\n\t],\n\t\"d\": {\n\t\t\"e\": 1\n\t}\n}")
		#expect(plists.send("PLSTJSON", ["----": p, "rplc": "function(k, v) { return typeof v === 'number' ? v * 10 : v; }"]).result?.stringValue == #"{"a":10,"l":["x","y"],"d":{"e":10}}"#)
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
}

struct FilterIntoTests {
	@Test func addsEntries() throws {
		let plists = Plists()
		let p = try plists.new(record(["z": 0]))
		try PropertyLists.add([("a", "1"), ("b", ["2", "3"])], to: p, store: plists.store)
		#expect(plists.xml(p).contains("<key>b</key><array><string>2</string><string>3</string></array>"))
		#expect(throws: OSAXError(-1)) { try PropertyLists.add([("a", "1")], to: try plists.new(["x"]), store: plists.store) }
	}
}

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

/// Runs `body` on a thread with the main thread's 8 MB stack, where the app runs commands (tests run on threads
/// with much smaller stacks).
func onMainSizedStack(_ body: @escaping @Sendable () -> Void) {
	let done = DispatchSemaphore(value: 0)
	let thread = Thread {
		body()
		done.signal()
	}
	thread.stackSize = 8 << 20
	thread.start()
	done.wait()
}

/// Deep nesting used to recurse until the stack ran out (a JSON file of a million `[`s crashed the app).
struct NestingTests {
	@Test func tooDeepIsAnError() {
		onMainSizedStack {
			do {
				try checkNesting()
			} catch {
				Issue.record(error)
			}
		}
	}

	private func checkNesting() throws {
		let plists = Plists()
		func nested(_ depth: Int) -> String { String(repeating: "[", count: depth) + String(repeating: "]", count: depth) }
		#expect(plists.send("PLSTNOSJ", ["----": nested(100)]).error == nil)
		#expect(plists.send("PLSTNOSJ", ["----": nested(1000)]).error?.number == -50)
		#expect(plists.send("PLSTNOSJ", ["----": nested(1_000_000)]).error?.number == -50)
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
