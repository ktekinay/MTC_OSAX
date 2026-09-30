import Foundation
import Testing
@testable import AppleEventCore

@MainActor
struct FourCharCodeTests {
	@Test(arguments: ["SATI", "$in ", "----", "ut16"])
	func roundTrips(_ code: String) {
		#expect(FourCharCode(fourCharString: code).fourCharString == code)
	}

	@Test func matchesSystemConstants() {
		#expect(FourCharCode(fourCharString: "utxt") == typeUnicodeText)
		#expect(FourCharCode(fourCharString: "----") == keyDirectObject)
	}
}

@MainActor
struct DecodingTests {
	@Test func stringFromText() throws {
		#expect(try String(appleEventDescriptor: NSAppleEventDescriptor(string: "abc")) == "abc")
	}

	@Test func stringFromInteger() throws {
		#expect(try String(appleEventDescriptor: NSAppleEventDescriptor(int32: 42)) == "42")
	}

	@Test func stringRejectsList() {
		#expect(throws: OSAXError.coercionFailed) {
			try String(appleEventDescriptor: ["a", "b"].appleEventDescriptor)
		}
	}

	@Test func intFromIntegralReal() throws {
		#expect(try Int(appleEventDescriptor: NSAppleEventDescriptor(double: 2)) == 2)
	}

	@Test func doubleFromInteger() throws {
		#expect(try Double(appleEventDescriptor: NSAppleEventDescriptor(int32: 3)) == 3)
	}

	@Test func boolFromTrueAndFalseTypes() throws {
		let trueDescriptor = NSAppleEventDescriptor(descriptorType: typeTrue, data: nil)!
		let falseDescriptor = NSAppleEventDescriptor(descriptorType: typeFalse, data: nil)!
		#expect(try Bool(appleEventDescriptor: trueDescriptor))
		#expect(try !Bool(appleEventDescriptor: falseDescriptor))
	}

	@Test func dateRoundTrips() throws {
		let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
		#expect(try Date(appleEventDescriptor: date.appleEventDescriptor) == date)
	}

	@Test func arrayFromList() throws {
		let list = [1, 2, 3].appleEventDescriptor
		#expect(try [Int](appleEventDescriptor: list) == [1, 2, 3])
	}

	@Test func arrayWrapsSingleValue() throws {
		#expect(try [String](appleEventDescriptor: NSAppleEventDescriptor(string: "a")) == ["a"])
	}

	@Test func urlFromFileURL() throws {
		let url = URL(fileURLWithPath: "/tmp/x.txt")
		#expect(try URL(appleEventDescriptor: NSAppleEventDescriptor(fileURL: url)).path == "/tmp/x.txt")
	}

	/// A `furl` holding an http URL used to be read from the network by every file parameter.
	@Test func urlRejectsNonFileURLs() throws {
		let web = try #require(NSAppleEventDescriptor(descriptorType: typeFileURL, data: Data("http://example.com/x.plist".utf8)))
		#expect((#expect(throws: OSAXError.self) { try URL(appleEventDescriptor: web) })?.number == -1700)
	}

	@Test func urlFromPOSIXPath() throws {
		#expect(try URL(appleEventDescriptor: NSAppleEventDescriptor(string: "/tmp/x.txt")).path == "/tmp/x.txt")
	}

	@Test func urlFromTildePath() throws {
		let url = try URL(scriptPath: "~/x.txt")
		#expect(url.path == NSHomeDirectory() + "/x.txt")
	}

	@Test func urlFromHFSPathOnStartupVolume() throws {
		let volume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		#expect(try URL(scriptPath: "\(volume):Users:someone:a/b.txt").path == "/Users/someone/a:b.txt")
		#expect(try URL(scriptPath: "\(volume):Users:").path == "/Users")
	}

	@Test func urlFromHFSPathOnOtherVolume() throws {
		#expect(try URL(scriptPath: "Backup Disk:folder:file").path == "/Volumes/Backup Disk/folder/file")
	}

	@Test func urlFromFileURLString() throws {
		#expect(try URL(scriptPath: "file:///tmp/a%20b.txt").path == "/tmp/a b.txt")
		#expect(throws: OSAXError.coercionFailed) { try URL(scriptPath: "file://") }
	}

	/// Edge cases that used to slip through: another Mac's file URL, schemes in capitals, `..` in HFS paths, no
	/// volume name, and the startup volume's name in another case.
	/// The Apple Event Manager turned text past 32 bits into -2147483648 rather than failing.
	@Test func integersFromText() throws {
		func integer(_ text: String) throws -> Int { try Int(appleEventDescriptor: NSAppleEventDescriptor(string: text)) }
		for text in ["3000000000", "-3000000000", "1e40", "2147483648"] {
			#expect((#expect(throws: OSAXError.self) { try integer(text) })?.number == -1700, "\(text)")
		}
		#expect(try integer("42") == 42)
		#expect(try integer("2147483647") == 2_147_483_647)
		#expect(try integer("-2147483648") == -2_147_483_648)
		#expect((#expect(throws: OSAXError.self) { try integer("forty") })?.number == -1700)
	}

	@Test func urlEdgeCases() throws {
		func number(_ path: String) -> Int? {
			(#expect(throws: OSAXError.self) { try URL(scriptPath: path) })?.number
		}
		#expect(number("file://host/etc/passwd") == -1700)
		// A URL value naming another computer, as text does (it was used as the local path).
		let remote = try #require(NSAppleEventDescriptor(descriptorType: typeFileURL, data: Data("file://host/etc/passwd".utf8)))
		#expect((#expect(throws: OSAXError.self) { try URL(appleEventDescriptor: remote) })?.number == -1700)
		let local = try #require(NSAppleEventDescriptor(descriptorType: typeFileURL, data: Data("file://localhost/tmp/x".utf8)))
		#expect(try URL(appleEventDescriptor: local).path == "/tmp/x")
		#expect(try URL(scriptPath: "file://localhost/tmp/x").path == "/tmp/x")
		#expect(try URL(scriptPath: "FILE:///tmp/x").path == "/tmp/x")
		#expect(number("HTTP://example.com/x") == -1700)
		#expect(number("Vol:private:tmp:..:etc:passwd") == -1700)
		// Nor as the volume (it was /Volumes/../etc/hosts).
		#expect(number("..:etc:hosts") == -1700)
		#expect(number(".:etc:hosts") == -1700)
		#expect(number(":folder:file") == -1700)
		#expect(number("Vol:a:::b") == -1700)
		#expect(try URL(scriptPath: "Backup:a:b::c").path == "/Volumes/Backup/a/c")
		let volume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		#expect(try URL(scriptPath: "\(volume.uppercased()):Users").path == "/Users")
	}

	@Test func urlRejectsRelativePath() {
		#expect(throws: OSAXError.coercionFailed) {
			try URL(scriptPath: "file.txt")
		}
	}
}

