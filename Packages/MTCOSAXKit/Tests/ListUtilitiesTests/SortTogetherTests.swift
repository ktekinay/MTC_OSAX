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

	/// Criteria of every kind of number, and as text.
	@Test func criteriaOfEveryKind() {
		let expected = sort(lists, ["from": [2, 3]])
		#expect(sort(lists, ["from": ArrayOfReal([2, 3])]) == expected)
		#expect(sort(lists, ["from": AppleEventList([2.0, "3"])]) == expected)
		#expect(send("SATISort", ["----": lists, "from": AppleEventList([2, 1.5])]).error == .coercionFailed)
		#expect(send("SATISort", ["----": lists, "from": AppleEventList([2, NSAppleEventDescriptor.missingValue])]).error == .coercionFailed)
	}
}
