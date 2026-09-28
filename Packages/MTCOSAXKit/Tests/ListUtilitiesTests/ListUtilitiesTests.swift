import AppleEventCore
import Foundation
import Testing
@testable import ListUtilities

func send(_ code: String, _ parameters: [String: any AppleEventEncodable]) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(ListUtilities.commands())
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

/// A reply's list as Swift values: strings, integers, reals, "missing" for missing value, or nested arrays.
func values(_ descriptor: NSAppleEventDescriptor?) -> [AnyHashable]? {
	guard let descriptor else { return nil }
	if let reals = ArrayOfReal.values(of: descriptor) {
		return reals
	}
	guard descriptor.descriptorType == typeAEList else { return nil }
	return (0 ..< descriptor.numberOfItems).map { index -> AnyHashable in
		let item = descriptor.atIndex(index + 1)!
		switch item.descriptorType {
		case typeSInt32: return Int(item.int32Value)
		case typeIEEE64BitFloatingPoint: return item.doubleValue
		case typeType: return "missing"
		case typeAEList, FourCharCode(fourCharString: "Lido"): return values(item)
		default: return item.stringValue ?? "?"
		}
	}
}

func record(_ reply: AppleEventReply) -> RecordFields? {
	reply.result.flatMap(RecordFields.init)
}

func user(_ fields: KeyValuePairs<String, any AppleEventEncodable>) -> NSAppleEventDescriptor {
	RecordFields(fields.map { (.user($0.key), $0.value.appleEventDescriptor) }).appleEventDescriptor
}

struct ListUtilitiesCommandTests {
	@Test func everyCommandIsRegistered() {
		#expect(ListUtilities.commands().count == 7)
	}
}

struct SortListTests {
	private func sort(_ list: any AppleEventEncodable, _ parameters: [String: any AppleEventEncodable] = [:]) -> [AnyHashable]? {
		values(send("SATISort", parameters.merging(["----": list]) { $1 }).result)
	}

	@Test func numbers() {
		#expect(sort([2, 5, 1, 3]) == [1, 2, 3, 5])
		#expect(sort([2, 5, 1, 3], ["Asce": false]) == [5, 3, 2, 1])
		#expect(sort(AppleEventList([3, 1.5, 2])) == [1.5, 2.0, 3.0])
		#expect(sort([3, 1, 3, 2, 1], ["Uniq": true]) == [1, 2, 3])
		#expect(sort(ArrayOfReal([3, 1, 2]), ["Asce": false]) == [3.0, 2.0, 1.0])
	}

	@Test func text() {
		#expect(sort(["abc", "ABC", "xyz", "123"]) == ["123", "ABC", "abc", "xyz"])
		#expect(sort(["é", "e", "f", "E"]) == ["E", "e", "f", "é"])
		#expect(sort(["b", "B", "a", "A", "c"], ["Cfla": 1]) == ["a", "A", "b", "B", "c"])
		#expect(sort(["a1", "a10", "a2", "1b", "10b", "2b"], ["Cfla": 2]) == ["1b", "2b", "10b", "a1", "a2", "a10"])
		#expect(sort(["b", "B", "a", "A", "ab", "Ab"], ["Cfla": 5]) == ["A", "a", "Ab", "ab", "B", "b"])
		#expect(sort(["a", "A", "b", "a"], ["Uniq": true, "Cfla": 1]) == ["a", "b"])
		#expect(sort(AppleEventList(["b", 2, "a", 1])) == ["1", "2", "a", "b"])
	}

	@Test func missingValuesComeLast() {
		let list = AppleEventList([3, NSAppleEventDescriptor.missingValue, 1, 2])
		#expect(sort(list) == [1, 2, 3, "missing"])
		#expect(sort(list, ["Asce": false]) == [3, 2, 1, "missing"])
	}

	@Test func singleValuesAndErrors() {
		#expect(sort(5) == [5])
		#expect(send("SATISort", [:]).error == .missingParameter)
		#expect(send("SATISort", ["----": AppleEventList([NSAppleEventDescriptor(date: Date()), 1])]).error == .coercionFailed)
	}

