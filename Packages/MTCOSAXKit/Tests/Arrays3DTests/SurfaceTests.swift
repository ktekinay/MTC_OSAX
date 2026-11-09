import AppleEventCore
import Foundation
import Testing
@testable import Arrays3D

/// Marching cubes: the table made from the corners, and surfaces that are closed, on the value, and facing the way
/// the field rises.
struct IsosurfaceTests {
	typealias Point = SIMD3<Double>

	private func triangles(_ field: [Double], _ counts: [Int], at value: Double, scales: [[Double]]? = nil) throws -> [[Point]] {
		let scales = scales ?? counts.map { (0 ..< $0).map(Double.init) }
		let numbers = try Isosurface.triangles(field, counts: counts, scales: scales, at: value)
		return stride(from: 0, to: numbers.count, by: 9).map { start in
			(0 ..< 3).map { Point(numbers[start + 3 * $0], numbers[start + 3 * $0 + 1], numbers[start + 3 * $0 + 2]) }
		}
	}

	private func field(_ counts: [Int], _ function: (Point) -> Double) -> [Double] {
		var values: [Double] = []
		for z in 0 ..< counts[2] {
			for y in 0 ..< counts[1] {
				for x in 0 ..< counts[0] {
					values.append(function(Point(Double(x), Double(y), Double(z))))
				}
			}
		}
		return values
	}

