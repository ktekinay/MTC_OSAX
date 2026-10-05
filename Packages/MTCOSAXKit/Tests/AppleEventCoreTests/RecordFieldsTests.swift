import Foundation
import Testing
@testable import AppleEventCore

@MainActor
struct RecordFieldsTests {
	@Test func codesAndUserKeysRoundTrip() throws {
		let record = RecordFields([
			(.code("pnam"), NSAppleEventDescriptor(string: "x")),
			(.user("abc"), NSAppleEventDescriptor(int32: 1)),
			(.user("b"), NSAppleEventDescriptor(int32: 2)),
		])
		let descriptor = record.appleEventDescriptor
		#expect(descriptor.forKeyword(FourCharCode(fourCharString: "pnam"))?.stringValue == "x")
		#expect(descriptor.forKeyword(FourCharCode(fourCharString: "usrf"))?.numberOfItems == 4)
		let decoded = try #require(RecordFields(descriptor))
		#expect(decoded.fields.map(\.key) == [.code("pnam"), .user("abc"), .user("b")])
		#expect(decoded[.user("b")]?.int32Value == 2)
		#expect(decoded[.user("zzz")] == nil)
	}

	@Test func notARecord() {
		#expect(RecordFields(NSAppleEventDescriptor.list()) == nil)
		#expect(RecordFields(NSAppleEventDescriptor(string: "x")) == nil)
	}
}
