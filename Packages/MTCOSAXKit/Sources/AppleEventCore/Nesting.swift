import Foundation

extension NSAppleEventDescriptor {
	/// How deeply lists and records may nest in a value a command goes through recursively: deeper, a value (sent as
	/// a raw Apple event) ran the main thread out of stack. The same as property lists' limit.
	public static let maximumNesting = 512

	/// -50 for a value nested more than `maximumNesting` levels deep.
	public static let nestedTooDeep = OSAXError(-50, "The value is nested more than \(maximumNesting) levels deep.")

	/// Whether lists or records nest more than `limit` levels deep (an item of the top list is at level 1). Counted
	/// without recursing, so it works however deep they go.
	public func nestsDeeper(than limit: Int = maximumNesting) -> Bool {
		var pending: [(descriptor: NSAppleEventDescriptor, depth: Int)] = [(self, 0)]
		while let (descriptor, depth) = pending.popLast() {
			guard descriptor.descriptorType == typeAEList || descriptor.isRecordDescriptor, descriptor.numberOfItems > 0 else { continue }
			guard depth < limit else { return true }
			for index in 1 ... descriptor.numberOfItems {
				if let item = descriptor.atIndex(index) {
					pending.append((item, depth + 1))
				}
			}
		}
		return false
	}
}
