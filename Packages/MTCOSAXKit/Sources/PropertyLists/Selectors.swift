import AppleEventCore
import Foundation

/// How a command picks children: `index`, `key` (or a list of keys), or a `using` path such as
/// `"key1/key2[4]/key3[2]"`. Keys in a path can't contain `/` or brackets (SatimageOSAX had no escaping).
enum Selector {
	case none
	case index(Int)
	case key(String)
	case keys([String])
	case path([Step])

	enum Step: Equatable {
		case key(String)
		case index(Int)
	}

	/// Error -1 for more than one selector, a list of indices, or a malformed path.
	init(_ request: AppleEventRequest) throws {
		let index = request.descriptor(for: "indx")
		let key = request.descriptor(for: "key ")
		let path = try request.parameter("by  ", as: String.self)
		guard [index != nil, key != nil, path != nil].filter({ $0 }).count <= 1 else {
			throw PropertyLists.invalid
		}
		if let index {
			guard index.descriptorType != typeAEList else {
				throw PropertyLists.invalid
			}
			self = .index(try Int(appleEventDescriptor: index))
		} else if let key {
			if key.descriptorType == typeAEList {
				self = .keys(try [String](appleEventDescriptor: key))
			} else {
				self = .key(try String(appleEventDescriptor: key))
			}
		} else if let path {
			self = .path(try Self.steps(path))
		} else {
			self = .none
		}
	}

	/// `a/b[2][3]/c` as steps. Slashes at either end are ignored (SatimageOSAX stopped working after a trailing
	/// one). Each part needs a key.
	static func steps(_ path: String) throws -> [Step] {
		var steps: [Step] = []
		for part in path.split(separator: "/", omittingEmptySubsequences: true) {
			let bracket = part.firstIndex(of: "[") ?? part.endIndex
			let name = part[..<bracket]
			guard !name.isEmpty, !name.contains("]") else {
				throw PropertyLists.invalid
			}
			steps.append(.key(String(name)))
			var rest = part[bracket...]
			while !rest.isEmpty {
				// A whole number (Int(_:) alone also takes "+1").
				// Indices start at 1 (`[-9223372036854775808]` trapped, taking 1 from it).
				guard rest.first == "[", let close = rest.firstIndex(of: "]"), rest[rest.index(after: rest.startIndex)] != "+",
				      let index = Int(rest[rest.index(after: rest.startIndex) ..< close]), index >= 1
				else {
					throw PropertyLists.invalid
				}
				steps.append(.index(index))
				rest = rest[rest.index(after: close)...]
			}
		}
		guard !steps.isEmpty else {
			throw PropertyLists.invalid
		}
		return steps
	}
}

extension PropertyLists {
	/// The child for one step: -1 for a key in something that isn't a dictionary, an index in something that
	/// isn't an array, or an index out of range; `missingKey` for a key that isn't there.
	static func child(of node: Node, _ step: Selector.Step, missingKey: OSAXError) throws -> Node {
		switch (step, node.content) {
		case let (.key(key), .dictionary):
			guard let child = node.child(forKey: key) else {
				throw missingKey
			}
			return child
		case let (.index(index), .array(items)):
			guard index >= 1, index <= items.count else {
				throw invalid
			}
			return items[index - 1]
		default:
			throw invalid
		}
	}

	static func follow(_ steps: [Selector.Step], from node: Node, missingKey: OSAXError) throws -> Node {
		try steps.reduce(node) { try child(of: $0, $1, missingKey: missingKey) }
	}
}
