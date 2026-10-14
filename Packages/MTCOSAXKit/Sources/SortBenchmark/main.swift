// Times `sortlist` on lists of each kind and size: the whole command in process (descriptors in and out, through
// the dispatcher), the sort alone (making the sort keys and ordering the rows), and the ordering alone. Build in
// release:
//
//   Scripts/sort-benchmark.sh [--sizes 1000,100000] [--only text]
//
// Each time is the median of several runs. Lists are random but the same every time (a fixed seed).

import AppleEventCore
import Foundation
import ListUtilities

/// Repeatable random numbers (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
	var state: UInt64
	init(seed: UInt64) { state = seed }
	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		return z ^ (z >> 31)
	}
}

/// A list to sort: its parameters for the command, and how to make its sort keys as the command does once it has
/// the items.
struct Case {
	var name: String
	var parameters: [String: NSAppleEventDescriptor]
	var flags = 0
	var unique = false
	var keys: () throws -> [Sorting.Column]

	func order(_ keys: [Sorting.Column]) -> Int {
		Sorting.order(rows: 0 ..< count(keys[0]), keys: keys, ascending: keys.map { _ in true }, options: Sorting.Options(flags: flags, removeDuplicates: unique)).count
	}

	private func count(_ column: Sorting.Column) -> Int {
		switch column {
		case let .numbers(values): values.count
		case let .texts(keys): keys.count
		}
	}
}

func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
	let list = NSAppleEventDescriptor.list()
	for (index, item) in items.enumerated() {
		list.insert(item, at: index + 1)
	}
	return list
}

private let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789éÉøß -")

func randomWord(_ generator: inout SeededGenerator) -> String {
	String((0 ..< Int.random(in: 3 ... 12, using: &generator)).map { _ in letters.randomElement(using: &generator)! })
}

/// In order but for 5% of them (2.5% of places swapped in pairs), as `SortedResultTests` arranges them.
func mostlySorted<Value>(_ values: [Value], by areInIncreasingOrder: (Value, Value) -> Bool, _ generator: inout SeededGenerator) -> [Value] {
	var values = values.sorted(by: areInIncreasingOrder)
	for _ in 0 ..< values.count / 80 {
		values.swapAt(Int.random(in: values.indices, using: &generator), Int.random(in: values.indices, using: &generator))
	}
	return values
}

/// 95% duplicates: drawn from the first twentieth.
func mostlyDuplicates<Value>(_ values: [Value], _ generator: inout SeededGenerator) -> [Value] {
	let distinct = values.prefix(max(1, values.count / 20))
	return values.indices.map { _ in distinct.randomElement(using: &generator)! }
}

