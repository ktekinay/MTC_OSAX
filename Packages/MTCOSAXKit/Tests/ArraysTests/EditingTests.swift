import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// What the fixtures don't show (they're in `Fixtures/Arrays`): commands Satimage got wrong, other kinds of array,
/// and sizes.
@MainActor
struct EditingTests {
	private func list(_ reply: AppleEventReply) -> [NSAppleEventDescriptor]? {
		reply.result.flatMap { result in result.descriptorType == typeAEList ? (0 ..< result.numberOfItems).map { result.atIndex($0 + 1)! } : nil }
	}

	/// SatimageOSAX replied -1708; it removes what `replacemissingvalue` replaces, keeping the kind of list.
	@Test func removeMissingValues() throws {
		let removed = try #require(list(send("SATIRmMv", ["----": AppleEventList([1, NSAppleEventDescriptor.missingValue, 2.5, NSAppleEventDescriptor(double: .nan)])])))
		#expect(removed.map(\.descriptorType) == [typeSInt32, typeIEEE64BitFloatingPoint])
		#expect(removed.map(\.doubleValue) == [1, 2.5])
		#expect(values(send("SATIRmMv", ["----": ArrayOfReal([.nan, 1, .nan, 2])])) == [1, 2])
		#expect(values(send("SATIRmMv", ["----": ArrayOfReal([.nan])])) == [])
		let nested = try #require(list(send("SATIRmMv", ["----": AppleEventList([ArrayOfReal([1, .nan]), AppleEventList([NSAppleEventDescriptor.missingValue, 3])])])))
		#expect(ArrayOfReal.values(of: nested[0]) == [1])
		#expect(nested[1].numberOfItems == 1 && nested[1].atIndex(1)!.int32Value == 3)
	}

	/// SatimageOSAX wrapped them (1.0E+10 became 1410065408); AppleScript's `as integer` is -1700 for them.
	@Test func integersBeyond32Bits() {
		let integers = FourCharCode(fourCharString: "LiIn")
		#expect(send("SATIExLF", ["----": ArrayOfReal([1, 1e10]), "for ": -1, "rtyp": NSAppleEventDescriptor(typeCode: integers)]).error == .coercionFailed)
		#expect(send("SATIExLF", ["----": ArrayOfReal([2147483647.4, -2147483648]), "for ": -1, "rtyp": NSAppleEventDescriptor(typeCode: integers)]).error == nil)
	}

	/// Arrays of 4-byte reals (SatimageOSAX's `read binary`) and polynomials are read as arrays.
	@Test func otherKindsOfArray() throws {
		let floats = try #require(NSAppleEventDescriptor(descriptorType: ArrayOfReal.descriptorType, data: Data("Not a recordgnis".utf8) + Data([0, 0, 0x80, 0x3f, 0, 0, 0, 0x40])))
		#expect(values(send("SATILiRe", ["----": floats])) == [2, 1])
		let polynomial = try ArrayOfReal.descriptor(count: 3, type: ArrayOfReal.polynomialType) { _ = $0.initialize(from: [1, 2, 3]) }
		#expect(values(send("SATIExLF", ["----": polynomial, "for ": -1])) == [1, 2, 3])
	}

	/// Nested lists are flattened, however deep (up to the nesting limit, -50 beyond).
	@Test func nestedLists() {
		#expect(values(send("SATIExLF", ["----": AppleEventList([1, AppleEventList([2, AppleEventList([3])])]), "for ": -1])) == [1, 2, 3])
		var deep: NSAppleEventDescriptor = NSAppleEventDescriptor(int32: 1)
		for _ in 0 ... NSAppleEventDescriptor.maximumNesting + 1 {
			let list = NSAppleEventDescriptor.list()
			list.insert(deep, at: 1)
			deep = list
		}
		#expect(send("SATIExLF", ["----": deep, "for ": -1]).error?.number == -50)
	}

	/// A million numbers each way, in well under a second (a descriptor for each would take seconds).
	@Test func largeArrays() {
		let count = 1_000_000
		let start = Date()
		let array = ArrayOfReal((0 ..< count).map(Double.init))
		#expect(values(send("SATIExLF", ["----": array, "at  ": 2, "for ": -1, "step": 2]))?.count == count / 2)
		#expect(values(send("SATISeLF", ["----": array, "at  ": 1, "step": 2, "into": ArrayOfReal(Array(repeating: -1, count: count / 2))]))?.prefix(3) == [-1, 1, -1])
		#expect(values(send("SATIInLF", ["----": array, "into": array]))?.count == 2 * count)
		#expect(values(send("SATILiRe", ["----": array]))?.first == Double(count - 1))
		#expect(values(send("SATIMASK", ["----": array, "with": array]))?.count == count - 1)
		#expect(Date().timeIntervalSince(start) < 5)
	}

	/// A matrix with numbers that aren't `ncols` × `nrows` of them is -50.
	@Test func matrixSizes() {
		let wrong = RecordFields([(.code("ncol"), NSAppleEventDescriptor(int32: 2)), (.code("nrow"), NSAppleEventDescriptor(int32: 2)), (.code("Lido"), AppleEventList([1, 2, 3]).appleEventDescriptor)]).appleEventDescriptor.coerce(toDescriptorType: Matrix.descriptorType)!
		#expect(send("SATILiRe", ["----": wrong]).error?.number == -50)
		#expect(send("SATICRMT", ["----": "1", "ncol": 20_000, "nrow": 20_000]).error?.number == -50)
	}
}
