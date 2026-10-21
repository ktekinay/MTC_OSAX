import AppleEventCore
import Foundation
import PropertyLists
import Testing
@testable import Arrays3D

@MainActor
final class Sender {
	let store = DocumentStore()
	let dispatcher = CommandDispatcher()

	init() {
		dispatcher.register(Arrays3D.commands(store: store))
		dispatcher.register(PropertyLists.commands(store: store))
	}

	func send(_ code: String, _ parameters: [String: any AppleEventEncodable]) -> AppleEventReply {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
		for (keyword, value) in parameters {
			event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
		}
		return dispatcher.dispatch(event)
	}

	/// open3D, or nil and the test fails.
	func open(_ name: String? = nil, _ dimensions: [any AppleEventEncodable], _ field: any AppleEventEncodable) -> NSAppleEventDescriptor? {
		var parameters: [String: any AppleEventEncodable] = ["dims": AppleEventList(dimensions), "scfl": field]
		if let name {
			parameters["----"] = name
		}
		let reply = send("VI3Dodoc", parameters)
		#expect(reply.error == nil, "open3D: \(String(describing: reply.error))")
		return reply.result
	}
}

func values(_ reply: AppleEventReply) -> [Double]? {
	reply.result.flatMap(ArrayOfReal.values(of:))
}

func names(_ reply: AppleEventReply) -> [String]? {
	reply.result.map { list in (0 ..< list.numberOfItems).map { list.atIndex($0 + 1)!.stringValue ?? "?" } }
}

@MainActor
struct Arrays3DCommandTests {
	@Test func everyCommandIsRegistered() {
		#expect(Arrays3D.commands(store: DocumentStore()).count == 9)
	}
}

/// Opening, naming, finding and closing arrays.
@MainActor
struct StoreTests {
	/// References count up for the life of the app; an array without a name is named after its reference's number.
	@Test func referencesAndNames() throws {
		let sender = Sender()
		let a = try #require(sender.open("a", [2, 1, 1], ArrayOfReal([1, 2])))
		#expect(a.descriptorType == Arrays3D.referenceType && a.data == Data([1, 0, 0, 0]))
		let b = try #require(sender.open(nil, [1, 1, 1], ArrayOfReal([3])))
		#expect(b.data == Data([2, 0, 0, 0]))
		#expect(names(sender.send("VI3Dlstn", ["as  ": NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "TEXT"))])) == ["3Darray0002", "a"])
		#expect(sender.send("VI3Dlstn", [:]).result?.numberOfItems == 2)
		#expect(sender.send("VI3Dclos", ["----": a]).error == nil)
		#expect(sender.send("VI3Dinfo", ["----": a]).error?.number == -1728)
		// Closed numbers aren't used again.
		let c = try #require(sender.open("c", [1, 1, 1], ArrayOfReal([4])))
		#expect(c.data == Data([3, 0, 0, 0]))
		#expect(sender.send("VI3Dclos", ["----": "3Darray0002"]).error == nil)
		#expect(sender.send("VI3Dclos", ["----": c]).error == nil)
		#expect(sender.send("VI3Dlstn", [:]).result?.numberOfItems == 0)
	}

	/// A name finds the newest array with it; renamed, the next one is found.
	@Test func repeatedNames() throws {
		let sender = Sender()
		let first = try #require(sender.open("x", [1, 1, 1], ArrayOfReal([1])))
		let second = try #require(sender.open("x", [2, 1, 1], ArrayOfReal([1, 2])))
		#expect(values(sender.send("VI3Dgetd", ["----": "x"])) == [1, 2])
		#expect(sender.send("VI3Drena", ["----": second, "into": "y"]).error == nil)
		#expect(values(sender.send("VI3Dgetd", ["----": "x"])) == [1])
		#expect(values(sender.send("VI3Dgetd", ["----": "y"])) == [1, 2])
		#expect(sender.send("VI3Dgetd", ["----": 1]).error == .coercionFailed)
		for reference in [first, second] {
			sender.send("VI3Dclos", ["----": reference])
		}
	}

