import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// What the fixtures don't show (they're in `Fixtures/Arrays`): where Satimage was wrong, missing values in blocks,
/// and sizes.
@MainActor
struct StatisticsTests {
	private func matrix(_ columns: Int, _ rows: Int, _ values: [Double]) throws -> NSAppleEventDescriptor {
		try Matrix(columns: columns, rows: rows, values: values).descriptor()
	}

	private func matrix(_ reply: AppleEventReply) throws -> Matrix? {
		try reply.result.flatMap { try Matrix($0) }
	}

	/// SatimageOSAX also counted numbers up to an interval below the minimum (0 to 9 from 4 in 2 intervals: 5 and 3).
	@Test func histogramCountsOnlyTheRange() throws {
		let reply = try #require(send("SATIHisT", ["----": ArrayOfReal((0 ..< 10).map(Double.init)), "samp": 2, "MIN ": 4]).result)
		#expect(ArrayOfReal.values(of: reply.atIndex(1)!) == [5.25, 7.75])
		#expect(ArrayOfReal.values(of: reply.atIndex(2)!) == [3, 3])
		let inside = try #require(send("SATIHisT", ["----": ArrayOfReal((0 ..< 10).map(Double.init)), "samp": 2, "MIN ": 3, "MAX ": 6]).result)
		#expect(ArrayOfReal.values(of: inside.atIndex(2)!) == [2, 2])
	}

	/// Without `reduced`, as if the matrix had zeros around it: the identity filter keeps it as it is (SatimageOSAX
	/// put some border values in the wrong places).
	@Test func filterWithoutReducing() throws {
		let identity: [Double] = [0, 0, 0, 0, 1, 0, 0, 0, 0]
		let m33 = try matrix(3, 3, (1 ... 9).map(Double.init))
		#expect(try matrix(send("SATIBLUR", ["----": m33, "with": ArrayOfReal(identity), "redu": false]))?.values == (1 ... 9).map(Double.init))
		let ones = ArrayOfReal(Array(repeating: 1, count: 9))
		let blurred = try matrix(send("SATIBLUR", ["----": try matrix(4, 4, (1 ... 16).map(Double.init)), "with": ones, "redu": false]))
		#expect(blurred?.values == [14, 24, 30, 22, 33, 54, 63, 45, 57, 90, 99, 69, 46, 72, 78, 54])
		// Too small to reduce: -50 (SatimageOSAX: -108, out of memory).
		#expect(send("SATIBLUR", ["----": try matrix(2, 2, [1, 2, 3, 4]), "with": ones]).error?.number == -50)
		#expect(try matrix(send("SATIBLUR", ["----": try matrix(2, 2, [1, 2, 3, 4]), "with": ones, "redu": false]))?.values == [10, 10, 10, 10])
	}

	/// A block size of 0 is -50 (SatimageOSAX returned nothing); missing values are left out of a block's statistics
	/// and counted by "missing value".
	@Test func resampleBlocks() throws {
		let m = try matrix(2, 2, [1, .nan, 3, 4])
		#expect(send("SATIReMa", ["----": m, "bloc": AppleEventList([0, 2])]).error?.number == -50)
		#expect(try matrix(send("SATIReMa", ["----": m, "bloc": AppleEventList([2, 2])]))?.values == [8.0 / 3])
		#expect(try matrix(send("SATIReMa", ["----": m, "bloc": AppleEventList([2, 2]), "WANT": "missing value"]))?.values == [1])
		#expect(try matrix(send("SATIReMa", ["----": m, "bloc": AppleEventList([1, 1]), "WANT": "Median"]))?.values.map(\.isNaN) == [false, true, false, false])
	}

	/// The statistics of a million numbers, in well under a second.
	@Test func largeArrays() throws {
		let count = 1_000_000
		let array = ArrayOfReal((0 ..< count).map(Double.init))
		let start = Date()
		let reply = try #require(send("SATIStat", ["----": array, "Krts": true]).result)
		let stats = try #require(RecordFields(reply))
		#expect(stats[.code("MEDI")]?.doubleValue == Double(count / 2))
		#expect(stats[.code("MAXi")]?.int32Value == Int32(count))
		#expect(values(send("SATIRSum", ["----": array]))?.last == Double(count) * Double(count - 1) / 2)
		#expect(send("SATIHisT", ["----": array, "samp": 100]).error == nil)
		#expect(Date().timeIntervalSince(start) < 5)
	}
}
