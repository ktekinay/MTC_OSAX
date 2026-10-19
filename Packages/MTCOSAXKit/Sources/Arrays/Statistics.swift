import AppleEventCore
import Foundation

/// `runningsum`, `statlist`, `histogram`, `resamplematrix` and `filter`, as recorded from SatimageOSAX. Statistics
/// leave out missing values (NaN); the variance divides by the count (not one less), the kurtosis isn't less 3,
/// and the median is the upper one of an even count.
enum Statistics {
	@MainActor
	static func commands() -> [CommandDefinition] {
		[
			CommandDefinition("runningsum", code: "SATIRSum") { request in
				let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
				// A matrix's numbers are summed column by column, as recorded (the dictionary doesn't say).
				let matrix = try Matrix(descriptor)
				let values = try matrix?.values ?? Values.numbers(descriptor)
				let (columns, rows) = matrix.map { ($0.columns, $0.rows) } ?? (1, values.count)
				// A loop, not `map` with a closure adding to a captured sum, which took 30 times as long.
				return try ArrayOfReal.descriptor(count: values.count) { buffer in
					var sum = 0.0, index = 0
					for column in 0 ..< columns {
						for row in 0 ..< rows {
							sum += values[row * columns + column]
							buffer[index] = sum
							index += 1
						}
					}
				}
			},
			CommandDefinition("statlist", code: "SATIStat", handler: statList),
			CommandDefinition("histogram", code: "SATIHisT", handler: histogram),
			CommandDefinition("resamplematrix", code: "SATIReMa", handler: resample),
			CommandDefinition("filter", code: "SATIBLUR", handler: filter),
		]
	}

	// MARK: statlist

