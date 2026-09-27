import Foundation
import Testing
@testable import AppleEventCore

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

	@Test func urlRejectsRelativePath() {
		#expect(throws: OSAXError.coercionFailed) {
			try URL(scriptPath: "file.txt")
		}
	}
}

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