	/// The app stays open while an array is, but pools don't hold them: DeletePool leaves them open.
	@Test func storeAndPools() throws {
		let sender = Sender()
		let reference = try #require(sender.open("kept", [1, 1, 1], ArrayOfReal([1])))
		#expect(sender.store.hasOpenDocuments)
		#expect(sender.send("POOLdpoo", ["----": ""]).error == nil)
		#expect(sender.send("VI3Dinfo", ["----": reference]).error == nil)
		#expect(sender.send("POOLgpoo", ["----": reference]).error == .coercionFailed)
		sender.send("VI3Dclos", ["----": reference])
		#expect(!sender.store.hasOpenDocuments)
	}

	/// Fields as lists (SatimageOSAX: -1), 8-byte reals kept as they are (SatimageOSAX: 4-byte), limits.
	@Test func fields() throws {
		let sender = Sender()
		let list = try #require(sender.open("list", [3, 1, 1], AppleEventList([0.1, 1e300, NSAppleEventDescriptor.missingValue])))
		#expect(values(sender.send("VI3Dgetd", ["----": list]))?.prefix(2) == [0.1, 1e300])
		let info = try #require(sender.send("VI3Dinfo", ["----": list]).result.flatMap(RecordFields.init))
		#expect(info[.code("MIN ")]?.atIndex(1)?.doubleValue == 0.1)
		#expect(info[.code("MAX ")]?.atIndex(1)?.doubleValue == 1e300)
		#expect(info[.code("MAX ")]?.atIndex(2)?.typeCodeValue == NSAppleEventDescriptor.missingValueCode)
		sender.send("VI3Dclos", ["----": list])
		// A first number missing (SatimageOSAX's minimum and maximum were garbage), and only missing values.
		let gaps = try #require(sender.open("gaps", [3, 1, 1], AppleEventList([NSAppleEventDescriptor.missingValue, 5, 2])))
		let gapInfo = try #require(sender.send("VI3Dinfo", ["----": gaps]).result.flatMap(RecordFields.init))
		#expect(gapInfo[.code("MIN ")]?.atIndex(1)?.doubleValue == 2 && gapInfo[.code("MAX ")]?.atIndex(1)?.doubleValue == 5)
		sender.send("VI3Dclos", ["----": gaps])
		#expect(sender.send("VI3Dodoc", ["dims": AppleEventList([10_000, 10_000, 2]), "scfl": ArrayOfReal([1])]).error?.number == -50)
		#expect(sender.send("VI3Dodoc", ["dims": AppleEventList([3, 3, 3]), "scfl": ArrayOfReal([1])]).error?.number == 2)
		#expect(sender.send("VI3Dodoc", ["dims": AppleEventList([-1, 3, 3]), "scfl": ArrayOfReal([1])]).error?.number == 10)
	}
}

/// extract3D against the offsets the dictionary gives (ix + nx·iy + nx·ny·iz).
@MainActor
struct ExtractTests {
	@Test func blocksMatchOffsets() throws {
		let sender = Sender()
		let (nx, ny, nz) = (4, 3, 5)
		let reference = try #require(sender.open("box", [nx, ny, nz], ArrayOfReal((0 ..< nx * ny * nz).map(Double.init))))
		var generator = SystemRandomNumberGenerator()
		for _ in 0 ..< 200 {
			let start = [Int.random(in: 1 ... nx, using: &generator), Int.random(in: 1 ... ny, using: &generator), Int.random(in: 1 ... nz, using: &generator)]
			let length = [Int.random(in: 1 ... nx - start[0] + 1, using: &generator), Int.random(in: 1 ... ny - start[1] + 1, using: &generator), Int.random(in: 1 ... nz - start[2] + 1, using: &generator)]
			var expected: [Double] = []
			for z in start[2] - 1 ..< start[2] - 1 + length[2] {
				for y in start[1] - 1 ..< start[1] - 1 + length[1] {
					for x in start[0] - 1 ..< start[0] - 1 + length[0] {
						expected.append(Double(x + nx * y + nx * ny * z))
					}
				}
			}
			#expect(values(sender.send("VI3Dextr", ["----": reference, "star": AppleEventList(start), "leng": AppleEventList(length)])) == expected, "\(start) \(length)")
		}
		// Negative starts count from the end.
		#expect(values(sender.send("VI3Dextr", ["----": reference, "star": AppleEventList([-1, -1, -1]), "leng": AppleEventList([1, 1, 1])])) == [Double(nx * ny * nz - 1)])
		sender.send("VI3Dclos", ["----": reference])
	}
}

