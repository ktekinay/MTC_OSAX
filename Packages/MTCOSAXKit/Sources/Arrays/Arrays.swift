import AppleEventCore
import Foundation
import Numerics

/// From Satimage's "Arrays" suite, the commands that make an `array of real`: `createarray` and `randomarray`.
/// Behavior recorded from SatimageOSAX in `Fixtures/Arrays`. The rest of the suite isn't implemented yet.
public enum Arrays {
	@MainActor
	public static func commands() -> [CommandDefinition] {
		let random = RandomSource()
		return [
			CommandDefinition("createarray", code: "SATICRAR") { request in
				let count = try size(request)
				let (low, high) = try range(request) ?? (0, Double(count - 1))
				let step = count > 1 ? (high - low) / Double(count - 1) : 0
				return ArrayOfReal((0 ..< count).map { low + Double($0) * step })
			},
			CommandDefinition("randomarray", code: "SATICRRA") { request in
				let count = try size(request)
				let (low, high) = try range(request) ?? (0, 1)
				let seed = try request.descriptor(for: "seed").map { try self.seed(Numbers.number($0)) }
				return random.withGenerator(seed: seed) { generator in
					ArrayOfReal((0 ..< count).map { _ in low + (high - low) * generator.nextUnit() })
				}
			},
		]
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
		if descriptor.descriptorType == typeAEList, descriptor.numberOfItems > 0 {
			return try firstNumber(descriptor.atIndex(1)!)
		}
		return try Numbers.number(descriptor)
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
