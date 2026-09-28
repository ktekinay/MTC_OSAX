import AppleEventCore
import Foundation

/// An element of a property list. Elements are objects, so a script's reference to one stays valid while other
/// elements change, until it's removed or its document is closed.
final class Node {
	enum Content {
		/// Keys to `Node`s. An `NSMutableDictionary` so keys come out in the same (hashing) order as SatimageOSAX's
		/// Core Foundation dictionaries, in `PlistGet` records and JSON.
		case dictionary(NSMutableDictionary)
		case array([Node])
		case string(String)
		case integer(Int64)
		case real(Double)
		case boolean(Bool)
		case date(Date)
		case data(Data)
	}

	var content: Content
	weak var parent: Node?
	let number: Int
	unowned let document: Document

	init(_ content: Content, in document: Document) {
		self.content = content
		self.document = document
		number = document.register()
		document.elements[number] = WeakNode(self)
		for child in children {
			child.parent = self
		}
	}

	/// The children of a dictionary (in key order) or an array; none for other values.
	var children: [Node] {
		switch content {
		case let .dictionary(dictionary): dictionary.allKeys.compactMap { dictionary[$0] as? Node }
		case let .array(items): items
		default: []
		}
	}

	var keys: [String] {
		if case let .dictionary(dictionary) = content {
			return dictionary.allKeys.compactMap { $0 as? String }
		}
		return []
	}

	/// Whether the node is still part of its document (not removed, and the document is open).
	var isAttached: Bool {
		var node = self
		while let parent = node.parent {
			node = parent
		}
		return node === document.root && document.isOpen
	}

	/// SatimageOSAX's names for the types (`PlistType`).
	var typeName: String {
		switch content {
		case .dictionary: "dictionary"
		case .array: "array"
		case .string: "string"
		case .integer: "integer"
		case .real: "real"
		case .boolean: "boolean"
		case .date: "date"
		case .data: "base64"
		}
	}

	func setChild(_ child: Node, forKey key: String) {
		guard case let .dictionary(dictionary) = content else { return }
		child.parent = self
		dictionary[key] = child
	}

	func removeChild(forKey key: String) {
		guard case let .dictionary(dictionary) = content, let child = dictionary[key] as? Node else { return }
		dictionary.removeObject(forKey: key)
		child.parent = nil
	}

	func insert(_ child: Node, at index: Int) {
		guard case var .array(items) = content else { return }
		child.parent = self
		items.insert(child, at: index)
		content = .array(items)
	}

	func replace(at index: Int, with child: Node) {
		guard case var .array(items) = content else { return }
		items[index].parent = nil
		child.parent = self
		items[index] = child
		content = .array(items)
	}

	func remove(at index: Int) {
		guard case var .array(items) = content else { return }
		items.remove(at: index).parent = nil
		content = .array(items)
	}

	func child(forKey key: String) -> Node? {
		if case let .dictionary(dictionary) = content {
			return dictionary[key] as? Node
		}
		return nil
	}

	/// A deep copy in `document`.
	func copy(in document: Document) -> Node {
		switch content {
		case let .dictionary(dictionary):
			return Node(.dictionary(dictionary.mappingValues { ($0 as! Node).copy(in: document) }), in: document)
		case let .array(items):
			return Node(.array(items.map { $0.copy(in: document) }), in: document)
		default:
			return Node(content, in: document)
		}
	}
}

struct WeakNode {
	weak var node: Node?

	init(_ node: Node) {
		self.node = node
	}
}

/// An open document of any kind (a property list, an XML document), as the store and pools see it.
public protocol StoredDocument: AnyObject {
	var number: Int { get }
	var pool: String { get }
	/// Called when the document is closed (by its own command or `DeletePool`), to release what it holds.
	func didClose()
}

/// An open property list: its tree, where it came from, and its pool.
final class Document: StoredDocument {
	let number: Int
	var pool: String
	var root: Node!
	var url: URL?
	var isBinary = false
	var identifier: String?
	var isOpen = true
	/// `PlistRetain` adds one; `PlistClose` closes the document when it gets to 0.
	var retainCount = 1
	fileprivate(set) var elements: [Int: WeakNode] = [:]
	private var nextElement = 1
	/// When the table next drops the entries of elements that no longer exist (every copy `PlistSet … to` makes,
	/// and the scratch elements of `PlistExist` and `PlistMatch`, get one, so it grew for as long as the document
	/// was open).
	private var compactAt = 1024

