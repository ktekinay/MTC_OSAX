import AppleEventCore
import Foundation
import Testing
@testable import ListUtilities

/// Sorting lists together by many criteria, and parameters far longer than they need be.
@MainActor
struct SortTogetherTests {
	private func sort(_ lists: any AppleEventEncodable, _ parameters: [String: any AppleEventEncodable]) -> [AnyHashable]? {
		values(send("SATISort", parameters.merging(["----": lists]) { $1 }).result)
	}

	private let lists = AppleEventList([[2, 1, 2, 1, 2], ["b", "c", "a", "c", "a"], [1, 2, 3, 4, 5]])

	/// A criterion that repeats an earlier one is left out, whatever its direction: rows equal by every criterion
	/// before it are equal by it too. (100,000 of them ran out of stack; 1,000 on 100,000 rows took 10 s.)
	@Test func repeatedCriteria() {
		let expected = sort(lists, ["from": [1, 2], "Asce": [false, true]])
		#expect(expected == [[2, 2, 2, 1, 1], ["a", "a", "b", "c", "c"], [3, 5, 1, 2, 4]])
		#expect(sort(lists, ["from": [1, 2, 1], "Asce": [false, true, true]]) == expected)
		#expect(sort(lists, ["from": [1, 1, 2, 1, 2], "Asce": [false, true, true, true, false]]) == expected)
		#expect(sort(lists, ["from": [1, 2, 1], "Asce": [false, true, true], "Uniq": true]) == sort(lists, ["from": [1, 2], "Asce": [false, true], "Uniq": true]))
		let start = Date()
		#expect(sort(lists, ["from": ArrayOfReal(Array(repeating: 1, count: 100_000))]) == sort(lists, ["from": 1]))
		#expect(sort(lists, ["from": AppleEventList(Array(repeating: 2, count: 100_000))]) == sort(lists, ["from": 2]))
		#expect(Date().timeIntervalSince(start) < 2)
		// Each criterion must still name a list.
		#expect(send("SATISort", ["----": lists, "from": [1, 1, 4]]).error == OSAXError(-1))
	}

	/// 20,000 lists sorted together, each by itself, ran out of stack (an order for each, made by recursing).
	@Test func manyLists() throws {
		let count = 20_000
		let numbers = AppleEventList((0 ..< count).map { AppleEventList([$0 % 7]) })
		let reply = try #require(send("SATISort", ["----": numbers, "from": Array(1 ... count)]).result)
		#expect(reply.numberOfItems == count)
		let texts = AppleEventList((0 ..< count).map { AppleEventList(["t\($0 % 7)"]) })
		#expect(send("SATISort", ["----": texts, "from": Array(1 ... count), "Uniq": true]).result?.numberOfItems == count)
	}

	/// Only as much of `ascending` is read as there are criteria (an array of 10,000,000 took 12 s and 1.6 GB).
	@Test func longDirections() {
		let start = Date()
		let falses = ArrayOfReal(Array(repeating: 0, count: 10_000_000))
		#expect(values(send("SATISort", ["----": [3, 1, 2], "Asce": falses]).result) == values(send("SATISort", ["----": [3, 1, 2], "Asce": false]).result))
		#expect(sort(lists, ["from": [1, 2], "Asce": falses]) == sort(lists, ["from": [1, 2], "Asce": [false, false]]))
		let list = AppleEventList(Array(repeating: false, count: 1_000_000))
		#expect(sort(lists, ["from": [1, 2], "Asce": list]) == sort(lists, ["from": [1, 2], "Asce": [false, false]]))
		#expect(Date().timeIntervalSince(start) < 5)
	}

	/// Repeated criteria with an `ascending` as long: only the criteria left are read (a descriptor was made for each
	/// of `ascending`'s numbers as far as the criteria went). Audit P1.
	@Test func longDirectionsWithRepeatedCriteria() {
		let start = Date()
		let ones = ArrayOfReal(Array(repeating: 1, count: 2_000_000))
		let falses = ArrayOfReal(Array(repeating: 0, count: 2_000_000))
		#expect(sort(lists, ["from": ones, "Asce": falses]) == sort(lists, ["from": 1, "Asce": false]))
		let list = AppleEventList(Array(repeating: false, count: 1_000_000))
		#expect(sort(lists, ["from": AppleEventList(Array(repeating: 1, count: 1_000_000)), "Asce": list]) == sort(lists, ["from": 1, "Asce": false]))
		// A criterion's direction is its own, or ascending's first past its end.
		#expect(sort(lists, ["from": [1, 1, 2], "Asce": [false, true, false]]) == sort(lists, ["from": [1, 2], "Asce": [false, false]]))
		#expect(sort(lists, ["from": [1, 2], "Asce": [false]]) == sort(lists, ["from": [1, 2], "Asce": [false, false]]))
		#expect(Date().timeIntervalSince(start) < 5)
	}

	/// The lists sorted by come back as they would sorted alone (recorded: numbers in a list with text as text,
	/// integers in a list with reals as reals); the other lists as they were. Audit R5.
	@Test func keyListsAreReplacedAsAlone() {
		let mixed = AppleEventList(["b", 10, "a", 9] as [any AppleEventEncodable])
		let reals = AppleEventList([3, 1.5, 2] as [any AppleEventEncodable])
		#expect(sort(AppleEventList([mixed, [1, 2, 3, 4]]), ["from": 1]) == [["10", "9", "a", "b"], [2, 4, 3, 1]])
		#expect(sort(AppleEventList([[1, 2, 3, 4], mixed]), ["from": 2]) == [[2, 4, 3, 1], ["10", "9", "a", "b"]])
		#expect(sort(AppleEventList([reals, [1, 2, 3]]), ["from": 1]) == [[1.5, 2.0, 3.0], [2, 3, 1]])
		#expect(sort(AppleEventList([mixed]), ["from": 1]) == sort(AppleEventList([mixed]), [:]))
	}

	/// Criteria of every kind of number, and as text.
	@Test func criteriaOfEveryKind() {
		let expected = sort(lists, ["from": [2, 3]])
		#expect(sort(lists, ["from": ArrayOfReal([2, 3])]) == expected)
		#expect(sort(lists, ["from": AppleEventList([2.0, "3"])]) == expected)
		#expect(send("SATISort", ["----": lists, "from": AppleEventList([2, 1.5])]).error == .coercionFailed)
		#expect(send("SATISort", ["----": lists, "from": AppleEventList([2, NSAppleEventDescriptor.missingValue])]).error == .coercionFailed)
	}
}
