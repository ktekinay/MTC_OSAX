import AppleEventCore
import Foundation
import Numerics

/// Satimage's "Arrays" suite, but for its hidden commands and the obsolete `extractitem` (see PLAN-Arrays.md).
/// Behavior recorded from SatimageOSAX in `Fixtures/Arrays`; where Satimage was broken, MTC_OSAX follows the
/// dictionary (`Fixtures/ArraysFixes`).
public enum Arrays {
	@MainActor
	public static func commands() -> [CommandDefinition] {
		let random = RandomSource()
		return placeholders + [
			CommandDefinition("createarray", code: "SATICRAR") { request in
				let count = try size(request)
				let (low, high) = try range(request) ?? (0, Double(count - 1))
				let step = count > 1 ? (high - low) / Double(count - 1) : 0
				return try ArrayOfReal.descriptor(count: count) { buffer in
					for index in 0 ..< count {
						// A range wider than a real can hold (-1.0E+308 to 1.0E+308) made NaN and infinities.
						buffer[index] = step.isFinite ? low + Double(index) * step : interpolate(low, high, Double(index) / Double(count - 1))
					}
				}
			},
			CommandDefinition("randomarray", code: "SATICRRA") { request in
				let count = try size(request)
				let (low, high) = try range(request) ?? (0, 1)
				let seed = try request.descriptor(for: "seed").map { try self.seed(Numbers.number($0)) }
				let isFinite = (high - low).isFinite
				return try ArrayOfReal.descriptor(count: count) { buffer in
					random.withGenerator(seed: seed) { generator in
						for index in 0 ..< count {
							let unit = generator.nextUnit()
							buffer[index] = isFinite ? low + (high - low) * unit : interpolate(low, high, unit)
						}
					}
				}
			},
		]
	}

	/// Commands not written yet: error -1708 (the event isn't handled), as before they were in the dictionary.
	@MainActor
	static let placeholders: [CommandDefinition] = [
		("creatematrix", "SATICRMT"), ("replacemissingvalue", "SATIFILL"), ("removemissingvalue", "SATIRmMv"),
		("extractarray", "SATIExLF"), ("changearray", "SATISeLF"), ("insertarray", "SATIInLF"),
		("resamplematrix", "SATIReMa"), ("reversearray", "SATILiRe"), ("multlist", "SATILST*"), ("divlist", "SATILST/"),
		("addlist", "SATILST+"), ("sublist", "SATILST-"), ("runningsum", "SATIRSum"), ("statlist", "SATIStat"),
		("histogram", "SATIHisT"), ("evalformula", "SATILSOP"), ("maskarray", "SATIMASK"), ("filter", "SATIBLUR"),
		("evalpolynomial", "SATIEvPo"), ("roots of", "SATIRoot"), ("composepolynomial", "SATICoPo"),
		("pade approximant", "SATIPade"), ("fitpolynomial", "SATIFiPo"), ("fitrational", "SATIRatF"),
		("read binary", "SATIRdBF"), ("write binary", "SATIWrBF"),
	].map { name, code in CommandDefinition(name, code: code) { _ in throw OSAXError.eventNotHandled } }

	/// The point `fraction` of the way from `low` to `high`, for a range wider than a real can hold (where
	/// `high - low` is infinite).
	static func interpolate(_ low: Double, _ high: Double, _ fraction: Double) -> Double {
		low * (1 - fraction) + high * fraction
	}

	/// The size: a positive number (or a list starting with one), rounded half to even as SatimageOSAX did
	/// (2.5 makes 2 items, 2.7 makes 3), up to `maximumSize`; error -50 otherwise.
	static func size(_ request: AppleEventRequest) throws -> Int {
		let value = try firstNumber(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor)
		let rounded = value.rounded(.toNearestOrEven)
		guard rounded >= 1 else {
			throw OSAXError.parameterError
		}
		guard rounded <= Double(maximumSize) else {
			throw OSAXError(-50, "An array can have at most 100,000,000 items.")
		}
		return Int(rounded)
	}

	/// 800 MB of reals, and as much again for the reply (two billion made 32 GB).
	static let maximumSize = 100_000_000

	/// The seed rounded half to even, reduced to its low 32 bits however large it is (a double beyond 2^53 is a
	/// whole number, and `fmod` is exact); error -50 for infinity or NaN.
	static func seed(_ value: Double) throws -> Int64 {
		guard value.isFinite else {
			throw OSAXError.parameterError
		}
		return Int64(fmod(value.rounded(.toNearestOrEven), 4_294_967_296))
	}

	/// `range {min, max}`: the first two numbers; one number (or a list of one) is both.
	static func range(_ request: AppleEventRequest) throws -> (Double, Double)? {
		guard let descriptor = request.descriptor(for: "rang") else {
			return nil
		}
		let numbers: [Double] = switch try Numbers(descriptor) {
		case let .number(value): [value]
		case let .array(values): values
		case let .list(items): try items.map {
				guard case let .number(value) = $0 else { throw OSAXError.coercionFailed }
				return value
			}
		}
		guard let low = numbers.first else {
			throw OSAXError.parameterError
		}
		return (low, numbers.count > 1 ? numbers[1] : low)
	}

	private static func firstNumber(_ descriptor: NSAppleEventDescriptor) throws -> Double {
		// A loop, not recursion: nested however deep, it can't run out of stack.
		var current = descriptor
		while current.descriptorType == typeAEList, current.numberOfItems > 0, let first = current.atIndex(1) {
			current = first
		}
		return try Numbers.number(current)
	}
}

/// The random numbers for `randomarray`: a Mersenne Twister (MT19937), as SatimageOSAX used, so a `seed` gives the
/// same numbers as it did. Without a seed, one generator seeded from the system continues from call to call.
final class RandomSource: @unchecked Sendable {
	private let lock = NSLock()
	private var shared = MersenneTwister(seed: UInt32.random(in: .min ... .max))

	func withGenerator<T>(seed: Int64?, _ body: (inout MersenneTwister) -> T) -> T {
		if let seed {
			var generator = MersenneTwister(seed: UInt32(truncatingIfNeeded: seed))
			return body(&generator)
		}
		lock.lock()
		defer { lock.unlock() }
		return body(&shared)
	}
}

/// MT19937, as published by Matsumoto and Nishimura (`init_genrand`, `genrand_int32`).
struct MersenneTwister {
	private var state = [UInt32](repeating: 0, count: 624)
	private var index = 624

	init(seed: UInt32) {
		state[0] = seed
		for i in 1 ..< 624 {
			state[i] = 1_812_433_253 &* (state[i - 1] ^ (state[i - 1] >> 30)) &+ UInt32(i)
		}
	}

	mutating func next() -> UInt32 {
		if index >= 624 {
			for k in 0 ..< 624 {
				let y = (state[k] & 0x8000_0000) | (state[(k + 1) % 624] & 0x7FFF_FFFF)
				state[k] = state[(k + 397) % 624] ^ (y >> 1) ^ (y & 1 == 0 ? 0 : 0x9908_B0DF)
			}
			index = 0
		}
		var y = state[index]
		index += 1
		y ^= y >> 11
		y ^= (y << 7) & 0x9D2C_5680
		y ^= (y << 15) & 0xEFC6_0000
		y ^= y >> 18
		return y
	}

	/// A number in [0, 1): the next 32 bits divided by 2³², as SatimageOSAX made them.
	mutating func nextUnit() -> Double {
		Double(next()) / 4_294_967_296
	}
}