	@Test func listsOfLists() {
		let lists = AppleEventList([[2, 1, 2, 1], ["b", "d", "a", "c"], [1, 2, 3, 4]])
		#expect(sort(AppleEventList([[3, 1, 2], ["b", "a"]])) == [[1, 2, 3], ["a", "b"]])
		#expect(sort(lists, ["from": 1]) == [[1, 1, 2, 2], ["d", "c", "b", "a"], [2, 4, 1, 3]])
		#expect(sort(lists, ["from": [1, 2]]) == [[1, 1, 2, 2], ["c", "d", "a", "b"], [4, 2, 3, 1]])
		#expect(sort(lists, ["from": [1, 2], "Asce": [true, false]]) == [[1, 1, 2, 2], ["d", "c", "b", "a"], [2, 4, 1, 3]])
		#expect(send("SATISort", ["----": AppleEventList([[1, 2], [1]]), "from": 1]).error == OSAXError(-1))
		#expect(send("SATISort", ["----": lists, "from": 4]).error == OSAXError(-1))
	}
}

struct MaskListTests {
	@Test func masks() {
		#expect(values(send("SATIMASk", ["----": ["a", "b", "c"], "with": [1, 0, 1]]).result) == ["a", "c"])
		#expect(values(send("SATIMASk", ["----": [1, 2, 3, 4], "with": [1, 0]]).result) == [1, 3])
		#expect(values(send("SATIMASk", ["----": [1, 2, 3], "with": [0, 1, 0], "Subs": "x"]).result) == ["x", 2, "x"])
		#expect(values(send("SATIMASk", ["----": [1, 2, 3], "with": ArrayOfReal([1, 0.5, 0])]).result) == [1, 2])
		#expect(send("SATIMASk", ["----": [1, 2], "with": [1, 0, 1]]).error == .parameterError)
		#expect(send("SATIMASk", ["----": ArrayOfReal([1]), "with": [1]]).error == .parameterError)
		#expect(send("SATIMASk", ["----": [1]]).error == .missingParameter)
	}
}

struct TopologicalSortTests {
	private func order(_ parameters: [String: any AppleEventEncodable]) -> [AnyHashable]? {
		values(send("SATITSrt", parameters).result)
	}

	@Test func documentationExample() {
		#expect(order(["edge": [[13, 2], [1, 13], [24, 1]]]) == [24, 1, 13, 2])
		#expect(order(["edge": [13, 2, 1, 13, 24, 1]]) == [24, 1, 13, 2])
	}

	@Test func verticesAndDependencies() {
		#expect(order(["----": [1, 2, 3, 4], "edge": [[3, 1]]]) == [2, 3, 1, 4])
		#expect(order(["----": [3, 1, 2]]) == [3, 1, 2])
		#expect(order(["depe": AppleEventList([[2], [3], [Int]()])]) == [3, 2, 1])
		#expect(order(["----": [10, 20, 30], "depe": AppleEventList([[20], [30], [Int]()])]) == [30, 20, 10])
	}

	@Test func errors() {
		#expect(send("SATITSrt", ["edge": [[1, 2], [2, 1]]]).error?.number == -2700)
		#expect(send("SATITSrt", ["edge": [1, 2, 3]]).error == .parameterError)
		#expect(send("SATITSrt", ["edge": [["a", "b"]]]).error == .coercionFailed)
		#expect(send("SATITSrt", ["----": [1, 2], "depe": AppleEventList([[2]])]).error == .parameterError)
		#expect(send("SATITSrt", [:]).error == .missingParameter)
	}
}

struct SuppressItemTests {
	@Test func lists() {
		#expect(values(send("SATIDLKY", ["----": 2, "from": ["a", "b", "c"]]).result) == ["a", "c"])
		#expect(values(send("SATIDLKY", ["----": -1, "from": [1, 2, 3]]).result) == [1, 2])
		#expect(values(send("SATIDLKY", ["----": [3, 1, 3], "from": [1, 2, 3, 4]]).result) == [2, 4])
		#expect(send("SATIDLKY", ["----": 0, "from": [1]]).error == OSAXError(-1719))
		#expect(send("SATIDLKY", ["----": 5, "from": [1]]).error == OSAXError(-1719))
		#expect(send("SATIDLKY", ["----": 1.5, "from": [1, 2]]).error == .parameterError)
	}

