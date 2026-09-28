import AppleEventCore
import Foundation
import Numerics

/// `topological sort`, which never worked in SatimageOSAX (it replied -1708), implemented from the dictionary.
///
/// An edge `{v1, v2}` means v1 comes before v2 (the dictionary's "v1 > v2"); `dependencies` gives, for each vertex,
/// the vertices that come before it. When several orders are possible, vertices come in the order they were given
/// (the direct parameter, or else their first appearance in the edges). A cycle is error -2700.
enum TopologicalSort {
	static func sort(_ request: AppleEventRequest) throws -> [Int] {
		let given = try request.descriptor(for: Keyword.directObject).map(integers)
		let edgesDescriptor = request.descriptor(for: "edge")
		let dependenciesDescriptor = request.descriptor(for: "depe")
		guard given != nil || edgesDescriptor != nil || dependenciesDescriptor != nil else {
			throw OSAXError.missingParameter
		}

		// A vertex given twice counts once, at its first place.
		var vertices: [Int] = []
		var known: Set<Int> = []
		for vertex in given ?? [] where known.insert(vertex).inserted {
			vertices.append(vertex)
		}
		var edges: [(Int, Int)] = []
		if let edgesDescriptor {
			edges = try self.edges(edgesDescriptor)
		}
		if let dependenciesDescriptor {
			let lists = ListUtilities.items(dependenciesDescriptor) ?? [dependenciesDescriptor]
			if given == nil {
				vertices = Array(1 ..< lists.count + 1)
				known = Set(vertices)
			}
			guard lists.count == vertices.count else {
				throw OSAXError.parameterError
			}
			for (vertex, list) in zip(vertices, lists) {
				for earlier in try integers(list) {
					edges.append((earlier, vertex))
				}
			}
		}
		for (from, to) in edges {
			for vertex in [from, to] where known.insert(vertex).inserted {
				vertices.append(vertex)
			}
		}
		return try order(vertices, edges)
	}

	/// Kahn's algorithm, taking the earliest given vertex among those that can come next: those are kept in a heap
	/// by their place, so it takes time in proportion to E + V log V (it used to look through them all each time).
	static func order(_ vertices: [Int], _ edges: [(Int, Int)]) throws -> [Int] {
		let place = Dictionary(uniqueKeysWithValues: vertices.enumerated().map { ($1, $0) })
		var incoming = [Int](repeating: 0, count: vertices.count)
		var outgoing = [[Int]](repeating: [], count: vertices.count)
		for (from, to) in edges {
			incoming[place[to]!] += 1
			outgoing[place[from]!].append(place[to]!)
		}
		var ready = MinHeap(incoming.indices.filter { incoming[$0] == 0 })
		var result: [Int] = []
		while let next = ready.pop() {
			result.append(vertices[next])
			for after in outgoing[next] {
				incoming[after] -= 1
				if incoming[after] == 0 {
					ready.push(after)
				}
			}
		}
		guard result.count == vertices.count else {
			throw OSAXError.general("The ordering has a cycle.")
		}
		return result
	}

	/// A binary heap of integers, smallest first.
	struct MinHeap {
		private var items: [Int] = []

		init(_ items: [Int]) {
			items.forEach { push($0) }
		}

		mutating func push(_ item: Int) {
			items.append(item)
			var child = items.count - 1
			while child > 0, items[(child - 1) / 2] > items[child] {
				items.swapAt(child, (child - 1) / 2)
				child = (child - 1) / 2
			}
		}

		mutating func pop() -> Int? {
			guard let first = items.first else { return nil }
			items.swapAt(0, items.count - 1)
			items.removeLast()
			var parent = 0
			while true {
				let left = 2 * parent + 1, right = left + 1
				var smallest = parent
				if left < items.count, items[left] < items[smallest] { smallest = left }
				if right < items.count, items[right] < items[smallest] { smallest = right }
				guard smallest != parent else { return first }
				items.swapAt(parent, smallest)
				parent = smallest
			}
		}
	}

	/// Pairs `{{v1, v2}, …}` or a flat list `{v1, v2, v3, v4, …}`.
	static func edges(_ descriptor: NSAppleEventDescriptor) throws -> [(Int, Int)] {
		let items = ListUtilities.items(descriptor) ?? [descriptor]
		if items.allSatisfy({ !ListUtilities.isList($0) }) {
			let flat = try integers(descriptor)
			guard flat.count.isMultiple(of: 2) else {
				throw OSAXError.parameterError
			}
			return stride(from: 0, to: flat.count, by: 2).map { (flat[$0], flat[$0 + 1]) }
		}
		return try items.map { pair in
			let ends = try integers(pair)
			guard ends.count == 2 else {
				throw OSAXError.parameterError
			}
			return (ends[0], ends[1])
		}
	}

	/// Whole numbers (a list, or one); error -1700 for anything else.
	static func integers(_ descriptor: NSAppleEventDescriptor) throws -> [Int] {
		try (ListUtilities.items(descriptor) ?? [descriptor]).map { item in
			let value = try Numbers.number(item)
			guard value.rounded() == value, abs(value) <= Double(Int32.max) else {
				throw OSAXError.coercionFailed
			}
			return Int(value)
		}
	}
}