	private func normal(_ triangle: [Point]) -> Point {
		let (u, v) = (triangle[1] - triangle[0], triangle[2] - triangle[0])
		return Point(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
	}

	/// Each pattern cuts exactly the edges whose corners are on different sides, each loop closed.
	@Test func tableCutsTheCrossedEdges() {
		for pattern in 0 ..< 256 {
			let below = (0 ..< 8).map { pattern >> $0 & 1 == 1 }
			let crossed = Set(Isosurface.edges.indices.filter { below[Isosurface.edges[$0].0] != below[Isosurface.edges[$0].1] })
			let cut = Isosurface.table[pattern]
			#expect(cut.count % 3 == 0)
			#expect(Set(cut) == crossed, "pattern \(pattern)")
			// Within the cell, each segment between two crossed edges is used by an even number of triangles' sides
			// but for the loops' own sides: every edge of a triangle fan's outline once, inner diagonals twice.
			var sides: [Set<Int>: Int] = [:]
			for triangle in stride(from: 0, to: cut.count, by: 3) {
				for (a, b) in [(0, 1), (1, 2), (2, 0)] {
					sides[[cut[triangle + a], cut[triangle + b]], default: 0] += 1
				}
			}
			#expect(sides.values.allSatisfy { $0 == 1 || $0 == 2 }, "pattern \(pattern)")
		}
	}

	/// A linear field's surface is exactly on the value (each vertex interpolated along its edge), and every
	/// triangle faces the way the field rises.
	@Test func linearField() throws {
		let gradient = Point(1, 2, -3)
		let counts = [5, 4, 6]
		let values = field(counts) { ($0 * gradient).sum() }
		for value in [-4.5, 0.3, 2, 7.25] {
			let surface = try triangles(values, counts, at: value)
			#expect(!surface.isEmpty)
			for triangle in surface {
				for vertex in triangle {
					#expect(abs((vertex * gradient).sum() - value) < 1e-12)
				}
				let n = normal(triangle)
				#expect((n * gradient).sum() >= 0, "\(triangle)")
			}
		}
	}

	/// A sphere's surface (the distance from a point inside the grid) is closed: every side of a triangle is shared
	/// with exactly one other, the other way round; and it faces outward, where the distance rises.
	@Test func closedAndFacingOut() throws {
		let counts = [9, 10, 8]
		// Not at a distance of a value from any grid point (4.3, 4.6, 3.4 is 3.1 from 7, 4, 2): a surface through a
		// corner has several vertices there, and degenerate triangles.
		let center = Point(4.31, 4.57, 3.43)
		let values = field(counts) { (($0 - center) * ($0 - center)).sum().squareRoot() }
		for value in [1.0, 2.5, 3.1] {
			let surface = try triangles(values, counts, at: value)
			var sides: [String: Int] = [:]
			func key(_ a: Point, _ b: Point) -> String { "\(a.x),\(a.y),\(a.z)>\(b.x),\(b.y),\(b.z)" }
			for triangle in surface {
				for (a, b) in [(0, 1), (1, 2), (2, 0)] where triangle[a] != triangle[b] {
					sides[key(triangle[a], triangle[b]), default: 0] += 1
				}
				let middle = (triangle[0] + triangle[1] + triangle[2]) / 3
				#expect((normal(triangle) * (middle - center)).sum() >= 0)
			}
			for (side, count) in sides {
				let parts = side.split(separator: ">")
				#expect(count == 1 && sides["\(parts[1])>\(parts[0])"] == 1, "\(side), value \(value)")
			}
		}
	}

	/// A field of one 1 at the center of 0s: an octahedron of 8 triangles, as SatimageOSAX's was; in the scales'
	/// coordinates.
	@Test func octahedron() throws {
		var values = [Double](repeating: 0, count: 27)
		values[13] = 1
		let surface = try triangles(values, [3, 3, 3], at: 0.5)
		#expect(surface.count == 8)
		#expect(Set(surface.flatMap { $0 }) == [Point(0.5, 1, 1), Point(1.5, 1, 1), Point(1, 0.5, 1), Point(1, 1.5, 1), Point(1, 1, 0.5), Point(1, 1, 1.5)])
		let scaled = try triangles(values, [3, 3, 3], at: 0.5, scales: [[10, 15, 20], [0, 1, 2], [0, 1, 4]])
		#expect(Set(scaled.flatMap { $0 }) == [Point(12.5, 1, 1), Point(17.5, 1, 1), Point(15, 0.5, 1), Point(15, 1.5, 1), Point(15, 1, 0.5), Point(15, 1, 2.5)])
		// At the field's ends: degenerate triangles at the 1 (it isn't below the value), none at 0.
		#expect(try triangles(values, [3, 3, 3], at: 1).count == 8)
		#expect(try triangles(values, [3, 3, 3], at: 0).isEmpty)
	}

	/// Cells with a missing value are left out; a grid one point thick has no cells.
	@Test func missingValuesAndThinGrids() throws {
		var values = [Double](repeating: 0, count: 27)
		values[13] = 1
		values[0] = .nan
		#expect(try triangles(values, [3, 3, 3], at: 0.5).count == 7)
		#expect(try triangles([0, 1, 0, 1], [2, 2, 1], at: 0.5).isEmpty)
	}

	/// Infinite values are left out as missing ones are (they made the vertices NaN); a scale that isn't finite is
	/// -50, and one whose spacing overflows still gives finite vertices. Audit R3.
	@Test func infinities() throws {
		var values = [Double](repeating: 1, count: 8)
		values[0] = -.infinity
		#expect(try triangles(values, [2, 2, 2], at: 0).isEmpty)
		#expect(throws: OSAXError.self) { try triangles([0, 1, 0, 1, 0, 1, 0, 1], [2, 2, 2], at: 0.5, scales: [[0, .infinity], [0, 1], [0, 1]]) }
		let wide = try triangles([0, 1, 0, 1, 0, 1, 0, 1], [2, 2, 2], at: 0.5, scales: [[-1e308, 1e308], [0, 1], [0, 1]])
		#expect(!wide.isEmpty && wide.allSatisfy { $0.allSatisfy { $0.x == 0 && $0.y.isFinite && $0.z.isFinite } })
	}

	/// What `triangles` gives is what the command's `array of real` holds (written straight into it).
	@Test func descriptorMatchesTriangles() throws {
		let values = field([4, 4, 4]) { point in let d = point - Point(1.5, 1.5, 1.5); return (d * d).sum() }
		let scales = [[0, 1, 2, 3], [0, 2, 4, 6], [0, 0.5, 1, 1.5]]
		let numbers = try Isosurface.triangles(values, counts: [4, 4, 4], scales: scales, at: 2)
		#expect(numbers.count > 100)
		#expect(ArrayOfReal.values(of: try Isosurface.descriptor(values, counts: [4, 4, 4], scales: scales, at: 2)) == numbers)
	}
}

/// Streamlines through fields whose streamlines are known.
struct StreamlineTests {
	typealias Point = SIMD3<Double>

	private func array(_ counts: [Int], scales: [[Double]]? = nil, _ velocity: (Point) -> Point) -> Array3D {
		let scales = scales ?? counts.map { (0 ..< $0).map(Double.init) }
		var fields: [[Double]] = [[], [], []]
		for z in 0 ..< counts[2] {
			for y in 0 ..< counts[1] {
				for x in 0 ..< counts[0] {
					let v = velocity(Point(scales[0][x], scales[1][y], scales[2][z]))
					for axis in 0 ..< 3 {
						fields[axis].append(v[axis])
					}
				}
			}
		}
		return Array3D(number: 1, id: 1, name: "test", counts: counts, scales: scales, fields: fields)
	}

	private func points(_ numbers: [Double]) -> [Point] {
		stride(from: 0, to: numbers.count, by: 3).map { Point(numbers[$0], numbers[$0 + 1], numbers[$0 + 2]) }
	}

