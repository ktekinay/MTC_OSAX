import AppleEventCore
import Foundation
import Numerics
import PropertyLists

/// Satimage's "3D array handling" suite (see Implemented/PLAN-3DArrays.md): 3D arrays of numbers, or vector fields,
/// kept open in the app's document store between commands and referred to by a reference or by name. Behavior recorded
/// from SatimageOSAX in `Fixtures/Arrays3D`; where Satimage was broken (`isosurface`, `streamline`), MTC_OSAX follows
/// the dictionary (`Fixtures/Arrays3DFixes`).
public enum Arrays3D {
	/// `Array3DRef`: a 4-byte little-endian number.
	static let referenceType = FourCharCode(fourCharString: "VI3D")
	/// -1728 (errAENoSuchObject): a closed array, or a name no open array has.
	static let noSuchArray = OSAXError(-1728)
	/// As for the Arrays commands: 800 MB of reals.
	static let maximumSize = 100_000_000
	static let tooLarge = OSAXError(-50, "A 3D array, or a result, can have at most 100,000,000 numbers.")

	@MainActor
	public static func commands(store: DocumentStore) -> [CommandDefinition] {
		let arrays = OpenArrays(store: store)
		return [
			CommandDefinition("open3D", code: "VI3Dodoc") { try arrays.open($0) },
			CommandDefinition("close3D", code: "VI3Dclos") { request in
				store.close(try arrays.array(request))
				return nil
			},
			CommandDefinition("info3D", code: "VI3Dinfo") { try info(arrays.array($0)) },
			CommandDefinition("contents3D", code: "VI3Dgetd") { request in
				let array = try arrays.array(request)
				let fields = try array.fields.map { try ArrayOfReal($0).descriptor() }
				return array.isVectorField ? fields.appleEventDescriptor : fields[0]
			},
			CommandDefinition("list3D", code: "VI3Dlstn") { request in
				// `as string` (or `as text`) for their names, newest first, as recorded; their references otherwise.
				let open = arrays.open.reversed()
				if let type = request.descriptor(for: "as  ")?.typeCodeValue, textTypes.contains(type) {
					return open.map { NSAppleEventDescriptor(string: $0.name) }.appleEventDescriptor
				}
				return open.map(reference).appleEventDescriptor
			},
			CommandDefinition("rename3D", code: "VI3Drena") { request in
				let array = try arrays.array(request)
				array.name = try request.requiredParameter("into", as: String.self)
				return nil
			},
			CommandDefinition("extract3D", code: "VI3Dextr", handler: { try extract(arrays.array($0), $0) }),
			CommandDefinition("isosurface", code: "VI3Dsurf") { request in
				let array = try arrays.array(request)
				guard let at = request.descriptor(for: "isov") else {
					throw OSAXError.missingParameter
				}
				let value = try Numbers.number(at)
				let field = try array.field(fieldIndex(request))
				// A value outside the field's numbers is error 7, as recorded.
				guard let range = Array3D.range(field), value >= range.minimum, value <= range.maximum else {
					throw OSAXError(7)
				}
				return try Isosurface.descriptor(field, counts: array.counts, scales: array.scales, at: value)
			},
			CommandDefinition("streamline", code: "VI3Dinte") { request in
				let array = try arrays.array(request)
				guard array.isVectorField else {
					throw OSAXError(-1)
				}
				guard let start = request.descriptor(for: "Strt") else {
					throw OSAXError.missingParameter
				}
				let point = try triple(start)
				let resolution = try request.descriptor(for: "Step").map(Numbers.number) ?? 1
				guard resolution.isFinite, resolution > 0 else {
					throw OSAXError(-50, "The resolution must be more than 0.")
				}
				let direction = try request.descriptor(for: "Idir").map(integer) ?? 1
				guard direction == 1 || direction == -1 else {
					throw OSAXError(-50, "The direction must be 1 or -1.")
				}
				return try ArrayOfReal(Streamline(array).points(from: SIMD3(point[0], point[1], point[2]), resolution: resolution, backward: direction < 0)).descriptor()
			},
		]
	}

	/// The open 3D arrays, and the counter for their references.
	@MainActor
	final class OpenArrays {
		let store: DocumentStore
		private var nextID: UInt32 = 1

		init(store: DocumentStore) {
			self.store = store
		}

		/// Oldest first.
		var open: [Array3D] {
			store.allDocuments.compactMap { $0 as? Array3D }
		}