@MainActor
struct EncodingTests {
	@Test func smallIntIsInteger() {
		#expect(42.appleEventDescriptor.descriptorType == typeSInt32)
	}

	@Test func largeIntIsReal() {
		let descriptor = 5_000_000_000.appleEventDescriptor
		#expect(descriptor.descriptorType == typeIEEE64BitFloatingPoint)
		#expect(descriptor.doubleValue == 5_000_000_000)
	}

	@Test func recordKeepsKeysAndOrder() {
		let record = AppleEventRecord(["mPos": 2, "mLen": 4, "mRes": "2007"]).appleEventDescriptor
		#expect(DescriptorSnapshot(record).summary == #"reco {mPos: long 2, mLen: long 4, mRes: utxt "2007"}"#)
	}

	@Test func missingValue() {
		#expect(DescriptorSnapshot(.missingValue).summary == "type 'msng'")
	}
}

@MainActor
struct CLengthTests {
	/// Lengths of 2 GB or more used to trap in Int32(_:) before reaching libxml2 or tomlc17.
	@Test func tooLargeIsAnError() throws {
		#expect(try Int32(length: 12) == 12)
		#expect(try Int32(length: Int(Int32.max)) == Int32.max)
		#expect((#expect(throws: OSAXError.self) { try Int32(length: Int(Int32.max) + 1) })?.number == -50)
	}
}

