import AppleEventCore
import Foundation

/// `streamline`, from the dictionary (SatimageOSAX's returned its starting point 30,001 times, whatever the field):
/// the curve that follows a vector field's direction from a point, the field interpolated trilinearly between the
/// grid's points in the scales' coordinates. Fourth-order Runge–Kutta, in steps of `resolution` times the smallest
/// distance between two points of a scale, along the field (or against it, `backward`). It stops at the edge of the
/// box (its last point on the edge), where the field is 0 (or missing), or after `maximumSteps` steps.
struct Streamline {
	/// SatimageOSAX's 30,001 points.
	static let maximumSteps = 30_000

	/// One axis: its scale, in order (rising or falling).
	struct Axis {
		let scale: [Double]
		let rising: Bool
		let lower: Double
		let upper: Double

		/// -50 for a scale out of order (no cell would be the one a point is in), or one that isn't finite or whose
		/// span isn't (a cell's spacing that overflows made a fraction along it NaN, so that a weight of 0 wasn't).
		init(_ scale: [Double]) throws {
			let rising = scale.count < 2 || scale[1] > scale[0]
			for index in scale.indices.dropFirst() where !(rising ? scale[index] > scale[index - 1] : scale[index] < scale[index - 1]) {
				throw OSAXError(-50, "A streamline needs each axis's scale in order, rising or falling, without repeats.")
			}
			self.scale = scale
			self.rising = rising
			(lower, upper) = rising ? (scale.first!, scale.last!) : (scale.last!, scale.first!)
			guard lower.isFinite, upper.isFinite, (upper - lower).isFinite else {
				throw OSAXError(-50, "A streamline needs each axis's scale finite, from its first number to its last.")
			}
		}

		/// The cell along this axis a coordinate is in, and how far along it (0 to 1); nil outside the scale.
		func locate(_ coordinate: Double) -> (index: Int, fraction: Double)? {
			guard coordinate >= lower, coordinate <= upper else {
				return nil
			}
			guard scale.count > 1 else {
				return (0, 0)
			}
			// The last index whose point comes before the coordinate (in the scale's order), at most the last cell.
			var low = 0, high = scale.count - 2
			while low < high {
				let middle = (low + high + 1) / 2
				if rising ? scale[middle] <= coordinate : scale[middle] >= coordinate {
					low = middle
				} else {
					high = middle - 1
				}
			}
			return (low, (coordinate - scale[low]) / (scale[low + 1] - scale[low]))
		}

		/// The smallest distance between two of its points; nil for an axis of one point.
		var spacing: Double? {
			scale.count < 2 ? nil : zip(scale, scale.dropFirst()).map { abs($1 - $0) }.min()
		}

		func clamp(_ coordinate: Double) -> Double {
			min(max(coordinate, lower), upper)
		}
	}

	let axes: [Axis]
	let counts: [Int]
	let fields: [[Double]]

	init(_ array: Array3D) throws {
		axes = try array.scales.map(Axis.init)
		counts = array.counts
		fields = array.fields
	}

	/// The field at a point, interpolated; nil outside the box.
	func velocity(at point: SIMD3<Double>) -> SIMD3<Double>? {
		guard let x = axes[0].locate(point.x), let y = axes[1].locate(point.y), let z = axes[2].locate(point.z) else {
			return nil
		}
		let (nx, ny) = (counts[0], counts[1])
		var result = SIMD3<Double>(repeating: 0)
		for corner in 0 ..< 8 {
			let (dx, dy, dz) = (corner & 1, corner >> 1 & 1, corner >> 2 & 1)
			let factors = (dx == 0 ? 1 - x.fraction : x.fraction, dy == 0 ? 1 - y.fraction : y.fraction, dz == 0 ? 1 - z.fraction : z.fraction)
			// Each factor, not their product: along an axis of one point the far corner's factor is 0, and it's past
			// the field's end (0 times NaN wasn't 0).
			guard factors.0 != 0, factors.1 != 0, factors.2 != 0 else {
				continue
			}
			let weight = factors.0 * factors.1 * factors.2
			let offset = (x.index + dx) + nx * (y.index + dy) + nx * ny * (z.index + dz)
			result += weight * SIMD3(fields[0][offset], fields[1][offset], fields[2][offset])
		}
		return result
	}

	func isInside(_ point: SIMD3<Double>) -> Bool {
		(0 ..< 3).allSatisfy { point[$0] >= axes[$0].lower && point[$0] <= axes[$0].upper }
	}

	/// The points, the start first, as x, y, z for each. Error 2000 for a start outside the box, as recorded.
	func points(from start: SIMD3<Double>, resolution: Double, backward: Bool) throws -> [Double] {
		guard velocity(at: start) != nil else {
			throw OSAXError(2000)
		}
		var points = [start.x, start.y, start.z]
		guard let spacing = axes.compactMap(\.spacing).min() else {
			return points // A single point: nowhere to go.
		}
		let step = resolution * spacing
		// A step that overflowed made every point after the start NaN.
		guard step.isFinite else {
			throw OSAXError(-50, "The resolution times the grid's spacing must be a finite number.")
		}
		/// The direction to go at a point: the field's, made 1 long (so each step goes `step`); nil outside the
		/// box, or where the field is 0 or missing.
		func direction(_ point: SIMD3<Double>) -> SIMD3<Double>? {
			guard let velocity = velocity(at: point) else {
				return nil
			}
			var (direction, speed) = (velocity, (velocity * velocity).sum().squareRoot())
			if !(speed > 0 && speed.isFinite) {
				// Divided by its largest component first where the squares overflow (a component above 1e154, which
				// stopped the streamline as if the field were missing) or are all 0; otherwise as it was, to the bit.
				let largest = max(abs(velocity.x), abs(velocity.y), abs(velocity.z))
				guard largest > 0, largest.isFinite else {
					return nil
				}
				direction = velocity / largest
				speed = (direction * direction).sum().squareRoot()
			}
			return (backward ? -direction : direction) / speed
		}
		var point = start
		for _ in 0 ..< Self.maximumSteps {
			guard let k1 = direction(point) else {
				break
			}
			var next: SIMD3<Double>
			if let k2 = direction(point + step / 2 * k1), let k3 = direction(point + step / 2 * k2), let k4 = direction(point + step * k3) {
				// The stages' mean first, so a uniform flow goes exactly one step.
				next = point + step * ((k1 + 2 * k2 + 2 * k3 + k4) / 6)
			} else {
				// A stage left the box (or found no field): a plain step toward the edge.
				next = point + step * k1
			}
			if !isInside(next) {
				// The last point on the edge, unless it's already there.
				next = clipped(from: point, to: next)
				if next != point {
					points += [next.x, next.y, next.z]
				}
				break
			}
			guard next != point else {
				break
			}
			points += [next.x, next.y, next.z]
			point = next
		}
		return points
	}

	/// Where the segment from a point inside the box to one outside it reaches the box's edge.
	func clipped(from inside: SIMD3<Double>, to outside: SIMD3<Double>) -> SIMD3<Double> {
		var fraction = 1.0
		for axis in 0 ..< 3 where outside[axis] != inside[axis] {
			let bound = outside[axis] > axes[axis].upper ? axes[axis].upper : outside[axis] < axes[axis].lower ? axes[axis].lower : nil
			if let bound {
				fraction = min(fraction, (bound - inside[axis]) / (outside[axis] - inside[axis]))
			}
		}
		let point = inside + fraction * (outside - inside)
		// Exactly on the edge, whatever the rounding.
		return SIMD3((0 ..< 3).map { axes[$0].clamp(point[$0]) })
	}
}