	init(number: Int, pool: String) {
		self.number = number
		self.pool = pool
	}

	func didClose() {
		isOpen = false
	}

	fileprivate func register() -> Int {
		if elements.count >= compactAt {
			elements = elements.filter { $0.value.node != nil }
			compactAt = max(1024, elements.count * 2)
		}
		defer { nextElement += 1 }
		return nextElement
	}

	func element(_ number: Int) -> Node? {
		guard let node = elements[number]?.node, node.isAttached else {
			return nil
		}
		return node
	}
}

/// The open documents of every kind, in the order they were opened, and the pools they're in. One per app.
public final class DocumentStore: @unchecked Sendable {
	public private(set) var allDocuments: [any StoredDocument] = []
	/// The pool new documents go into (`SetPool`); "" at launch.
	public var currentPool = ""
	private var nextDocument = 1
	/// Finds the document an XMLRef (or another kind of reference) belongs to, for `GetPool`; nil if it isn't
	/// that kind of reference.
	private var resolvers: [(NSAppleEventDescriptor) throws -> (any StoredDocument)?] = []

	public init() {}

	/// Whether any document is open; the app doesn't quit for being idle while one is.
	public var hasOpenDocuments: Bool {
		!allDocuments.isEmpty
	}

	/// The open property lists.
	var documents: [Document] {
		allDocuments.compactMap { $0 as? Document }
	}

	/// Adds a new document, numbered and in `pool` (default: the current pool).
	public func add<T: StoredDocument>(pool: String?, _ make: (_ number: Int, _ pool: String) -> T) -> T {
		let document = make(nextDocument, pool ?? currentPool)
		nextDocument += 1
		allDocuments.append(document)
		return document
	}

	func newDocument(pool: String?) -> Document {
		add(pool: pool) { Document(number: $0, pool: $1) }
	}

	public func close(_ document: any StoredDocument) {
		allDocuments.removeAll { $0 === document }
		document.didClose()
	}

	func document(number: Int) -> Document? {
		documents.first { $0.number == number }
	}

	/// Lets `GetPool` find the documents of another kind of reference.
	public func addResolver(_ resolver: @escaping (NSAppleEventDescriptor) throws -> (any StoredDocument)?) {
		resolvers.append(resolver)
	}

	/// The document of a CFRef or of another kind of reference; error -1700 if it's neither.
	func storedDocument(_ descriptor: NSAppleEventDescriptor) throws -> any StoredDocument {
		if Self.isReference(descriptor) {
			return try node(descriptor).document
		}
		for resolver in resolvers {
			if let document = try resolver(descriptor) {
				return document
			}
		}
		throw OSAXError.coercionFailed
	}

	// MARK: References

	/// A CFRef (`CFob`) for an element: its document's number, "MTCp", and its element number.
	static let referenceType = FourCharCode(fourCharString: "CFob")

	func reference(_ node: Node) -> NSAppleEventDescriptor {
		var data = Data()
		withUnsafeBytes(of: UInt32(node.document.number).littleEndian) { data.append(contentsOf: $0) }
		data.append(contentsOf: Array("MTCp".utf8))
		withUnsafeBytes(of: UInt64(node.number).littleEndian) { data.append(contentsOf: $0) }
		return NSAppleEventDescriptor(descriptorType: Self.referenceType, data: data)!
	}

	/// The element a CFRef refers to: error -1700 if it isn't a CFRef, -1728 if its document was closed or the
	/// element removed.
	func node(_ descriptor: NSAppleEventDescriptor) throws -> Node {
		guard descriptor.descriptorType == Self.referenceType else {
			throw OSAXError.coercionFailed
		}
		let data = descriptor.data
		guard data.count == 16, data[4 ..< 8] == Data("MTCp".utf8) else {
			throw PropertyLists.noSuchElement
		}
		let document = data[0 ..< 4].withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
		let element = data[8 ..< 16].withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
		// A forged or corrupted number beyond Int's range is just an element that doesn't exist.
		guard let element = Int(exactly: element), let node = self.document(number: Int(document))?.element(element) else {
			throw PropertyLists.noSuchElement
		}
		return node
	}

	static func isReference(_ descriptor: NSAppleEventDescriptor) -> Bool {
		descriptor.descriptorType == referenceType
	}
}
