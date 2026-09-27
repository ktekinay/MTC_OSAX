import Foundation
import Testing
@testable import AppleEventCore

struct SnapshotTests {
	/// Converting to a snapshot, through JSON, and back must give an identical descriptor.
	private func roundTrip(_ descriptor: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
		let json = try JSONEncoder().encode(DescriptorSnapshot(descriptor))
		return try JSONDecoder().decode(DescriptorSnapshot.self, from: json).descriptor
	}

	private static func sample(_ type: String) -> NSAppleEventDescriptor {
		switch type {
		case "utxt": NSAppleEventDescriptor(string: "abc déf")
		case "ut16": NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "ut16"), data: "ABC".data(using: .utf16))!
		case "utf8": NSAppleEventDescriptor(descriptorType: typeUTF8Text, data: Data("é".utf8))!
		case "long": NSAppleEventDescriptor(int32: -7)
		case "doub": NSAppleEventDescriptor(double: 1.5)
		case "bool": NSAppleEventDescriptor(boolean: true)
		case "true": NSAppleEventDescriptor(descriptorType: typeTrue, data: nil)!
		case "fals": NSAppleEventDescriptor(descriptorType: typeFalse, data: nil)!
		case "null": .null()
		case "type": .missingValue
		case "enum": NSAppleEventDescriptor(enumCode: FourCharCode(fourCharString: "yes "))
		case "ldt ": NSAppleEventDescriptor(date: Date(timeIntervalSinceReferenceDate: 800_000_000))
		case "list": [NSAppleEventDescriptor(string: "a"), NSAppleEventDescriptor(int32: 1)].appleEventDescriptor
		case "reco": AppleEventRecord(["mPos": 2, "mRes": ["x", "y"]]).appleEventDescriptor
		default: fatalError("No sample for \(type)")
		}
	}

	@Test(arguments: ["utxt", "ut16", "utf8", "long", "doub", "bool", "true", "fals", "null", "type", "enum", "ldt ", "list", "reco"])
	func roundTripsThroughJSON(type: String) throws {
		let descriptor = Self.sample(type)
		let copy = try roundTrip(descriptor)
		#expect(copy.descriptorType.fourCharString == type)
		#expect(copy.data == descriptor.data)
		#expect(DescriptorSnapshot(copy) == DescriptorSnapshot(descriptor))
	}

	@Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
	func nonFiniteRealsRoundTrip(_ value: Double) throws {
		let snapshot = DescriptorSnapshot(NSAppleEventDescriptor(double: value))
		let decoded = try JSONDecoder().decode(DescriptorSnapshot.self, from: JSONEncoder().encode(snapshot))
		#expect(decoded == snapshot)
		let copy = decoded.descriptor.doubleValue
		#expect(copy == value || (copy.isNaN && value.isNaN))
	}

	@Test func keywordRoundTrips() throws {
		var snapshot = DescriptorSnapshot(type: "keyw")
		snapshot.code = "by  "
		#expect(DescriptorSnapshot(snapshot.descriptor) == snapshot)
	}

	@Test func appleEventRoundTrips() throws {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: "SATIFINd"))
		event.setParam(NSAppleEventDescriptor(string: "([0-9]+)"), forKeyword: keyDirectObject)
		event.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: FourCharCode(fourCharString: "UsGR"))

		let copy = try roundTrip(event)
		#expect(copy.eventClass.fourCharString == "SATI")
		#expect(copy.eventID.fourCharString == "FINd")
		#expect(copy.paramDescriptor(forKeyword: keyDirectObject)?.stringValue == "([0-9]+)")
		#expect(copy.paramDescriptor(forKeyword: FourCharCode(fourCharString: "UsGR"))?.booleanValue == true)
	}

	@Test func textIsStoredReadably() {
		let snapshot = DescriptorSnapshot(NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "ut16"), data: "Hé".data(using: .utf16))!)
		#expect(snapshot.text == "Hé")
		#expect(snapshot.hex == nil)
	}

	@Test func normalizationUnifiesTextAndBooleans() {
		let satimageStyle = DescriptorSnapshot([
			NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "ut16"), data: "A".data(using: .utf16))!,
			NSAppleEventDescriptor(descriptorType: typeTrue, data: nil)!,
		].appleEventDescriptor)
		let ours = DescriptorSnapshot([NSAppleEventDescriptor(string: "A"), NSAppleEventDescriptor(boolean: true)].appleEventDescriptor)
		#expect(satimageStyle != ours)
		#expect(satimageStyle.normalized == ours.normalized)
	}

	@Test func normalizationKeepsDifferentValuesDifferent() {
		let a = DescriptorSnapshot(NSAppleEventDescriptor(string: "A")).normalized
		let b = DescriptorSnapshot(NSAppleEventDescriptor(string: "B")).normalized
		let number = DescriptorSnapshot(NSAppleEventDescriptor(int32: 1)).normalized
		let real = DescriptorSnapshot(NSAppleEventDescriptor(double: 1)).normalized
		#expect(a != b)
		#expect(number != real)
	}

	@Test func summary() {
		let value = [NSAppleEventDescriptor(string: #"say "hi""#), NSAppleEventDescriptor(int32: 1), .null()].appleEventDescriptor
		#expect(DescriptorSnapshot(value).summary == #"list [utxt "say \"hi\"", long 1, null]"#)
	}
}
