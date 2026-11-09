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

	/// Matrices count toward the nesting limit (each started again from 0: 3,000 levels ran out of stack). Audit C2.
	@Test func matricesCountTowardNesting() throws {
		// Through lists, each level is two (the matrix, and the list holding the next).
		for throughLists in [true, false] {
			let allowed = throughLists ? 250 : 500
			#expect(values(send("SATIExLF", ["----": try nestedMatrices(allowed, throughLists: throughLists), "for ": -1])) == [1])
			for levels in [allowed + 20, 3_000] {
				let deep = try nestedMatrices(levels, throughLists: throughLists)
				#expect(send("SATIExLF", ["----": deep, "for ": -1]).error?.number == -50, "\(levels)")
				#expect(send("SATIFILL", ["----": AppleEventList([deep]), "with": 0]).error?.number == -50, "\(levels)")
			}
		}
	}

	/// Each of a matrix's dimensions at most 100,000,000: 0 columns let 2,147,483,647 rows through, and
	/// reversearray went through them one by one (Audit C3). A matrix with a dimension of 0 is still a matrix.
	@Test func matrixDimensions() throws {
		let tall = try Matrix(columns: 0, rows: 2_147_483_647, values: []).descriptor()
		#expect(send("SATILiRe", ["----": tall]).error?.number == -50)
		let wide = try Matrix(columns: 100_000_001, rows: 0, values: []).descriptor()
		#expect(send("SATILiRe", ["----": wide]).error?.number == -50)
		let empty = try #require(send("SATILiRe", ["----": try Matrix(columns: 0, rows: 3, values: []).descriptor()]).result)
		#expect(try Matrix(empty) == Matrix(columns: 0, rows: 3, values: []))
	}

	/// Blocks of 0 numbers insert nothing, at once (2,147,483,647 of them were gone through one by one). Audit S3.
	@Test func emptyBlocks() {
		let start = Date()
		#expect(values(send("SATIInLF", ["----": AppleEventList([1]), "into": AppleEventList([2]), "for ": 2_147_483_647, "bloc": 0])) == [2])
		#expect(Date().timeIntervalSince(start) < 1)
	}

	/// A range wider than a real can hold, as for createarray (it made {NaN, inf, inf}). Audit R4.
	@Test func wideMatrixRanges() {
		#expect(values(send("SATICRMT", ["----": "x", "ncol": 3, "nrow": 1, "rang": [-1e308, 1e308]])) == [-1e308, 0, 1e308])
		#expect(values(send("SATICRMT", ["----": "y", "ncol": 1, "nrow": 3, "rang": [1e308, -1e308]])) == [1e308, 0, -1e308])
		#expect(values(send("SATICRMT", ["----": "x", "ncol": 3, "nrow": 1, "rang": [0, 1]])) == [0, 0.5, 1])
	}

	/// Items that aren't missing keep their types: integers of each size, reals, types, text (integers were copied
	/// through a descriptor each; now from their data). Audit P3.
	@Test func replaceMissingKeepsItems() throws {
		var wide: Int64 = 1 << 40, short: Int16 = -7
		let items: [NSAppleEventDescriptor] = [
			NSAppleEventDescriptor(int32: 5), NSAppleEventDescriptor.missingValue,
			NSAppleEventDescriptor(descriptorType: typeSInt64, bytes: &wide, length: 8)!,
			NSAppleEventDescriptor(descriptorType: typeSInt16, bytes: &short, length: 2)!,
			NSAppleEventDescriptor(double: 2.5), NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "abcd")),
			NSAppleEventDescriptor(string: "text"),
		]
		let replaced = try #require(list(send("SATIFILL", ["----": AppleEventList(items), "with": 9])))
		#expect(replaced.map(\.descriptorType) == [typeSInt32, typeIEEE64BitFloatingPoint, typeSInt64, typeSInt16, typeIEEE64BitFloatingPoint, typeType, typeUnicodeText])
		#expect(replaced[0].int32Value == 5 && replaced[1].doubleValue == 9 && replaced[2].data == Data(bytes: &wide, count: 8))
		#expect(replaced[3].data == Data(bytes: &short, count: 2) && replaced[4].doubleValue == 2.5)
		#expect(replaced[5].typeCodeValue == FourCharCode(fourCharString: "abcd") && replaced[6].stringValue == "text")
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

	/// A diagonal list of more than 10,000 numbers is -50, as `ncols` is (100,000 tried 80 GB), and two axes too
	/// large together are refused before either is made.
	@Test func matrixLimits() {
		#expect(send("SATICRMT", ["----": "d", "Diag": ArrayOfReal(Array(repeating: 1, count: 10_001))]).error?.number == -50)
		#expect(values(send("SATICRMT", ["----": "d", "Diag": ArrayOfReal([1, 2])])) == [1, 0, 0, 2])
		let start = Date()
		#expect(send("SATICRMT", ["----": "1", "ncol": 100_000_000, "nrow": 100_000_000]).error?.number == -50)
		#expect(Date().timeIntervalSince(start) < 1)
		#expect(values(send("SATICRMT", ["----": "x", "ncol": 3, "nrow": 2])) == [0, 1, 2, 0, 1, 2])
		#expect(values(send("SATICRMT", ["----": "y", "ncol": 2, "nrow": AppleEventList([5, 7])])) == [5, 5, 7, 7])
	}

	/// Other items stay as they were (an integer an integer, text text); missing values and NaN are replaced, in
	/// nested lists too, which may nest at most 512 levels (-50).
	@Test func replaceMissingValuesInLists() throws {
		let list = AppleEventList([1, NSAppleEventDescriptor.missingValue, NSAppleEventDescriptor(double: .nan), 2.5, "a", AppleEventList([NSAppleEventDescriptor.missingValue])])
		let replaced = try #require(self.list(send("SATIFILL", ["----": list, "with": 0])))
		#expect(replaced.map(\.descriptorType) == [typeSInt32, typeIEEE64BitFloatingPoint, typeIEEE64BitFloatingPoint, typeIEEE64BitFloatingPoint, typeUnicodeText, typeAEList])
		#expect(replaced.prefix(4).map(\.doubleValue) == [1, 0, 0, 2.5])
		#expect(replaced[4].stringValue == "a")
		#expect(replaced[5].atIndex(1)?.doubleValue == 0)
		#expect(send("SATIRmMv", ["----": nested(NSAppleEventDescriptor.maximumNesting + 1)]).error?.number == -50)
		#expect(send("SATIRmMv", ["----": nested(NSAppleEventDescriptor.maximumNesting)]).error == nil)
	}

	/// Lists made from arrays: reals (`missing value` for NaN) or integers.
	@Test func listsFromArrays() throws {
		let reals = try #require(list(send("SATIExLF", ["----": ArrayOfReal([1.5, .nan, -2]), "for ": -1, "rtyp": NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "LiDo"))])))
		#expect(reals.map(\.descriptorType) == [typeIEEE64BitFloatingPoint, typeType, typeIEEE64BitFloatingPoint])
		#expect(reals[0].doubleValue == 1.5 && reals[1].isMissingValue && reals[2].doubleValue == -2)
		let integers = try #require(list(send("SATIExLF", ["----": ArrayOfReal([1.5, .nan, -2]), "for ": -1, "rtyp": NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "LiIn"))])))
		#expect(integers.map(\.descriptorType) == [typeSInt32, typeType, typeSInt32])
		#expect(integers[0].int32Value == 2 && integers[2].int32Value == -2)
	}
}