	@Test func records() throws {
		let input = RecordFields([(.code("pnam"), NSAppleEventDescriptor(string: "x")), (.user("abc"), NSAppleEventDescriptor(int32: 1)), (.user("b"), NSAppleEventDescriptor(int32: 2))]).appleEventDescriptor
		let byUser = try #require(record(send("SATIDLKY", ["----": "abc", "from": input])))
		#expect(byUser.fields.map(\.key) == [.code("pnam"), .user("b")])
		let byCode = try #require(record(send("SATIDLKY", ["----": ["pnam", "b"], "from": input])))
		#expect(byCode.fields.map(\.key) == [.user("abc")])
		let keyword = NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "pnam"))
		let byKeyword = try #require(record(send("SATIDLKY", ["----": keyword, "from": input])))
		#expect(byKeyword.fields.count == 2)
		#expect(send("SATIDLKY", ["----": 1, "from": input]).error == OSAXError(-1719))
	}
}

struct FilterItemsTests {
	private let letters = ["a", "z", "e", "r", "t", "y"]

	@Test func documentationExamples() {
		#expect(values(send("SATIEIFL", ["----": ["r", "t", "z"], "from": letters]).result) == ["a", "e", "y"])
		#expect(values(send("SATIKIFL", ["----": ["r", "t", "z"], "from": letters]).result) == ["z", "r", "t"])
		let lists = AppleEventList([letters, [1, 2, 3, 4, 5, 6]])
		#expect(values(send("SATIEIFL", ["----": ["r", "t", "z"], "from": lists]).result) == [["a", "e", "y"], [1, 3, 6]])
		#expect(values(send("SATIKIFL", ["----": ["r", "t", "z"], "from": lists]).result) == [["z", "r", "t"], [2, 4, 5]])
	}

	@Test func options() {
		#expect(values(send("SATIEIFL", ["----": ["A", "b"], "from": ["a", "A", "b", "B"], "CaSe": false]).result) == [])
		#expect(values(send("SATIKIFL", ["----": ["É"], "from": ["é", "e", "É"], "CaSe": false]).result) == ["é", "É"])
		#expect(values(send("SATIEIFL", ["----": ["x"], "from": AppleEventList([[1, 2, 3], ["x", "y", "x"]]), "With": 2]).result) == [[2], ["y"]])
		#expect(values(send("SATIEIFL", ["----": ["1"], "from": AppleEventList([1, "1", 2])]).result) == [2])
		#expect(values(send("SATIKIFL", ["----": [String](), "from": ["a", "b"]]).result) == [])
		#expect(send("SATIKIFL", ["----": ["a"]]).error == .missingParameter)
	}
}

struct SpecialConcatTests {
	@Test func records() throws {
		let a = user(["a": 1, "b": [1], "c": "A", "d": 0])
		let b = user(["a": 2, "b": [2], "c": "B", "e": 5])
		let result = try #require(record(send("SATICONC", ["----": a, "with": b])))
		#expect(result.fields.map(\.key) == [.user("a"), .user("b"), .user("c"), .user("d"), .user("e")])
		#expect(result[.user("a")]?.descriptorType == typeIEEE64BitFloatingPoint)
		#expect(result[.user("a")]?.doubleValue == 3)
		#expect(values(result[.user("b")]) == [1, 2])
		#expect(result[.user("c")]?.stringValue == "A")
	}

	@Test func tables() {
		func concat(_ a: String, _ b: String) -> String? {
			send("SATICONC", ["----": a, "with": b]).result?.stringValue
		}
		#expect(concat("1\t2\rA\tB", "3\rC") == "1\t2\t3\rA\tB\tC")
		#expect(concat("1\nA", "3\nC") == "1\t3\nA\tC")
		#expect(concat("1\rA\rX", "3\rC") == "1\t3\rA\tC\rX\t")
		#expect(concat("1\rA\r", "3\rC\r") == "1\t3\rA\tC\r")
		#expect(concat("", "b") == "\tb")
	}

	@Test func errors() {
		#expect(send("SATICONC", ["----": "a", "with": user(["a": 1])]).error == .coercionFailed)
		#expect(send("SATICONC", ["----": [1], "with": [2]]).error == .coercionFailed)
		#expect(send("SATICONC", ["----": user(["a": 1])]).error == .missingParameter)
	}
}
