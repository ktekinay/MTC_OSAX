import AppleEventCore
import Foundation
import Testing
@testable import Arrays

/// `read binary` and `write binary` (recorded from SatimageOSAX in `Fixtures/Arrays/Files`). Every file is in this
/// test's own temporary folder.
@MainActor
struct BinaryFileTests {
	let folder: URL

	init() throws {
		folder = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-binary-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	}

	private func file(_ name: String) -> URL {
		folder.appendingPathComponent(name)
	}

	private func type(_ code: String) -> NSAppleEventDescriptor {
		NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: code))
	}

	/// Every format both ways, in each byte order.
	@Test func roundTrips() {
		let numbers: [Double] = [1, -2, 100, 0]
		for code in ["doub", "sing", "long", "shor", "byte"] {
			for bigEndian in [false, true] {
				let url = file("\(code)-\(bigEndian).bin")
				#expect(send("SATIWrBF", ["----": url, "data": ArrayOfReal(numbers), "rtyp": type(code), "Endi": bigEndian]).error == nil)
				#expect(values(send("SATIRdBF", ["----": url, "rtyp": type(code), "Endi": bigEndian])) == numbers, "\(code), big endian \(bigEndian)")
			}
		}
		try? FileManager.default.removeItem(at: folder)
	}

	/// SatimageOSAX gave error 1 for a path as text; it's a path, as for the file commands.
	@Test func pathsAsText() {
		let path = file("text.bin").path
		#expect(send("SATIWrBF", ["----": path, "data": AppleEventList([7, 8]), "rtyp": type("byte")]).error == nil)
		#expect(values(send("SATIRdBF", ["----": path, "rtyp": type("byte")])) == [7, 8])
		try? FileManager.default.removeItem(at: folder)
	}

	/// SatimageOSAX read integers into 4-byte reals, so 16,777,217 came back as 16,777,216.
	@Test func largeIntegersAreExact() {
		let url = file("large.bin")
		#expect(send("SATIWrBF", ["----": url, "data": AppleEventList([16_777_217, -2_147_483_648, 2_147_483_647]), "rtyp": type("long")]).error == nil)
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("long")])) == [16_777_217, -2_147_483_648, 2_147_483_647])
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("long"), "Sign": false])) == [16_777_217, 2_147_483_648, 2_147_483_647])
		try? FileManager.default.removeItem(at: folder)
	}

	/// Another `as` (SatimageOSAX took `as text` without saying what it wrote) and a negative offset are -50; a
	/// missing file is -43; no numbers writes nothing.
	@Test func errors() {
		#expect(send("SATIWrBF", ["----": file("bad.bin"), "data": AppleEventList([1]), "rtyp": type("TEXT")]).error?.number == -50)
		#expect(send("SATIWrBF", ["----": file("bad.bin"), "data": AppleEventList([1]), "strt": -1]).error?.number == -50)
		#expect(send("SATIRdBF", ["----": file("missing.bin"), "rtyp": type("doub")]).error == OSAXError(-43))
		#expect(send("SATIWrBF", ["----": file("none.bin"), "data": AppleEventList([])]).error == nil)
		#expect(!FileManager.default.fileExists(atPath: file("none.bin").path))
		#expect(!FileManager.default.fileExists(atPath: file("bad.bin").path))
		try? FileManager.default.removeItem(at: folder)
	}

	/// Blocks, steps and skipped bytes on a large file, and writing in the middle.
	@Test func blocksAndOffsets() {
		let url = file("blocks.bin")
		let count = 1_000_000
		#expect(send("SATIWrBF", ["----": url, "data": ArrayOfReal((0 ..< count).map(Double.init)), "rtyp": type("long")]).error == nil)
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("long"), "skip": 8, "jump": 1000, "bloc": 2]))?.prefix(4) == [2, 3, 1002, 1003])
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("long"), "for ": 3, "jump": 10]))  == [0, 10, 20])
		#expect(send("SATIWrBF", ["----": url, "data": AppleEventList([-1]), "rtyp": type("long"), "strt": 4]).error == nil)
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("long"), "for ": 3])) == [0, -1, 2])
		try? FileManager.default.removeItem(at: folder)
	}

	/// Only regular files: a named pipe is -50 both ways (writing waited forever for something to read it), and a
	/// folder is error 21.
	@Test func onlyRegularFiles() {
		let pipe = file("pipe")
		#expect(mkfifo(pipe.path, 0o600) == 0)
		#expect(send("SATIWrBF", ["----": pipe, "data": AppleEventList([1])]).error?.number == -50)
		#expect(send("SATIRdBF", ["----": pipe, "rtyp": type("doub")]).error?.number == -50)
		#expect(send("SATIRdBF", ["----": folder, "rtyp": type("doub")]).error?.number == 21)
		#expect(send("SATIWrBF", ["----": folder, "data": AppleEventList([1])]).error?.number == 21)
		try? FileManager.default.removeItem(at: folder)
	}

	/// Overlapping blocks read at most 100,000,000 numbers (a 20 KB file made 600 MB, and a file over 4 GB overflowed
	/// and crashed).
	@Test func overlappingBlocksAreLimited() {
		let url = file("overlap.bin")
		#expect(send("SATIWrBF", ["----": url, "data": ArrayOfReal(Array(repeating: 7, count: 30_000)), "rtyp": type("byte")]).error == nil)
		#expect(send("SATIRdBF", ["----": url, "rtyp": type("byte"), "bloc": 20_000, "jump": 1]).error?.number == -50)
		let overlapping = (30_000 - 100 + 1) * 100
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("byte"), "bloc": 100, "jump": 1]))?.count == overlapping)
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("byte"), "skip": 29_998])) == [7, 7])
		#expect(values(send("SATIRdBF", ["----": url, "rtyp": type("byte"), "skip": 30_000])) == [])
		try? FileManager.default.removeItem(at: url)
	}
}