	/// `{maximum, maximum index, minimum, minimum index, sum, mean, variance, stdev, missing value}` (the count of
	/// missing values, which the dictionary doesn't list), and `with kurtosis` skewness, kurtosis and median. Indexes
	/// count every item; the first of equal ones. No numbers is -50; only missing values, Satimage's error 2.
	static func statList(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let values = try Values.numbers(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		guard !values.isEmpty else {
			throw OSAXError.parameterError
		}
		var maximum = -Double.infinity, minimum = Double.infinity, maximumIndex = 0, minimumIndex = 0
		var sum = 0.0, count = 0
		for (index, value) in values.enumerated() where !value.isNaN {
			if maximumIndex == 0 || value > maximum {
				maximum = value
				maximumIndex = index + 1
			}
			if minimumIndex == 0 || value < minimum {
				minimum = value
				minimumIndex = index + 1
			}
			sum += value
			count += 1
		}
		guard count > 0 else {
			throw OSAXError(2)
		}
		let moments = Moments(values, sum: sum, count: count)
		var fields: [(RecordFields.Key, NSAppleEventDescriptor)] = [
			(.code("MAX "), NSAppleEventDescriptor(double: maximum)),
			(.code("MAXi"), NSAppleEventDescriptor(int32: Int32(maximumIndex))),
			(.code("MIN "), NSAppleEventDescriptor(double: minimum)),
			(.code("MINi"), NSAppleEventDescriptor(int32: Int32(minimumIndex))),
			(.code("SUM "), NSAppleEventDescriptor(double: sum)),
			(.code("MEAN"), NSAppleEventDescriptor(double: moments.mean)),
			(.code("Sigm"), NSAppleEventDescriptor(double: moments.variance)),
			(.code("StDe"), NSAppleEventDescriptor(double: moments.variance.squareRoot())),
			(.code("msng"), NSAppleEventDescriptor(int32: Int32(values.count - count))),
		]
		if try request.parameter("Krts", default: false) {
			let deviation = moments.variance.squareRoot()
			fields += [
				(.code("Skew"), NSAppleEventDescriptor(double: moments.third / (deviation * deviation * deviation))),
				(.code("Krts"), NSAppleEventDescriptor(double: moments.fourth / (moments.variance * moments.variance))),
				(.code("MEDI"), NSAppleEventDescriptor(double: upperMedian(values))),
			]
		}
		return RecordFields(fields).appleEventDescriptor
	}

	/// The mean and central moments of the numbers that aren't NaN (each moment divided by their count).
	struct Moments {
		var mean: Double
		var variance = 0.0
		var third = 0.0
		var fourth = 0.0

		init(_ values: [Double], sum: Double, count: Int) {
			mean = sum / Double(count)
			for value in values where !value.isNaN {
				let deviation = value - mean
				let square = deviation * deviation
				variance += square
				third += square * deviation
				fourth += square * square
			}
			variance /= Double(count)
			third /= Double(count)
			fourth /= Double(count)
		}
	}

	/// The item at half the count (of every item, missing ones too) once they're sorted, NaN last: the upper median
	/// of an even count. With missing values it can be NaN, as recorded (`{1, missing value, 3, missing value}`).
	/// Found by selection (Hoare's), not by sorting them all, which took six times as long.
	static func upperMedian(_ values: [Double]) -> Double {
		var numbers = values.filter { !$0.isNaN }
		let k = values.count / 2
		guard k < numbers.count else {
			return .nan
		}
		var low = 0, high = numbers.count - 1
		while low < high {
			let pivot = numbers[(low + high) / 2]
			var i = low, j = high
			while i <= j {
				while numbers[i] < pivot { i += 1 }
				while numbers[j] > pivot { j -= 1 }
				if i <= j {
					numbers.swapAt(i, j)
					i += 1
					j -= 1
				}
			}
			// The k-th is in the part below the pivot, the part above it, or between them (equal to the pivot).
			if k <= j {
				high = j
			} else if k >= i {
				low = i
			} else {
				break
			}
		}
		return numbers[k]
	}

	// MARK: histogram

	/// `{values, counts}`: each distinct number and how many times it comes, or with `samples` the centers of that
	/// many equal intervals from `minimum` to `maximum` (by default the numbers' own) and how many numbers fall in
	/// each (the maximum itself in the last). Missing values are left out; none left, or no samples, is error -1.
	/// SatimageOSAX also counted numbers up to an interval below `minimum` in the first interval; MTC_OSAX counts
	/// only numbers in the range.
	static func histogram(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let values = try Values.numbers(try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor).filter { !$0.isNaN }
		guard !values.isEmpty else {
			throw OSAXError(-1)
		}
		guard let samplesDescriptor = request.descriptor(for: "samp") else {
			var counts: [Double: Int] = [:]
			for value in values {
				counts[value, default: 0] += 1
			}
			let distinct = counts.keys.sorted()
			return [try Values.array(distinct), try Values.array(distinct.map { Double(counts[$0]!) })].appleEventDescriptor
		}
		let samples = try Values.integer(samplesDescriptor)
		guard samples >= 1, samples <= Arrays.maximumSize else {
			throw OSAXError(-1)
		}
		let low = try request.descriptor(for: "MIN ").map(Values.number) ?? values.min()!
		let high = try request.descriptor(for: "MAX ").map(Values.number) ?? values.max()!
		let width = (high - low) / Double(samples)
		var counts = [Double](repeating: 0, count: samples)
		for value in values {
			if value == high {
				counts[samples - 1] += 1
			} else if value >= low, value < high {
				counts[interval(of: value, low: low, high: high, width: width, samples: samples)] += 1
			}
		}
		let centers = (0 ..< samples).map { index in
			let fraction = (Double(index) + 0.5) / Double(samples)
			return width.isFinite ? low + (Double(index) + 0.5) * width : Arrays.interpolate(low, high, fraction)
		}
		return [try Values.array(centers), try Values.array(counts)].appleEventDescriptor
	}

	/// The interval a number from `low` up to (not including) `high` falls in. A range wider than a real can hold
	/// (an infinite width) put every number in the first interval or gave NaN, and one so narrow its width is 0 gave
	/// 0/0: converting NaN to an integer crashed. Those are worked out from halves of the numbers, and if that fails
	/// too (a range below the smallest real), the number is in the first interval.
	static func interval(of value: Double, low: Double, high: Double, width: Double, samples: Int) -> Int {
		var position = width.isFinite && width > 0 ? (value - low) / width : .nan
		if !position.isFinite {
			position = (value / 2 - low / 2) / (high / 2 - low / 2) * Double(samples)
		}
		return position.isFinite ? min(samples - 1, max(0, Int(position))) : 0
	}

	// MARK: resamplematrix

	/// The statistics `wanted` resamplematrix computes on each block.
	enum Statistic: String {
		case mean, minimum, maximum, stdev, missingValue = "missing value", sum, median, dispersion

		/// Over the block's numbers that aren't NaN, but "missing value", which counts the NaNs.
		func callAsFunction(_ block: [Double]) -> Double {
			let present = block.filter { !$0.isNaN }
			switch self {
			case .missingValue: return Double(block.count - present.count)
			case .sum: return present.reduce(0, +)
			case .mean: return present.reduce(0, +) / Double(present.count)
			case .minimum: return present.min() ?? .nan
			case .maximum: return present.max() ?? .nan
			case .dispersion: return (present.max() ?? .nan) - (present.min() ?? .nan)
			case .median: return present.isEmpty ? .nan : upperMedian(present)
			case .stdev:
				guard !present.isEmpty else { return .nan }
				return Moments(present, sum: present.reduce(0, +), count: present.count).variance.squareRoot()
			}
		}
	}

	/// The matrix in blocks: `blocksize {i, j}`, i columns by j rows (the last blocks smaller if the matrix isn't a
	/// whole number of them), or lists of each block's size; each block replaced by a statistic (default the mean),
	/// or a list of matrices for a list of `wanted`. A size below 1, or `blocksize` not a list of two, is -50 (a
	/// size of 0 made SatimageOSAX return nothing).
	static func resample(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard let matrix = try Matrix(descriptor) else {
			throw OSAXError.coercionFailed
		}
		guard let blocksize = request.descriptor(for: "bloc") else {
			throw OSAXError.missingParameter
		}
		guard let sizes = RawList(blocksize), sizes.count == 2 else {
			throw OSAXError.parameterError
		}
		let columnBlocks = try blocks(sizes.descriptor(0), length: matrix.columns)
		let rowBlocks = try blocks(sizes.descriptor(1), length: matrix.rows)
		let wantedDescriptor = request.descriptor(for: "WANT")
		let names = try wantedDescriptor.map { wanted -> [String] in
			guard let list = RawList(wanted) else { return [try String(appleEventDescriptor: wanted)] }
			return try (0 ..< list.count).map { try String(appleEventDescriptor: list.descriptor($0)) }
		} ?? ["mean"]
		let statistics = try names.map { name in
			guard let statistic = Statistic(rawValue: name.lowercased()) else { throw OSAXError.parameterError }
			return statistic
		}
		let results = try statistics.map { statistic in
			var values: [Double] = []
			for rows in rowBlocks {
				for columns in columnBlocks {
					var block: [Double] = []
					for row in rows {
						block += matrix.values[row * matrix.columns + columns.lowerBound ..< row * matrix.columns + columns.upperBound]
					}
					values.append(statistic(block))
				}
			}
			return try Matrix(columns: columnBlocks.count, rows: rowBlocks.count, values: values).descriptor()
		}
		if let wantedDescriptor, wantedDescriptor.descriptorType == typeAEList {
			return results.appleEventDescriptor
		}
		return results[0]
	}

	/// The ranges of a dimension's blocks: of one size (the last one shorter), or of the sizes listed (stopping at
	/// the end of the dimension).
	private static func blocks(_ descriptor: NSAppleEventDescriptor, length: Int) throws -> [Range<Int>] {
		let sizes = try RawList(descriptor).map { list in try (0 ..< list.count).map { try Values.integer(list.descriptor($0)) } }
		var ranges: [Range<Int>] = []
		var start = 0
		if let sizes {
			for size in sizes where start < length {
				guard size >= 1 else { throw OSAXError.parameterError }
				ranges.append(start ..< min(length, start + size))
				start += size
			}
		} else {
			let size = try Values.integer(descriptor)
			guard size >= 1 else { throw OSAXError.parameterError }
			while start < length {
				ranges.append(start ..< min(length, start + size))
				start += size
			}
		}
		return ranges
	}

	// MARK: filter

	/// A 3×3 filter (nine numbers, row by row) over a matrix: each number becomes the sum of its neighbors times the
	/// filter's numbers. `reduced` (the default) leaves out the first and last rows and columns; without it, they're
	/// computed as if the matrix had zeros around it. (SatimageOSAX put some of those in the wrong places, so even
	/// the identity filter changed the matrix.) Fewer than 3 rows or columns to reduce is -50 (SatimageOSAX: -108).
	static func filter(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard let matrix = try Matrix(descriptor) else {
			throw OSAXError.coercionFailed
		}
		guard let kernelDescriptor = request.descriptor(for: "with") else {
			throw OSAXError.missingParameter
		}
		let kernel = try Values.numbers(kernelDescriptor)
		guard kernel.count == 9 else {
			throw OSAXError.parameterError
		}
		let reduced = try request.parameter("redu", default: true)
		let (columns, rows) = (matrix.columns, matrix.rows)
		let margin = reduced ? 1 : 0
		guard columns - 2 * margin >= 1, rows - 2 * margin >= 1 else {
			throw OSAXError.parameterError
		}
		var values: [Double] = []
		values.reserveCapacity((columns - 2 * margin) * (rows - 2 * margin))
		for row in margin ..< rows - margin {
			for column in margin ..< columns - margin {
				var sum = 0.0
				for dy in -1 ... 1 {
					for dx in -1 ... 1 {
						let (y, x) = (row + dy, column + dx)
						if y >= 0, y < rows, x >= 0, x < columns {
							sum += kernel[(dy + 1) * 3 + dx + 1] * matrix.values[y * columns + x]
						}
					}
				}
				values.append(sum)
			}
		}
		return try Matrix(columns: columns - 2 * margin, rows: rows - 2 * margin, values: values).descriptor()
	}
}
