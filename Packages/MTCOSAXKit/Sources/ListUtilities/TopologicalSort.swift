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
		for vertex in given ?? [] where !vertices.contains(vertex) {
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
			for vertex in [from, to] where !vertices.contains(vertex) {
				vertices.append(vertex)
			}
		}
		return try order(vertices, edges)
	}

	/// Kahn's algorithm, taking the earliest given vertex among those that can come next.
	static func order(_ vertices: [Int], _ edges: [(Int, Int)]) throws -> [Int] {
		var incoming = Dictionary(uniqueKeysWithValues: vertices.map { ($0, 0) })
		var outgoing: [Int: [Int]] = [:]
		for (from, to) in edges {
			incoming[to, default: 0] += 1
			outgoing[from, default: []].append(to)
		}
		var remaining = vertices
		var result: [Int] = []
		while let index = remaining.firstIndex(where: { incoming[$0] == 0 }) {
			let vertex = remaining.remove(at: index)
			result.append(vertex)
			for next in outgoing[vertex] ?? [] {
				incoming[next]! -= 1
			}
		}
		guard remaining.isEmpty else {
			throw OSAXError.general("The ordering has a cycle.")
		}
		return result
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