	/// A uniform flow: a straight line, one step apart, ending on the box's edge; backward, the other way.
	@Test func uniformFlow() throws {
		let flow = try Streamline(array([5, 3, 3]) { _ in Point(2, 0, 0) })
		let forward = points(try flow.points(from: Point(0, 1, 1), resolution: 1, backward: false))
		#expect(forward == (0 ... 4).map { Point(Double($0), 1, 1) })
		let fine = points(try flow.points(from: Point(0.1, 1, 1), resolution: 0.25, backward: false))
		#expect(fine.first == Point(0.1, 1, 1) && fine.last == Point(4, 1, 1) && fine.count == 17)
		let back = points(try flow.points(from: Point(2.5, 1, 1), resolution: 1, backward: true))
		#expect(back == [Point(2.5, 1, 1), Point(1.5, 1, 1), Point(0.5, 1, 1), Point(0, 1, 1)])
		#expect(throws: OSAXError(2000)) { try flow.points(from: Point(5.5, 1, 1), resolution: 1, backward: false) }
	}

	/// A field too large to square (1e200) is followed as any other (it stopped at the start); a step that overflows
	/// is -50 (it made NaN points). Audit R1, R2.
	@Test func extremeFieldsAndSteps() throws {
		let large = try Streamline(array([5, 3, 3]) { _ in Point(1e200, 0, 0) })
		#expect(points(try large.points(from: Point(0, 1, 1), resolution: 1, backward: false)) == (0 ... 4).map { Point(Double($0), 1, 1) })
		let tiny = try Streamline(array([5, 3, 3]) { _ in Point(1e-200, 0, 0) })
		#expect(points(try tiny.points(from: Point(0, 1, 1), resolution: 1, backward: false)).count == 5)
		let flow = try Streamline(array([2, 2, 2], scales: [[0, 10], [0, 10], [0, 10]]) { _ in Point(1, 0, 0) })
		#expect(throws: OSAXError.self) { try flow.points(from: Point(1, 1, 1), resolution: 1e308, backward: false) }
	}

	/// Axes of one point: the far corners along them are left out (they're past the field's end), on every grid
	/// that's flat on one or two axes.
	@Test func axesOfOnePoint() throws {
		for counts in [[1, 4, 1], [4, 1, 1], [1, 1, 4], [4, 4, 1], [1, 4, 4], [4, 1, 4]] {
			let axis = counts.firstIndex(of: 4)!
			var direction = Point(0, 0, 0)
			direction[axis] = 1
			let flow = try Streamline(array(counts) { _ in direction })
			let line = points(try flow.points(from: Point(0, 0, 0), resolution: 1, backward: false))
			#expect(line == (0 ... 3).map { Double($0) * direction }, "\(counts)")
		}
	}

	/// A rotating flow about the z axis: the streamline stays on its circle (fourth order: within 1e-3 here), and
	/// goes round it until the steps run out.
	@Test func rotatingFlow() throws {
		let scale = (0 ... 20).map { Double($0) / 5 - 2 } // -2 to 2
		let flow = try Streamline(array([21, 21, 2], scales: [scale, scale, [0, 1]]) { Point(-$0.y, $0.x, 0) })
		let circle = points(try flow.points(from: Point(1, 0, 0.5), resolution: 0.5, backward: false))
		#expect(circle.count == Streamline.maximumSteps + 1)
		for point in circle {
			#expect(abs((point.x * point.x + point.y * point.y).squareRoot() - 1) < 1e-3)
			#expect(point.z == 0.5)
		}
		// Counterclockwise: the first step goes toward +y.
		#expect(circle[1].y > 0)
	}

	/// Where the field is 0 it stops; the field interpolates between grid points with uneven scales.
	@Test func stopsAndInterpolates() throws {
		let still = try Streamline(array([3, 3, 3]) { _ in Point(0, 0, 0) })
		#expect(try still.points(from: Point(1, 1, 1), resolution: 1, backward: false) == [1, 1, 1])
		let uneven = try Streamline(array([3, 2, 2], scales: [[0, 1, 4], [0, 1], [0, 1]]) { _ in Point(0, 0, 1) })
		let up = points(try uneven.points(from: Point(2.5, 0.5, 0), resolution: 1, backward: false))
		#expect(up.first == Point(2.5, 0.5, 0) && up.last == Point(2.5, 0.5, 1))
		#expect(throws: OSAXError.self) { try Streamline(array([3, 1, 1], scales: [[0, 2, 1], [0], [0]]) { _ in Point(1, 0, 0) }) }
	}
}
