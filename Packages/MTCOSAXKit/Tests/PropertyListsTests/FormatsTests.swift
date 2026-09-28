import AppleEventCore
import Foundation
import Testing
@testable import PropertyLists

private let newYork = TimeZone(identifier: "America/New_York")!
/// 2026-09-28T14:30:00Z.
private let moment = Date(timeIntervalSince1970: 1_790_605_800)

private func lines(_ text: String) -> Set<String> {
	Set(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
}

private func dictionary(_ pairs: [String: Any]) -> NSMutableDictionary {
	NSMutableDictionary(dictionary: pairs)
}

private var missing: Data { PropertyLists.missingValueData }

struct TOMLTests {
	@Test func scalars() throws {
		let text = try TOML.write(dictionary([
			"s": "a\"b\n\u{1}", "i": NSNumber(value: Int64(1) << 40), "r": 2.5, "t": true, "d": moment, "data": Data([1, 2, 3]),
			"inf": Double.infinity, "a b": "k",
		]))
		#expect(lines(text) == [
			#"s = "a\"b\n\u0001""#, "i = 1099511627776", "r = 2.5", "t = true", "d = 2026-09-28T14:30:00Z", #"data = "AQID""#,
			"inf = inf", #""a b" = "k""#, "",
		])
	}

	@Test func tables() throws {
		let text = try TOML.write(dictionary(["address": dictionary(["city": "Paris"])]))
		#expect(text == "[address]\ncity = \"Paris\"\n")
		let nested = try TOML.write(dictionary(["a": dictionary(["b": dictionary(["c": 1])])]))
		#expect(nested == "[a.b]\nc = 1\n")
		#expect(try TOML.write(dictionary(["e": NSDictionary()])) == "[e]\n")
		let arrayOfTables = try TOML.write(dictionary(["p": [dictionary(["n": 1]), dictionary(["n": 2])] as NSArray]))
		#expect(arrayOfTables == "[[p]]\nn = 1\n\n[[p]]\nn = 2\n")
		// Dictionaries in a mixed array are inline tables.
		#expect(try TOML.write(dictionary(["m": [1, dictionary(["x": 1])] as NSArray])) == "m = [1, { x = 1 }]\n")
		// Simple keys come before sub-tables.
		let mixed = try TOML.write(dictionary(["z": dictionary(["y": 1]), "a": 2]))
		#expect(mixed == "a = 2\n\n[z]\ny = 1\n" || mixed == "a = 2\n[z]\ny = 1\n")
	}

	@Test func missingValue() throws {
		#expect(try TOML.write(dictionary(["phone": missing])) == "# phone = NULL\n")
		#expect(throws: OSAXError.self) { try TOML.write(dictionary(["list": [1, missing] as NSArray])) }
		#expect((try? TOML.write([1, 2] as NSArray)) == nil)
		do {
			_ = try TOML.write("text")
		} catch let error as OSAXError {
			#expect(error.number == -50)
		}
	}

	@Test func reading() throws {
		let text = """
		# a comment
		s = "a\\tb"
		i = 0x10
		r = 1.5e3
		b = false
		offset = 2026-09-28T10:30:00-04:00
		local = 2026-09-28T10:30:00
		day = 2026-09-28
		time = 14:30:00
		fraction = 14:30:00.5
		list = [1, "two", [3]]
		[t]
		x = 1
		[[aot]]
		n = 1
		"""
		let object = try #require(try TOML.read(text, timeZone: newYork) as? NSDictionary)
		#expect(object["s"] as? String == "a\tb")
		#expect((object["i"] as? NSNumber)?.int64Value == 16)
		#expect((object["r"] as? NSNumber)?.doubleValue == 1500)
		#expect((object["b"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && !$0.boolValue } == true)
		#expect(object["offset"] as? Date == moment)
		#expect(object["local"] as? Date == moment)
		#expect(object["day"] as? Date == moment.addingTimeInterval(-(14 * 3600 + 30 * 60) + 4 * 3600))
		#expect(object["time"] as? String == "14:30:00")
		#expect(object["fraction"] as? String == "14:30:00.5")
		#expect((object["list"] as? NSArray)?.count == 3)
		#expect((object["t"] as? NSDictionary)?["x"] as? NSNumber == 1)
		#expect(((object["aot"] as? NSArray)?.firstObject as? NSDictionary)?["n"] as? NSNumber == 1)
	}

	/// TOML allows offsets beyond TimeZone's 18 hours; they used to trap.
	@Test func largeOffsets() throws {
		let object = try #require(try TOML.read("""
		d = 2026-09-28T10:30:00+19:00
		e = 2026-09-28T10:30:00-23:59
		f = 2026-09-28T10:30:00.5+05:30
		""") as? NSDictionary)
		let utc = try #require(ISO8601DateFormatter().date(from: "2026-09-28T10:30:00Z"))
		#expect(object["d"] as? Date == utc.addingTimeInterval(-19 * 3600))
		#expect(object["e"] as? Date == utc.addingTimeInterval(23 * 3600 + 59 * 60))
		#expect(object["f"] as? Date == utc.addingTimeInterval(0.5 - 5.5 * 3600))
	}

	@Test func errors() {
		do {
			_ = try TOML.read("a = ")
			Issue.record("no error")
		} catch let error as OSAXError {
			#expect(error.number == -1)
			#expect(error.message?.hasPrefix("Not TOML:") == true)
		} catch {
			Issue.record("\(error)")
		}
		#expect((try? TOML.read("")) as? NSDictionary == NSDictionary())
	}

	@Test func roundTrip() throws {
		let original = dictionary([
			"s": "x", "i": 42, "r": 0.25, "t": false, "d": moment,
			"sub": dictionary(["list": [1, 2] as NSArray, "deeper": dictionary(["k": "v"])]),
			"aot": [dictionary(["n": 1]), dictionary(["n": 2])] as NSArray,
		])
		let back = try #require(try TOML.read(TOML.write(original)) as? NSDictionary)
		#expect(back == original)
		// A missing value is dropped (TOML readers ignore comments).
		#expect(try TOML.read(TOML.write(dictionary(["a": 1, "gone": missing]))) as? NSDictionary == dictionary(["a": 1]))
	}
}

struct YAMLTests {
	/// Aliases used to be expanded again at every use, so a few lines could make hundreds of millions of values.
	@Test func aliasExpansion() throws {
		var lines = ["a0: &a0 [x, x, x, x, x, x, x, x, x]"]
		for level in 1 ... 9 {
			lines.append("a\(level): &a\(level) [" + Array(repeating: "*a\(level - 1)", count: 9).joined(separator: ", ") + "]")
		}
		let start = Date()
		let error = #expect(throws: OSAXError.self) { try YAML.read(lines.joined(separator: "\n")) }
		#expect(error?.number == -50)
		#expect(Date().timeIntervalSince(start) < 5)
		// A few levels are fine, and each use is the whole value.
		let small = try #require(try YAML.read(lines.prefix(3).joined(separator: "\n")) as? NSDictionary)
		#expect((small["a2"] as? NSArray)?.count == 9)
		#expect(((small["a2"] as? NSArray)?[8] as? NSArray)?.count == 9)
		#expect(small["a1"] as? NSArray == (small["a2"] as? NSArray)?[0] as? NSArray)
	}

	/// Empty text used to hand libyaml a pointer to a temporary array.
	@Test func emptyTextHasNoDocument() {
		for text in ["", "# only a comment\n"] {
			let error = #expect(throws: OSAXError.self) { try YAML.read(text) }
			#expect(error?.number == -1)
			#expect(error?.message == "Not YAML: there's no document.")
		}
	}

	@Test func writing() {
		#expect(YAML.write(dictionary(["name": "Ann"])) == "name: Ann\n")
		#expect(YAML.write(dictionary(["tags": ["a", "b"] as NSArray])) == "tags:\n- a\n- b\n")
		#expect(YAML.write(dictionary(["address": dictionary(["city": "Paris"])])) == "address:\n  city: Paris\n")
		#expect(YAML.write([dictionary(["k": 1]), ["x", "z"] as NSArray] as NSArray) == "- k: 1\n- - x\n  - z\n")
		#expect(YAML.write(dictionary(["e": NSDictionary(), "l": NSArray()])).contains("e: {}"))
		#expect(YAML.write("plain") == "plain\n")
		#expect(YAML.write(dictionary(["d": moment])) == "d: 2026-09-28T14:30:00Z\n")
		#expect(YAML.write(dictionary(["b": Data([1, 2, 3])])) == "b: !!binary AQID\n")
		#expect(YAML.write(dictionary(["m": missing])) == "m: null\n")
		#expect(YAML.write(dictionary(["r": Double.nan])) == "r: .nan\n")
		#expect(YAML.write(dictionary(["t": true])) == "t: true\n")
	}

	@Test func quoting() {
		for text in ["yes", "No", "true", "null", "~", "123", "1.5", "2026-09-28", "", " x", "a: b", "- x", "#c", "a #b", "x\ny", "tab\there", ".inf"] {
			#expect(YAML.scalarText(text).hasPrefix("\""), "\(text)")
		}
		for text in ["Ann", "Paris, France", "a-b", "hello world", "é"] {
			#expect(YAML.scalarText(text) == text, "\(text)")
		}
		#expect(YAML.scalarText("x\ny") == #""x\ny""#)
	}

	@Test func reading() throws {
		let text = """
		yes: yes
		no: no
		t: true
		f: False
		n: null
		tilde: ~
		empty:
		hex: 0x1F
		oct: 0o17
		real: 1.5e3
		inf: -.inf
		day: 2026-09-28
		utc: 2026-09-28T14:30:00Z
		spaced: 2026-09-28 10:30:00
		offset: 2026-09-28T10:30:00-04:00
		quoted: "2026-09-28"
		single: '123'
		bin: !!binary AQID
		str: !!str text
		list: [1, two]
		"""
		let object = try #require(try YAML.read(text, timeZone: newYork) as? NSDictionary)
		#expect(object["yes"] as? String == "yes")
		#expect(object["no"] as? String == "no")
		#expect((object["t"] as? NSNumber)?.boolValue == true)
		#expect((object["f"] as? NSNumber)?.boolValue == false)
		#expect(object["n"] as? Data == missing)
		#expect(object["tilde"] as? Data == missing)
		#expect(object["empty"] as? Data == missing)
		#expect((object["hex"] as? NSNumber)?.int64Value == 31)
		#expect((object["oct"] as? NSNumber)?.int64Value == 15)
		#expect((object["real"] as? NSNumber)?.doubleValue == 1500)
		#expect((object["inf"] as? NSNumber)?.doubleValue == -.infinity)
		#expect(object["day"] as? Date == moment.addingTimeInterval(-(14 * 3600 + 30 * 60) + 4 * 3600))
		#expect(object["utc"] as? Date == moment)
		#expect(object["spaced"] as? Date == moment)
		#expect(object["offset"] as? Date == moment)
		#expect(object["quoted"] as? String == "2026-09-28")
		#expect(object["single"] as? String == "123")
		#expect(object["bin"] as? Data == Data([1, 2, 3]))
		#expect(object["str"] as? String == "text")
		#expect((object["list"] as? NSArray) == [1, "two"] as NSArray)
	}

	@Test func anchorsAliasesAndMerges() throws {
		let text = """
		base: &base
		  a: 1
		  b: 2
		copy: *base
		derived:
		  <<: *base
		  b: 3
		"""
		let object = try #require(try YAML.read(text) as? NSDictionary)
		#expect(object["copy"] as? NSDictionary == dictionary(["a": 1, "b": 2]))
		#expect(object["derived"] as? NSDictionary == dictionary(["a": 1, "b": 3]))
	}

	@Test func errors() {
		func number(_ text: String) -> Int? {
			do {
				_ = try YAML.read(text)
				return nil
			} catch let error as OSAXError {
				return error.number
			} catch {
				return 0
			}
		}
		#expect(number("a: [1, 2") == -1)
		#expect(number("") == -1)
		#expect(number("a: 1\n---\nb: 2\n") == -50)
		#expect(number("? [a, b]\n: c\n") == -50)
		#expect(number("a: !!binary not base64 !!!") == -50)
		#expect(number("a: &x [*x]") != nil)
		do {
			_ = try YAML.read("a: [1, 2")
		} catch let error as OSAXError {
			#expect(error.message?.contains("line") == true)
		} catch {}
	}

	@Test func roundTrip() throws {
		let original = dictionary([
			"s": "x", "yes": "no", "number text": "12", "i": 42, "r": 0.25, "t": false, "d": moment, "data": Data([0, 255]),
			"nothing": missing, "sub": dictionary(["list": [1, dictionary(["k": "v"]), ["deep"] as NSArray] as NSArray]),
			"multi": "line one\nline two", "e": NSDictionary(), "l": NSArray(),
		])
		let back = try #require(try YAML.read(YAML.write(original)) as? NSDictionary)
		#expect(back == original)
	}
}

struct FormatCommandTests {
	@Test func commands() throws {
		let plists = Plists()
		let p = try plists.new(record(["name": "Ann", "tags": ["a", "b"]]))
		let yaml = try #require(plists.send("MTCpTYML", ["----": p]).result?.stringValue)
		#expect(lines(yaml) == ["name: Ann", "tags:", "- a", "- b", ""])
		let toml = try #require(plists.send("MTCpTTML", ["----": p]).result?.stringValue)
		#expect(lines(toml) == [#"name = "Ann""#, #"tags = ["a", "b"]"#, ""])

		let fromYAML = try #require(plists.send("MTCpFYML", ["----": yaml, "pool": "mtc-y"]).result)
		#expect(plists.xml(fromYAML) == plists.xml(p))
		#expect(plists.send("POOLgpoo", ["----": fromYAML]).result?.stringValue == "mtc-y")
		let fromTOML = try #require(plists.send("MTCpFTML", ["----": toml]).result)
		#expect(plists.xml(fromTOML) == plists.xml(p))

		// An element of a document; TOML needs a dictionary.
		let tags = try #require(plists.send("PLSTchld", ["----": p, "key ": "tags"]).result)
		#expect(plists.send("MTCpTYML", ["----": tags]).result?.stringValue == "- a\n- b\n")
		#expect(plists.send("MTCpTTML", ["----": tags]).error?.number == -50)
		#expect(plists.send("MTCpFTML", ["----": "x ="]).error?.number == -1)
		#expect(plists.send("MTCpFYML", ["----": "a: [1"]).error?.number == -1)
	}
}

/// Cases from the TOML 1.1 and YAML 1.2 specifications that the converters must get right.
struct FormatConformanceTests {
	@Test(arguments: [
		("dotted = 1\na.b.c = 2", "a", "{b = {c = 2;};}"),
		("t = { x = 1, y = [2, 3] }", "t", "{x = 1; y = (2, 3);}"),
		("s = '''\nraw \\n text'''", "s", "raw \\n text"),
		("s = \"\"\"\nline one\\\n   continued\"\"\"", "s", "line one continued"),
		("big = 9_223_372_036_854_775_807", "big", "9223372036854775807"),
		("f = 6.626e-34", "f", "6.626e-34"),
		("\"quoted key\" = 1", "quoted key", "1"),
	])
	/// `expected` is how Foundation describes the value, without spaces.
	func tomlValid(text: String, key: String, expected: String) throws {
		let object = try #require(try TOML.read(text) as? NSDictionary)
		let value = try #require(object[key])
		#expect("\(value)".replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "    ", with: "").replacingOccurrences(of: " ", with: "")
			== expected.replacingOccurrences(of: " ", with: ""))
	}

	@Test(arguments: [
		"a = 1\na = 2",                 // duplicate key
		"[t]\n[t]",                     // table defined twice
		"a = 1979-05-27 07:32:00Z x",   // trailing garbage
		"a = \"unterminated",
		"a = [1, 2",
		"a.b = 1\na = 2",               // key redefined as a value
	])
	func tomlInvalid(text: String) {
		#expect(throws: OSAXError.self) { try TOML.read(text) }
	}

	@Test func yamlValid() throws {
		let text = """
		%YAML 1.2
		---
		literal: |
		  one
		  two
		folded: >
		  one
		  two
		flow: {a: 1, b: [x, y]}
		# a comment
		"key with spaces": value
		multi word key: value # trailing comment
		"""
		let object = try #require(try YAML.read(text) as? NSDictionary)
		#expect(object["literal"] as? String == "one\ntwo\n")
		#expect(object["folded"] as? String == "one two\n")
		#expect(object["flow"] as? NSDictionary == dictionary(["a": 1, "b": ["x", "y"] as NSArray]))
		#expect(object["key with spaces"] as? String == "value")
		#expect(object["multi word key"] as? String == "value")
	}

	@Test(arguments: [
		"a:\n\t- tab indentation",
		"a: 'unterminated",
		"[1, 2",
		"a: b: c",
		"- a\nb: c",
	])
	func yamlInvalid(text: String) {
		#expect(throws: OSAXError.self) { try YAML.read(text) }
	}
}

/// Reading and writing files (decision 12), for JSON, YAML and TOML alike.
struct FormatFileTests {
	private let formats = [("JSON", "PLSTJSON", "PLSTNOSJ"), ("YAML", "MTCpTYML", "MTCpFYML"), ("TOML", "MTCpTTML", "MTCpFTML")]

	private func withFolder(_ body: (URL) throws -> Void) throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-formats-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		try body(folder)
	}

	@Test func writeAndReadBack() throws {
		try withFolder { folder in
			let plists = Plists()
			let p = try plists.new(record(["person": "Ann", "tags": ["a", "b"]]))
			for (name, to, from) in formats {
				let file = folder.appendingPathComponent("data.\(name.lowercased())")
				let written = plists.send(to, ["----": p, "kfil": file])
				#expect(written.error == nil, "\(name)")
				#expect(written.result == nil, "\(name): returns nothing")
				let text = try String(contentsOf: file, encoding: .utf8)
				#expect(text == plists.send(to, ["----": p]).result?.stringValue, "\(name)")
				let read = try #require(plists.send(from, ["----": file]).result, "\(name)")
				#expect(plists.send("PLSTequa", ["----": p, "to  ": read]).result?.booleanValue == true, "\(name)")
				// A POSIX path works for in.
				let path = folder.appendingPathComponent("path.\(name.lowercased())").path
				#expect(plists.send(to, ["----": p, "kfil": path]).error == nil, "\(name)")
				#expect(FileManager.default.fileExists(atPath: path), "\(name)")
			}
		}
	}

	@Test func textIsNeverAPath() throws {
		try withFolder { folder in
			let plists = Plists()
			let file = folder.appendingPathComponent("data.json")
			try "{\"a\":1}".write(to: file, atomically: true, encoding: .utf8)
			// The path as text is read as JSON (and isn't JSON), as in Satimage.
			#expect(plists.send("PLSTNOSJ", ["----": file.path]).error?.number == -1)
			#expect(plists.send("PLSTNOSJ", ["----": file]).error == nil)
		}
	}

	@Test func errors() throws {
		try withFolder { folder in
			let plists = Plists()
			let p = try plists.new(record(["a": 1]))
			for (name, to, from) in formats {
				#expect(plists.send(from, ["----": folder.appendingPathComponent("missing")]).error?.number == -43, "\(name)")
				let noFolder = folder.appendingPathComponent("nope/data")
				#expect(plists.send(to, ["----": p, "kfil": noFolder]).error?.number == -1, "\(name)")
			}
			let latin1 = folder.appendingPathComponent("latin1.toml")
			try Data("a = \"caf\u{E9}\"".data(using: .isoLatin1)!).write(to: latin1)
			#expect(plists.send("MTCpFTML", ["----": latin1]).error?.number == -1)
			let bom = folder.appendingPathComponent("bom.json")
			try (Data([0xEF, 0xBB, 0xBF]) + Data("{\"a\":1}".utf8)).write(to: bom)
			#expect(plists.send("PLSTNOSJ", ["----": bom]).error == nil)
		}
	}
}