/// streamline's parameters, through the dispatcher (the README lists these errors).
@MainActor
struct StreamlineParameterTests {
	@Test func errors() throws {
		let sender = Sender()
		let field = AppleEventList([ArrayOfReal(Array(repeating: 1, count: 8)), ArrayOfReal(Array(repeating: 0, count: 8)), ArrayOfReal(Array(repeating: 0, count: 8))])
		let flow = try #require(sender.open("flow", [2, 2, 2], field))
		func error(_ parameters: [String: any AppleEventEncodable]) -> Int? {
			sender.send("VI3Dinte", parameters.merging(["----": flow]) { $1 }).error?.number
		}
		#expect(error(["Strt": AppleEventList([0, 0, 0])]) == nil)
		// The start: three numbers, a list or an array; anything else is -1721.
		#expect(error(["Strt": ArrayOfReal([0, 0, 0])]) == nil)
		#expect(error(["Strt": 0]) == -1721)
		#expect(error(["Strt": AppleEventList([0, 0])]) == -1721)
		#expect(error([:]) == -1701)
		for resolution in [0, -1, Double.nan, .infinity] {
			#expect(error(["Strt": AppleEventList([0, 0, 0]), "Step": resolution]) == -50, "resolution \(resolution)")
		}
		for direction in [0, 2, -2] {
			#expect(error(["Strt": AppleEventList([0, 0, 0]), "Idir": direction]) == -50, "direction \(direction)")
		}
		#expect(error(["Strt": AppleEventList([0, 0, 0]), "Idir": -1]) == nil)
		sender.send("VI3Dclos", ["----": flow])
		// A scale out of order (or with a repeat) is -50.
		for scale in [[0.0, 2, 1], [0, 1, 1]] {
			let uneven = try #require(sender.open("uneven", [AppleEventList(scale), 2, 2], AppleEventList([ArrayOfReal(Array(repeating: 1, count: 12)), ArrayOfReal(Array(repeating: 0, count: 12)), ArrayOfReal(Array(repeating: 0, count: 12))])))
			#expect(sender.send("VI3Dinte", ["----": uneven, "Strt": AppleEventList([0, 0, 0])]).error?.number == -50, "\(scale)")
			sender.send("VI3Dclos", ["----": uneven])
		}
		// A scale that isn't finite, or whose span isn't, is -50: a span that overflowed read past the field (Audit C1).
		for scale: any AppleEventEncodable in [AppleEventList([-1.0E+308, 1.0E+308]), ArrayOfReal([0, .infinity])] {
			let wide = try #require(sender.open("wide", [1, scale, 1], AppleEventList([AppleEventList([1, 1]), AppleEventList([0, 0]), AppleEventList([0, 0])])))
			#expect(sender.send("VI3Dinte", ["----": wide, "Strt": AppleEventList([0, 9.0E+307, 0])]).error?.number == -50)
			sender.send("VI3Dclos", ["----": wide])
		}
		// A scalar field is -1, as recorded.
		let scalar = try #require(sender.open("scalar", [2, 2, 2], ArrayOfReal(Array(repeating: 1, count: 8))))
		#expect(sender.send("VI3Dinte", ["----": scalar, "Strt": AppleEventList([0, 0, 0])]).error?.number == -1)
		sender.send("VI3Dclos", ["----": scalar])
	}
}
