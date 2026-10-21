import AppleEventCore
import Foundation
import PropertyLists

/// An open 3D array: a scalar field (one number for each point of an nx × ny × nz grid) or a vector field (three),
/// with each axis's scale (its points' coordinates). Kept as 8-byte reals; SatimageOSAX kept 4-byte ones.
final class Array3D: StoredDocument {
	/// Its number in the document store.
	let number: Int
	let pool = ""
	/// 3D arrays are outside pools.
	let isPooled = false
	/// The number in its references, from 3D arrays' own counter.
	let id: UInt32
	var name: String
	/// nx, ny and nz.
	let counts: [Int]
	/// Each axis's coordinates, as many as its count.
	let scales: [[Double]]
	/// One field (scalar) or three (a vector field's components), each nx × ny × nz numbers, x varying fastest:
	/// the number for {ix, iy, iz} is at ix + nx × iy + nx × ny × iz.
	private(set) var fields: [[Double]]

	init(number: Int, id: UInt32, name: String, counts: [Int], scales: [[Double]], fields: [[Double]]) {
		self.number = number
		self.id = id
		self.name = name
		self.counts = counts
		self.scales = scales
		self.fields = fields
	}

	func didClose() {
		fields = []
	}

	var isVectorField: Bool {
		fields.count == 3
	}

	/// A field's smallest and largest number, leaving out NaN (`missing value`); nil if it has none.
	static func range(_ values: [Double]) -> (minimum: Double, maximum: Double)? {
		var minimum = Double.infinity, maximum = -Double.infinity, any = false
		for value in values where !value.isNaN {
			minimum = min(minimum, value)
			maximum = max(maximum, value)
			any = true
		}
		return any ? (minimum, maximum) : nil
	}

	/// A field by its 1-based `field index` (default 1); error -1 for one it doesn't have, as recorded.
	func field(_ index: Int?) throws -> [Double] {
		let index = index ?? 1
		guard (1 ... fields.count).contains(index) else {
			throw OSAXError(-1)
		}
		return fields[index - 1]
	}
}
