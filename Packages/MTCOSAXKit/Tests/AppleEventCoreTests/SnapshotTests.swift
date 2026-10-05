import Foundation
import Testing
@testable import AppleEventCore

@MainActor
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

	/// An alias snapshot holds a path; it's recreated as a file URL, since aliases can't be created in-process.
	@Test func aliasIsStoredAsPath() throws {
		var snapshot = DescriptorSnapshot(type: "alis")
		snapshot.text = "/private/tmp/some file.txt"
		let descriptor = snapshot.descriptor
		#expect(descriptor.descriptorType == typeFileURL)
		#expect(descriptor.fileURLValue?.path == "/private/tmp/some file.txt")
		#expect(snapshot.replacingText("/private/tmp", with: "/var/x").text == "/var/x/some file.txt")
	}

	/// An FSRef snapshot holds a path, and is recreated as an FSRef when the item exists.
	@Test func fileReferenceIsStoredAsPath() throws {
		let folder = URL(fileURLWithPath: "/private/tmp")
		let reference = try #require(NSAppleEventDescriptor.fileReference(folder))
		#expect(reference.descriptorType == typeFSRef)
		let snapshot = DescriptorSnapshot(reference)
		#expect(snapshot.text == folder.path)
		#expect(snapshot.descriptor.descriptorType == typeFSRef)
		#expect(snapshot.descriptor.fileReferencePath == folder.path)

		var missing = DescriptorSnapshot(type: "fsrf")
		missing.text = "/nonexistent/file.txt"
		#expect(missing.descriptor.fileURLValue?.path == "/nonexistent/file.txt")
	}

	@Test func fileReferencesCoerce() throws {
		let folder = URL(fileURLWithPath: "/private/tmp")
		#expect(NSAppleEventDescriptor.fileReference(URL(fileURLWithPath: "/nonexistent")) == nil)
		let alias = try #require(NSAppleEventDescriptor.alias(folder))
		#expect(alias.descriptorType == typeAlias)
		#expect(alias.coerce(toDescriptorType: typeFileURL)?.fileURLValue?.path == folder.path)
		#expect(try URL(appleEventDescriptor: #require(NSAppleEventDescriptor.fileReference(folder))).path == folder.path)
	}

	@Test func anyMatchesEveryValue() {
		var expected = DescriptorSnapshot(type: "reco")
		expected.fields = [.init(key: "pnam", value: DescriptorSnapshot(NSAppleEventDescriptor(string: "a"))), .init(key: "asmo", value: DescriptorSnapshot(type: "any"))]
		var actual = expected
		actual.fields![1].value = DescriptorSnapshot(NSAppleEventDescriptor(date: Date()))
		#expect(expected.matches(actual))
		actual.fields![0].value = DescriptorSnapshot(NSAppleEventDescriptor(string: "b"))
		#expect(!expected.matches(actual))
	}

	@Test func arrayOfRealIsStoredAsNumbers() throws {
		// createarray 3, as SatimageOSAX returns it.
		let recorded = Data(hexString: "4e6f742061207265636f726462756f640000000000000000000000000000f03f0000000000000040")
		let descriptor = try #require(NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "Lido"), data: recorded))
		#expect(try ArrayOfReal(appleEventDescriptor: descriptor).values == [0, 1, 2])
		#expect(ArrayOfReal([0, 1, 2]).appleEventDescriptor.data == recorded)
		let snapshot = DescriptorSnapshot(descriptor)
		#expect(snapshot.items?.map(\.real) == [0, 1, 2])
		#expect(snapshot.descriptor.data == recorded)
		let withNaN = DescriptorSnapshot(ArrayOfReal([.nan, 1]).appleEventDescriptor)
		#expect(withNaN.items?.first?.text == "nan")
		#expect(try roundTrip(withNaN.descriptor).data == ArrayOfReal([.nan, 1]).appleEventDescriptor.data)
		#expect(throws: OSAXError.coercionFailed) { try ArrayOfReal(appleEventDescriptor: NSAppleEventDescriptor(string: "x")) }
	}

	@Test func realTolerance() {
		let expected = DescriptorSnapshot([NSAppleEventDescriptor(double: 1.0)].appleEventDescriptor)
		let close = DescriptorSnapshot([NSAppleEventDescriptor(double: 1.0.nextUp.nextUp)].appleEventDescriptor)
		#expect(!expected.matches(close))
		#expect(expected.matches(close, realTolerance: 2))
		#expect(!expected.matches(close, realTolerance: 1))
		#expect(DescriptorSnapshot.unitsInTheLastPlace(between: 0, and: -0.0) == 0)
		#expect(DescriptorSnapshot.unitsInTheLastPlace(between: 1, and: -1) == .max)
	}

	@Test func recordsCompareRegardlessOfOrder() {
		let a = RecordFields([(.user("b"), NSAppleEventDescriptor(int32: 2)), (.user("a"), NSAppleEventDescriptor(int32: 1)), (.code("pnam"), NSAppleEventDescriptor(string: "x"))])
		let b = RecordFields([(.code("pnam"), NSAppleEventDescriptor(string: "x")), (.user("a"), NSAppleEventDescriptor(int32: 1)), (.user("b"), NSAppleEventDescriptor(int32: 2))])
		#expect(DescriptorSnapshot(a.appleEventDescriptor) != DescriptorSnapshot(b.appleEventDescriptor))
		#expect(DescriptorSnapshot(a.appleEventDescriptor).normalized == DescriptorSnapshot(b.appleEventDescriptor).normalized)
		let c = RecordFields([(.user("a"), NSAppleEventDescriptor(int32: 2)), (.user("b"), NSAppleEventDescriptor(int32: 1))])
		#expect(DescriptorSnapshot(a.appleEventDescriptor).normalized != DescriptorSnapshot(c.appleEventDescriptor).normalized)
	}

	@Test func referencesAreMapped() {
		let reference = { (bytes: [UInt8]) in DescriptorSnapshot(NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "CFob"), data: Data(bytes))!) }
		let recorded = reference([1, 2]), actual = reference([9, 9])
		var references: [String: DescriptorSnapshot] = [:]
		let recordedList = DescriptorSnapshot([recorded.descriptor, NSAppleEventDescriptor(int32: 1)].appleEventDescriptor)
		recordedList.collectReferences(from: DescriptorSnapshot([actual.descriptor, NSAppleEventDescriptor(int32: 1)].appleEventDescriptor), into: &references)
		#expect(references[recorded.hex!] == actual)
		#expect(recordedList.replacingReferences(references).items?.first == actual)
		#expect(reference([3]).replacingReferences(references) == reference([3]))
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