		/// The array a command's direct parameter names: a reference or a name (the newest array with it, as
		/// recorded). -1728 for a closed one or a name no open array has; -1700 for anything else.
		func array(_ request: AppleEventRequest) throws -> Array3D {
			let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
			if descriptor.descriptorType == referenceType {
				let data = descriptor.data
				guard data.count == 4 else {
					throw noSuchArray
				}
				let id = data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
				guard let array = open.first(where: { $0.id == id }) else {
					throw noSuchArray
				}
				return array
			}
			guard descriptor.isText else {
				throw OSAXError.coercionFailed
			}
			let name = try String(appleEventDescriptor: descriptor)
			guard let array = open.last(where: { $0.name == name }) else {
				throw noSuchArray
			}
			return array
		}

		/// `open3D`: the name (default "3Darray" and the reference's number in four digits), `dimensions` (three:
		/// each a count, or its scale's numbers) and `field` (an array or a list of numbers, or a list of three for
		/// a vector field). As recorded: dimensions that aren't three are error 3, a count below 1 error 10, other
		/// than one field or three -1, a field of the wrong size error 2.
		func open(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
			let name = try request.directParameter(as: String.self)
			guard let dimensions = request.descriptor(for: "dims"), let field = request.descriptor(for: "scfl") else {
				throw OSAXError.missingParameter
			}
			guard let axes = RawList(dimensions), axes.count == 3 else {
				throw OSAXError(3)
			}
			// Each axis's scale as given, or its count (its scale made only once the size is known to be allowed).
			let given: [Either] = try (0 ..< 3).map { index in
				let axis = axes.descriptor(index)
				if isSeveral(axis.descriptorType) {
					let scale = try numbers(axis)
					guard !scale.isEmpty else {
						throw OSAXError(10)
					}
					return .scale(scale)
				}
				// Cut toward zero, as recorded (2.5 is 2).
				let count = try integer(axis)
				guard count >= 1 else {
					throw OSAXError(10)
				}
				return .count(count)
			}
			let counts = given.map(\.count)
			let (size, overflow) = counts[0].multipliedReportingOverflow(by: counts[1])
			let (total, overflow2) = size.multipliedReportingOverflow(by: counts[2])
			guard !overflow, !overflow2, total <= maximumSize else {
				throw tooLarge
			}
			let fields: [[Double]]
			if let list = RawList(field), list.count > 0, (0 ..< list.count).allSatisfy({ isSeveral(list.info($0).type) }) {
				guard list.count == 1 || list.count == 3 else {
					throw OSAXError(-1)
				}
				fields = try (0 ..< list.count).map { try numbers(list.descriptor($0)) }
			} else {
				fields = [try numbers(field)]
			}
			guard fields.count * total <= maximumSize else {
				throw tooLarge
			}
			guard fields.allSatisfy({ $0.count == total }) else {
				throw OSAXError(2)
			}
			let id = nextID
			nextID &+= 1
			let array = store.add(pool: nil) { number, _ in
				Array3D(number: number, id: id, name: name ?? String(format: "3Darray%04u", id), counts: counts, scales: given.map(\.scale), fields: fields)
			}
			return reference(array)
		}

		private enum Either {
			case scale([Double])
			case count(Int)

			var count: Int {
				switch self {
				case let .scale(scale): scale.count
				case let .count(count): count
				}
			}

			/// 0, 1, 2, … for a count.
			var scale: [Double] {
				switch self {
				case let .scale(scale): scale
				case let .count(count): (0 ..< count).map(Double.init)
				}
			}
		}
	}

	static func reference(_ array: Array3D) -> NSAppleEventDescriptor {
		withUnsafeBytes(of: array.id.littleEndian) { NSAppleEventDescriptor(descriptorType: referenceType, bytes: $0.baseAddress, length: 4)! }
	}

	/// `info3D`: `{name, dimensions, scale, number of field, minimum, maximum}`, the minimum and maximum of each field
	/// (`missing value` for fields it doesn't have, or for one of only missing values), leaving out missing values.
	static func info(_ array: Array3D) throws -> NSAppleEventDescriptor {
		let ranges = array.fields.map(Array3D.range)
		func each(_ value: ((minimum: Double, maximum: Double)) -> Double) -> NSAppleEventDescriptor {
			(0 ..< 3).map { index in
				index < ranges.count ? ranges[index].map { NSAppleEventDescriptor(double: value($0)) } ?? .missingValue : .missingValue
			}.appleEventDescriptor
		}
		return RecordFields([
			(.code("pnam"), NSAppleEventDescriptor(string: array.name)),
			(.code("dims"), array.counts.map { NSAppleEventDescriptor(int32: Int32($0)) }.appleEventDescriptor),
			(.code("Tsca"), try array.scales.map { try ArrayOfReal($0).descriptor() }.appleEventDescriptor),
			(.code("NFie"), NSAppleEventDescriptor(int32: Int32(array.fields.count))),
			(.code("MIN "), each(\.minimum)),
			(.code("MAX "), each(\.maximum)),
		]).appleEventDescriptor
	}