func cases(size: Int) -> [Case] {
	var generator = SeededGenerator(seed: UInt64(size))
	let reals = (0 ..< size).map { _ in Double.random(in: -1e6 ... 1e6, using: &generator) }
	let integers = (0 ..< size).map { _ in Int32.random(in: -1_000_000 ... 1_000_000, using: &generator) }
	let dates = (0 ..< size).map { _ in Date(timeIntervalSinceReferenceDate: .random(in: -1e9 ... 1e9, using: &generator)) }
	let words = (0 ..< size).map { _ in randomWord(&generator) }
	let mixed: [NSAppleEventDescriptor] = (0 ..< size).map { index in
		index % 2 == 0 ? NSAppleEventDescriptor(string: randomWord(&generator)) : NSAppleEventDescriptor(double: .random(in: 0 ... 1000, using: &generator))
	}
	// Few distinct values in the first key, so the second decides often.
	let groups = (0 ..< size).map { _ in Double(Int.random(in: 0 ..< 100, using: &generator)) }

	let realItems = reals.map(NSAppleEventDescriptor.init(double:))
	let integerItems = integers.map(NSAppleEventDescriptor.init(int32:))
	let dateItems = dates.map(NSAppleEventDescriptor.init(date:))
	let wordItems = words.map(NSAppleEventDescriptor.init(string:))
	let groupItems = groups.map(NSAppleEventDescriptor.init(double:))

	func keyed(_ items: [NSAppleEventDescriptor]..., flags: Int = 0) -> () throws -> [Sorting.Column] {
		let lists = items.map { RawList(list($0))! }
		return { try lists.map { try Sorting.classify($0, flags: flags).keys } }
	}

	var result = [
		Case(name: "array of real", parameters: ["----": ArrayOfReal(reals).appleEventDescriptor]) { [.numbers(reals)] },
		Case(name: "reals", parameters: ["----": list(realItems)], keys: keyed(realItems)),
		Case(name: "integers", parameters: ["----": list(integerItems)], keys: keyed(integerItems)),
		Case(name: "dates", parameters: ["----": list(dateItems)], keys: keyed(dateItems)),
	]
	for flags in [0, 1, 2, 4] {
		result.append(Case(name: "text, flags \(flags)", parameters: ["----": list(wordItems), "Cfla": NSAppleEventDescriptor(int32: Int32(flags))], flags: flags, keys: keyed(wordItems, flags: flags)))
	}
	// Every text has the same first 8 bytes and more, as paths in one folder do.
	let paths = words.map { NSAppleEventDescriptor(string: "/Users/someone/Documents/" + $0) }
	result.append(Case(name: "text, one folder's paths", parameters: ["----": list(paths)], keys: keyed(paths)))
	result.append(Case(name: "numbers and text", parameters: ["----": list(mixed)], keys: keyed(mixed)))

	let together = list([list(groupItems), list(wordItems), list(realItems)])
	result.append(Case(name: "together, number and text", parameters: ["----": together, "from": [1, 2].appleEventDescriptor], keys: keyed(groupItems, wordItems)))
	result.append(Case(name: "together, two numbers", parameters: ["----": together, "from": [1, 3].appleEventDescriptor], keys: keyed(groupItems, realItems)))

	// Lists that are 95% sorted, and 95% duplicates (also with remove duplicates).
	let sortedReals = mostlySorted(reals, by: <, &generator)
	let duplicateReals = mostlyDuplicates(reals, &generator)
	let sortedWords = mostlySorted(words, by: <, &generator).map(NSAppleEventDescriptor.init(string:))
	let duplicateWords = mostlyDuplicates(words, &generator).map(NSAppleEventDescriptor.init(string:))
	let uniquely = NSAppleEventDescriptor(boolean: true)
	result += [
		Case(name: "array of real, 95% sorted", parameters: ["----": ArrayOfReal(sortedReals).appleEventDescriptor]) { [.numbers(sortedReals)] },
		Case(name: "reals, 95% sorted", parameters: ["----": list(sortedReals.map(NSAppleEventDescriptor.init(double:)))], keys: keyed(sortedReals.map(NSAppleEventDescriptor.init(double:)))),
		Case(name: "reals, 95% duplicates", parameters: ["----": list(duplicateReals.map(NSAppleEventDescriptor.init(double:)))], keys: keyed(duplicateReals.map(NSAppleEventDescriptor.init(double:)))),
		Case(name: "reals, 95% dup., unique", parameters: ["----": list(duplicateReals.map(NSAppleEventDescriptor.init(double:))), "Uniq": uniquely], unique: true, keys: keyed(duplicateReals.map(NSAppleEventDescriptor.init(double:)))),
		Case(name: "text, 95% sorted", parameters: ["----": list(sortedWords)], keys: keyed(sortedWords)),
		Case(name: "text, 95% duplicates", parameters: ["----": list(duplicateWords)], keys: keyed(duplicateWords)),
		Case(name: "text, 95% dup., unique", parameters: ["----": list(duplicateWords), "Uniq": uniquely], unique: true, keys: keyed(duplicateWords)),
	]
	return result
}

/// The median time of a block, run at least 3 times and for at least half a second (at most 25 times).
func median(_ block: () throws -> Void) rethrows -> Double {
	var times: [Double] = []
	let start = DispatchTime.now().uptimeNanoseconds
	while times.count < 3 || (times.count < 25 && DispatchTime.now().uptimeNanoseconds - start < 500_000_000) {
		let before = DispatchTime.now().uptimeNanoseconds
		try block()
		times.append(Double(DispatchTime.now().uptimeNanoseconds - before) / 1e6)
	}
	return times.sorted()[times.count / 2]
}

func formatted(_ milliseconds: Double) -> String {
	String(format: milliseconds < 10 ? "%9.3f" : "%9.1f", milliseconds)
}

var sizes = [1_000, 100_000, 1_000_000]
var only: String?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
	switch argument {
	case "--sizes": sizes = (arguments.next() ?? "").split(separator: ",").compactMap { Int($0) }
	case "--only": only = arguments.next()
	default:
		FileHandle.standardError.write(Data("usage: sort-benchmark [--sizes 1000,100000] [--only name]\n".utf8))
		exit(2)
	}
}

let dispatcher = CommandDispatcher()
dispatcher.register(ListUtilities.commands())

print("Times in ms (median). command: the whole sortlist, in process; sort: making keys and ordering rows; order:")
print("ordering rows alone.")
for size in sizes {
	print("\n\(size) items" + String(repeating: " ", count: max(0, 27 - "\(size) items".count)) + "  command       sort      order")
	for item in cases(size: size) where only.map({ item.name.contains($0) }) ?? true {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: "SATISort"))
		for (keyword, value) in item.parameters {
			event.setParam(value, forKeyword: FourCharCode(fourCharString: keyword))
		}
		let command = median {
			if let error = dispatcher.dispatch(event).error {
				fatalError("\(item.name): \(error)")
			}
		}
		let sort = try median { _ = item.order(try item.keys()) }
		let keys = try item.keys()
		let order = median { _ = item.order(keys) }
		print(item.name.padding(toLength: 27, withPad: " ", startingAt: 0) + formatted(command) + "  " + formatted(sort) + "  " + formatted(order))
	}
}