@MainActor
struct WriteReplacingTests {
	/// Saves used to write in place, so a failure part way left a cut-short file.
	@Test func replacesInOneStep() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replace-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let file = folder.appendingPathComponent("a.txt")
		try Data("new file".utf8).writeReplacing(file)
		#expect(try String(contentsOf: file, encoding: .utf8) == "new file")
		// Permissions are kept.
		chmod(file.path, 0o600)
		try Data("second".utf8).writeReplacing(file)
		#expect(try String(contentsOf: file, encoding: .utf8) == "second")
		#expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) == 0o600)
		// A link's target is replaced, not the link.
		let link = folder.appendingPathComponent("link.txt")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
		try Data("through the link".utf8).writeReplacing(link)
		#expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == file.path)
		#expect(try String(contentsOf: file, encoding: .utf8) == "through the link")
		// Nothing is left behind, and a missing folder is an error.
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a.txt", "link.txt"])
		#expect(throws: (any Error).self) { try Data().writeReplacing(folder.appendingPathComponent("nope/b.txt")) }
	}

	/// Replacing needs to make a file in the folder: a writable file in a folder that isn't couldn't be saved at all.
	@Test func writableFileInReadOnlyFolder() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replace-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let file = folder.appendingPathComponent("a.txt")
		try Data("old".utf8).write(to: file)
		chmod(folder.path, 0o555)
		defer {
			chmod(folder.path, 0o755)
			try? FileManager.default.removeItem(at: folder)
		}
		try Data("new".utf8).writeReplacing(file)
		#expect(try String(contentsOf: file, encoding: .utf8) == "new")
		// A new file there still can't be made.
		#expect(throws: (any Error).self) { try Data().writeReplacing(folder.appendingPathComponent("b.txt")) }
	}

	/// A link to a file that didn't exist yet was replaced by a file (with the link's 0755) instead of the file
	/// being made; setuid and setgid bits were put back after the write cleared them.
	@Test func linksToNewFilesAndSpecialBits() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replace-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let manager = FileManager.default
		try manager.createSymbolicLink(atPath: folder.path + "/relative.txt", withDestinationPath: "sub/new.txt")
		try manager.createSymbolicLink(atPath: folder.path + "/chain.txt", withDestinationPath: folder.path + "/relative.txt")
		try Data("made".utf8).writeReplacing(folder.appendingPathComponent("chain.txt"))
		#expect(try manager.destinationOfSymbolicLink(atPath: folder.path + "/chain.txt") == folder.path + "/relative.txt")
		#expect(try manager.destinationOfSymbolicLink(atPath: folder.path + "/relative.txt") == "sub/new.txt")
		#expect(try String(contentsOfFile: folder.path + "/sub/new.txt", encoding: .utf8) == "made")
		let mode = try #require(manager.attributesOfItem(atPath: folder.path + "/sub/new.txt")[.posixPermissions] as? Int)
		#expect(mode & 0o111 == 0)
		// A loop is an error, not a file in its place.
		try manager.createSymbolicLink(atPath: folder.path + "/loop", withDestinationPath: "loop")
		#expect(throws: (any Error).self) { try Data().writeReplacing(folder.appendingPathComponent("loop")) }
		#expect((try? manager.destinationOfSymbolicLink(atPath: folder.path + "/loop")) == "loop")
		// setuid goes, as with any write.
		let file = folder.appendingPathComponent("tool")
		try Data("old".utf8).write(to: file)
		chmod(file.path, 0o4755)
		try Data("new".utf8).writeReplacing(file)
		#expect(try manager.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o755)
	}
}

@MainActor
struct ArrayOfRealTests {
	/// Arrays are made straight into the descriptor's buffer (the numbers were copied twice more on the way), and
	/// a descriptor that can't be made is -108 rather than a trap.
	@Test func madeInOneBuffer() throws {
		let made = try ArrayOfReal.descriptor(count: 3) { buffer in
			for index in 0 ..< 3 { buffer[index] = Double(index) + 0.5 }
		}
		#expect(ArrayOfReal.values(of: made) == [0.5, 1.5, 2.5])
		#expect(made.data.prefix(16) == Data("Not a recordbuod".utf8))
		#expect(try ArrayOfReal([]).descriptor().data == Data("Not a recordbuod".utf8))
		#expect(try ArrayOfReal([1, 2]).descriptor() == ArrayOfReal([1, 2]).appleEventDescriptor)
	}

	/// Asking a list's data (to see whether it was an `array of real`) made the Apple Event Manager copy and
	/// byte-swap the whole list, and log, each time: half of `sortlist`'s time. 1,000 checks took about 10 seconds.
	@Test func otherDescriptorsAreRejectedWithoutReadingThem() {
		let list = Array(1 ... 10_000).appleEventDescriptor
		let clock = ContinuousClock()
		let elapsed = clock.measure {
			for _ in 0 ..< 1_000 {
				#expect(ArrayOfReal.values(of: list) == nil)
			}
		}
		#expect(elapsed < .seconds(1))
		#expect(ArrayOfReal.values(of: NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "Lido"), data: Data("Not a record".utf8))!) == nil)
	}

	/// The data was built 8 bytes at a time and read back through slices: 60 to 90% of `createarray` and `sqrt`.
	/// This took 0.95 seconds, and now about 5 ms.
	@Test func largeArraysConvertQuickly() throws {
		let values = (0 ..< 1_000_000).map { Double($0) / 3 }
		let clock = ContinuousClock()
		var decoded: [Double]?
		let elapsed = clock.measure {
			for _ in 0 ..< 5 {
				decoded = ArrayOfReal.values(of: ArrayOfReal(values).appleEventDescriptor)
			}
		}
		#expect(decoded == values)
		#expect(elapsed < .milliseconds(100))
		let bytes = ArrayOfReal([1.5, -0.0]).appleEventDescriptor.data
		#expect(bytes == Data("Not a recordbuod".utf8) + Data([0, 0, 0, 0, 0, 0, 0xf8, 0x3f, 0, 0, 0, 0, 0, 0, 0, 0x80]))
	}
}