	/// `extract3D`: the block from `start` (1-based; negative counts from the end, as for `extractarray`), `length` long
	/// on each axis, x varying fastest. A block outside the array is -1719, as recorded.
	static func extract(_ array: Array3D, _ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		guard let startDescriptor = request.descriptor(for: "star"), let lengthDescriptor = request.descriptor(for: "leng") else {
			throw OSAXError.missingParameter
		}
		let (start, length) = (try triple(startDescriptor).map(whole), try triple(lengthDescriptor).map(whole))
		var lower: [Int] = []
		for axis in 0 ..< 3 {
			let count = array.counts[axis]
			let first = start[axis] < 0 ? count + start[axis] + 1 : start[axis]
			guard first >= 1, length[axis] >= 1, first - 1 + length[axis] <= count else {
				throw OSAXError(-1719)
			}
			lower.append(first - 1)
		}
		let field = try array.field(fieldIndex(request))
		let (nx, ny) = (array.counts[0], array.counts[1])
		return try ArrayOfReal.descriptor(count: length[0] * length[1] * length[2]) { buffer in
			var index = 0
			for z in lower[2] ..< lower[2] + length[2] {
				for y in lower[1] ..< lower[1] + length[1] {
					for x in lower[0] ..< lower[0] + length[0] {
						buffer[index] = field[x + nx * y + nx * ny * z]
						index += 1
					}
				}
			}
		}
	}

	// MARK: Parameters

	// Not the Arrays suite's `Values`, which these resemble: there a list of lists is flattened into one array (here
	// it's a vector field's components), a number that isn't one is -50 (here Numbers' error), and a whole number is
	// rounded to even (here cut toward zero).

	/// The text types `list3D … as` takes for names: `string` and `text`, as AppleScript sends them.
	static let textTypes = Set(["TEXT", "ctxt", "utxt", "utf8", "ut16", "itxt"].map { FourCharCode(fourCharString: $0) })

	/// A list or an array (of any kind), as opposed to a number.
	static func isSeveral(_ type: DescType) -> Bool {
		type == typeAEList || type == ArrayOfReal.descriptorType
	}

	/// The numbers in an array or a list (`missing value` is NaN), or one number; -1700 for anything else.
	static func numbers(_ descriptor: NSAppleEventDescriptor) throws -> [Double] {
		if let values = ArrayOfReal.values(of: descriptor) {
			return values
		}
		guard let list = RawList(descriptor) else {
			return [try number(descriptor)]
		}
		var result: [Double] = []
		result.reserveCapacity(list.count)
		try list.forEachItem { item in
			result.append(try item.number ?? (item.isMissingValue ? .nan : number(list.descriptor(item.index))))
		}
		return result
	}

	static func number(_ descriptor: NSAppleEventDescriptor) throws -> Double {
		descriptor.isMissingValue ? .nan : try Numbers.number(descriptor)
	}

	/// A whole number, cut toward zero; -50 for one beyond 32 bits, infinite or NaN.
	static func integer(_ descriptor: NSAppleEventDescriptor) throws -> Int {
		try whole(Numbers.number(descriptor))
	}

	static func whole(_ value: Double) throws -> Int {
		let value = value.rounded(.towardZero)
		guard value.isFinite, value.magnitude <= Double(Int32.max) else {
			throw OSAXError.parameterError
		}
		return Int(value)
	}

	/// Three numbers (`start`, `length`, `starting at`); -1721 (the wrong number of them) otherwise, as recorded.
	static func triple(_ descriptor: NSAppleEventDescriptor) throws -> [Double] {
		guard isSeveral(descriptor.descriptorType) else {
			throw OSAXError(-1721)
		}
		let values = try numbers(descriptor)
		guard values.count == 3 else {
			throw OSAXError(-1721)
		}
		return values
	}

	static func fieldIndex(_ request: AppleEventRequest) throws -> Int? {
		try request.descriptor(for: "INDX").map(integer)
	}
}
