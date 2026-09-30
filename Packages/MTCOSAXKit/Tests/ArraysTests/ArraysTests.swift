import AppleEventCore
import Foundation
import Testing
@testable import Arrays

@MainActor
private func send(_ code: String, _ parameters: [String: any AppleEventEncodable]) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(Arrays.commands())
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

private func values(_ reply: AppleEventReply) -> [Double]? {
	reply.result.flatMap(ArrayOfReal.values(of:))
}

@MainActor
struct CreateArrayTests {
	@Test func ranges() {
		#expect(values(send("SATICRAR", ["----": 3])) == [0, 1, 2])
		#expect(values(send("SATICRAR", ["----": 5, "rang": [2, 3]])) == [2, 2.25, 2.5, 2.75, 3])
		#expect(values(send("SATICRAR", ["----": 1, "rang": [2, 3]])) == [2])
		#expect(values(send("SATICRAR", ["----": 3, "rang": [3, 1]])) == [3, 2, 1])
		#expect(values(send("SATICRAR", ["----": 3, "rang": [1]])) == [1, 1, 1])
		#expect(values(send("SATICRAR", ["----": 3, "rang": 1])) == [1, 1, 1])
		// A range wider than a real can hold made {NaN, inf, inf}.
		#expect(values(send("SATICRAR", ["----": 3, "rang": [-1e308, 1e308]])) == [-1e308, 0, 1e308])
		let random = values(send("SATICRRA", ["----": 1000, "rang": [-1e308, 1e308]])) ?? []
		#expect(random.count == 1000 && random.allSatisfy { $0.isFinite && $0 >= -1e308 && $0 <= 1e308 })
	}

	@Test func sizes() {
		#expect(values(send("SATICRAR", ["----": 2.7]))?.count == 3)
		#expect(values(send("SATICRAR", ["----": 2.5]))?.count == 2)
		#expect(values(send("SATICRAR", ["----": "3"]))?.count == 3)
		#expect(values(send("SATICRAR", ["----": [3]]))?.count == 3)
		#expect(send("SATICRAR", ["----": 0]).error == .parameterError)
		#expect(send("SATICRAR", ["----": -2]).error == .parameterError)
		#expect(send("SATICRAR", [:]).error == .missingParameter)
		// Two billion items used to be allowed (32 GB).
		#expect(send("SATICRAR", ["----": 100_000_001]).error?.number == -50)
		#expect(send("SATICRRA", ["----": 2_000_000_000]).error?.number == -50)
	}
}

@MainActor
struct RandomArrayTests {
	@Test func seedsMatchSatimage() {
		// Recorded from SatimageOSAX: randomarray 3 seed 12345.
		#expect(values(send("SATICRRA", ["----": 3, "seed": 12345])) == [0.9296160866506398, 0.8901547130662948, 0.31637556036002934])
		#expect(values(send("SATICRRA", ["----": 4, "rang": [10, 20], "seed": 1]))?.first == 14.170219984371215)
	}

	@Test func unseededStaysInRange() throws {
		let first = try #require(values(send("SATICRRA", ["----": 1000, "rang": [100, 101]])))
		#expect(first.count == 1000)
		#expect(first.allSatisfy { $0 >= 100 && $0 < 101 })
		#expect(first != values(send("SATICRRA", ["----": 1000, "rang": [100, 101]])))
	}

	@Test func largeSeedsRepeat() {
		let a = values(send("SATICRRA", ["----": 3, "seed": 4_000_000_000.0]))
		#expect(a != nil && a == values(send("SATICRRA", ["----": 3, "seed": 4_000_000_000.0])))
	}

	/// Seeds beyond 64 bits used to trap; they're reduced to their low 32 bits like any other.
	@Test func hugeSeeds() throws {
		#expect(try Arrays.seed(1e30) == Int64(fmod(1e30, 4_294_967_296)))
		#expect(try Arrays.seed(4_294_967_297) == 1)
		#expect(try Arrays.seed(-1) == -1)
		#expect(values(send("SATICRRA", ["----": 3, "seed": 1e30]))?.count == 3)
		#expect(send("SATICRRA", ["----": 3, "seed": Double.nan]).error == .parameterError)
		#expect(send("SATICRRA", ["----": 3, "seed": Double.infinity]).error == .parameterError)
	}

	@Test func mersenneTwisterReferenceValues() {
		// The first outputs of MT19937 seeded with 5489, from its reference implementation.
		var generator = MersenneTwister(seed: 5489)
		#expect([generator.next(), generator.next(), generator.next()] == [3_499_211_612, 581_869_302, 3_890_346_734])
	}
}
