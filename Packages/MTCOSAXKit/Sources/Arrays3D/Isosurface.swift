import AppleEventCore
import Foundation

/// `isosurface`: marching cubes. SatimageOSAX's left most of the surface out (in a single cell, only corner 0 alone
/// above or below the value made a triangle), so this follows the dictionary rather than its triangles.
///
/// Each cell of the grid (x varying fastest, then y, then z) is cut where the value crosses its edges, a corner
/// counting as below the value if it's less. The triangles for each pattern of corners below are made once, from the
/// corners alone (`table`), rather than copied from a published table: on each face, the edges where the value is
/// crossed are joined from where the face goes below the value to where it comes back above, going round the face
/// the same way, so corners below that touch only at a corner stay apart. That depends on the face alone, so two
/// cells that share a face cut it the same way and the surface has no cracks. Each loop of edges is a fan of
/// triangles, turned so that they face toward larger values (their vertices go counterclockwise seen from there).
enum Isosurface {
	/// A cell's corner k is at (k & 1, k >> 1 & 1, k >> 2 & 1) from its first corner.
	static func position(_ corner: Int) -> SIMD3<Int> {
		SIMD3(corner & 1, corner >> 1 & 1, corner >> 2 & 1)
	}

	static let positions = (0 ..< 8).map(position)

	/// The 12 edges, as their corners (the first nearer the cell's first corner).
	static let edges: [(Int, Int)] = (0 ..< 8).flatMap { a in
		[1, 2, 4].compactMap { bit in a & bit == 0 ? (a, a | bit) : nil }
	}

	/// The 6 faces, each's corners counterclockwise seen from outside the cell.
	static let faces: [[Int]] = (0 ..< 3).flatMap { axis in
		[0, 1].map { side in
			let (u, v) = (1 << ((axis + 1) % 3), 1 << ((axis + 2) % 3))
			let base = side << axis
			let corners = [base, base | u, base | u | v, base | v]
			// u, v, outward normal: counterclockwise from outside if (u × v) points outward, which is on the upper side.
			return side == 1 ? corners : corners.reversed()
		}
	}

	/// The axis each edge goes along.
	static let edgeAxes = edges.map { ($0.0 ^ $0.1).trailingZeroBitCount }

	static func edge(_ a: Int, _ b: Int) -> Int {
		edges.firstIndex { $0 == (min(a, b), max(a, b)) }!
	}

	/// For each pattern of corners below the value (bit k for corner k), its triangles: three edges each.
	static let table: [[Int]] = (0 ..< 256).map(triangles)

	static func triangles(_ pattern: Int) -> [Int] {
		let below = (0 ..< 8).map { pattern >> $0 & 1 == 1 }
		// Each crossed edge, and the one the surface goes to next round its loop.
		var next: [Int: Int] = [:]
		for face in faces {
			// The crossed edges in order round the face, and whether the face goes below the value there.
			let crossings = (0 ..< 4).compactMap { index -> (edge: Int, entersBelow: Bool)? in
				let (a, b) = (face[index], face[(index + 1) % 4])
				return below[a] == below[b] ? nil : (edge(a, b), below[b])
			}
			for (index, crossing) in crossings.enumerated() where crossing.entersBelow {
				next[crossing.edge] = crossings[(index + 1) % crossings.count].edge
			}
		}
		var result: [Int] = []
		var done = Set<Int>()
		for start in next.keys.sorted() where !done.contains(start) {
			var loop = [start]
			var edge = next[start]!
			while edge != start {
				loop.append(edge)
				edge = next[edge]!
			}
			done.formUnion(loop)
			for index in 1 ..< loop.count - 1 {
				result += [loop[0], loop[index], loop[index + 1]]
			}
		}
		return result
	}

	/// The triangles, 9 numbers each (three vertices' x, y and z, in the scales' coordinates). Cells with a missing or
	/// infinite value at a corner are left out (an infinite one made the vertices NaN). -50 for a scale that isn't
	/// finite, or for more than `Arrays3D.maximumSize` numbers.
	static func triangles(_ field: [Double], counts: [Int], scales: [[Double]], at value: Double) throws -> [Double] {
		let surface = try Surface(field, counts: counts, scales: scales, at: value)
		return [Double](unsafeUninitializedCapacity: surface.count) { buffer, initialized in
			surface.write(into: buffer)
			initialized = surface.count
		}
	}

	/// `triangles` as an `array of real`, written straight into it: no array of them to copy (and to grow, which
	/// near the limit made 2.5 GB of 0.8).
	static func descriptor(_ field: [Double], counts: [Int], scales: [[Double]], at value: Double) throws -> NSAppleEventDescriptor {
		let surface = try Surface(field, counts: counts, scales: scales, at: value)
		return try ArrayOfReal.descriptor(count: surface.count, surface.write)
	}

	/// A surface's size, counted from its cells' patterns, and then its numbers.
	struct Surface {
		let field: [Double]
		let counts: [Int]
		let scales: [[Double]]
		let value: Double
		let count: Int

		init(_ field: [Double], counts: [Int], scales: [[Double]], at value: Double) throws {
			guard scales.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
				throw OSAXError(-50, "An isosurface needs each axis's scale finite.")
			}
			(self.field, self.counts, self.scales, self.value) = (field, counts, scales, value)
			var count = 0
			Self.forEachCell(field, counts: counts, at: value) { _, cut, _ in
				count += 3 * cut.count
			}
			guard count <= Arrays3D.maximumSize else {
				throw Arrays3D.tooLarge
			}
			self.count = count
		}

		/// Each cell with a surface in it (no missing or infinite corner): its first corner, its edges cut, and its
		/// corners' values.
		private static func forEachCell(_ field: [Double], counts: [Int], at value: Double, _ body: (SIMD3<Int>, [Int], [Double]) -> Void) {
			let (nx, ny, nz) = (counts[0], counts[1], counts[2])
			var values = [Double](repeating: 0, count: 8)
			guard nx > 1, ny > 1, nz > 1 else {
				return
			}
			for z in 0 ..< nz - 1 {
				for y in 0 ..< ny - 1 {
					for x in 0 ..< nx - 1 {
						var pattern = 0
						var missing = false
						for corner in 0 ..< 8 {
							let p = positions[corner]
							let v = field[(x + p.x) + nx * (y + p.y) + nx * ny * (z + p.z)]
							values[corner] = v
							missing = missing || !v.isFinite
							if v < value {
								pattern |= 1 << corner
							}
						}
						let cut = table[pattern]
						if !missing, !cut.isEmpty {
							body(SIMD3(x, y, z), cut, values)
						}
					}
				}
			}
		}

		/// The numbers, `count` of them.
		func write(into buffer: UnsafeMutableBufferPointer<Double>) {
			var index = 0
			Self.forEachCell(field, counts: counts, at: value) { cell, cut, values in
				for edge in cut {
					let (a, b) = edges[edge]
					let along = edgeAxes[edge]
					let fraction = (value - values[a]) / (values[b] - values[a])
					let corner = cell &+ positions[a]
					for axis in 0 ..< 3 {
						let from = scales[axis][corner[axis]]
						if axis == along {
							let to = scales[axis][corner[axis] + 1]
							// Each end weighted where the distance between them overflows (-1e308 to 1e308).
							buffer[index] = (to - from).isFinite ? from + fraction * (to - from) : from * (1 - fraction) + to * fraction
						} else {
							buffer[index] = from
						}
						index += 1
					}
				}
			}
		}
	}
}
