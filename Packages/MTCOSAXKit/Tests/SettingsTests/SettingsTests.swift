import AppleEventCore
import Foundation
import Testing
import TestSupport
@testable import Settings
import TextAdditions

/// The settings commands with a defaults suite of their own, so tests never read or change the app's settings.
@MainActor
private final class SettingsCommands {
	let defaults = MemoryDefaults.make()
	private let dispatcher = CommandDispatcher()

	init() {
		dispatcher.register(Settings.commands(defaults: defaults))
		dispatcher.register(TextAdditions.commands(settings: defaults))
	}

	@discardableResult
	func send(_ code: String, _ parameters: [String: any AppleEventEncodable] = [:]) -> AppleEventReply {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
		for (keyword, value) in parameters {
			event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
		}
		return dispatcher.dispatch(event)
	}

	func get(_ name: any AppleEventEncodable) -> AppleEventReply { send("MTCsget ", ["----": name]) }
	@discardableResult
	func set(_ name: any AppleEventEncodable, _ value: any AppleEventEncodable) -> AppleEventReply { send("MTCsset ", ["----": name, "to  ": value]) }
	@discardableResult
	func reset(_ name: any AppleEventEncodable) -> AppleEventReply { send("MTCsrset", ["----": name]) }
}

private func constant(_ code: String) -> NSAppleEventDescriptor {
	NSAppleEventDescriptor(enumCode: FourCharCode(fourCharString: code))
}

private var idleTimeout: NSAppleEventDescriptor { constant("MTsi") }
private var dollarReferences: NSAppleEventDescriptor { constant("MTsd") }
private var regexSyntax: NSAppleEventDescriptor { constant("MTsr") }
private var allSettings: NSAppleEventDescriptor { constant("MTsa") }

@MainActor
struct SettingsTests {
	@Test func defaults() {
		let settings = SettingsCommands()
		#expect(settings.get(idleTimeout).result?.int32Value == 3605)
		#expect(settings.get(dollarReferences).result?.booleanValue == false)
		#expect(settings.get(regexSyntax).result?.stringValue == "RUBY")
	}

	@Test func setGetAndReset() {
		let settings = SettingsCommands()
		settings.set(regexSyntax, "pcre")
		#expect(settings.get(regexSyntax).result?.stringValue == "PCRE")
		#expect(settings.defaults.string(forKey: "RegexSyntax") == "PCRE")
		settings.set(idleTimeout, 300.0)
		#expect(settings.get(idleTimeout).result?.descriptorType == typeSInt32)
		#expect(settings.get(idleTimeout).result?.int32Value == 300)
		#expect(Settings.idleTimeout(in: settings.defaults) == .seconds(300))
		settings.set(idleTimeout, 0)
		#expect(Settings.idleTimeout(in: settings.defaults) == nil)
		settings.set(dollarReferences, true)
		#expect(Settings.dollarReferences(in: settings.defaults))
		settings.reset(regexSyntax)
		#expect(settings.get(regexSyntax).result?.stringValue == "RUBY")
		#expect(settings.defaults.object(forKey: "RegexSyntax") == nil)
		settings.reset(allSettings)
		#expect(settings.defaults.object(forKey: "IdleTimeoutSeconds") == nil)
		#expect(settings.defaults.object(forKey: "DollarReferences") == nil)
	}

	@Test func textNames() {
		let settings = SettingsCommands()
		settings.set("regex syntax", "PERL")
		for name in ["regex_syntax", "RegexSyntax", "Regex Syntax", "regexsyntax", "REGEX_SYNTAX"] {
			#expect(settings.get(name).result?.stringValue == "PERL", "\(name)")
		}
		settings.reset("AllSettings")
		#expect(settings.get("regex syntax").result?.stringValue == "RUBY")
		#expect(settings.get("all settings").result?.numberOfItems == 3)
		#expect(settings.get("all_settings").result?.numberOfItems == 3)
	}

	@Test func allSettingsRecords() throws {
		let settings = SettingsCommands()
		settings.set(dollarReferences, true)
		let list = try #require(settings.get(allSettings).result)
		let records = (1 ... list.numberOfItems).compactMap { list.atIndex($0).flatMap(RecordFields.init) }
		#expect(records.map { $0[.code("pnam")]?.enumCodeValue.fourCharString } == ["MTsi", "MTsd", "MTsr"])
		#expect(records.map { $0[.code("key ")]?.stringValue } == ["IdleTimeoutSeconds", "DollarReferences", "RegexSyntax"])
		#expect(records[1][.code("val ")]?.booleanValue == true)
		#expect(records[1][.code("MTdv")]?.booleanValue == false)
		#expect(records[1][.code("MTid")]?.booleanValue == false)
		#expect(records[0][.code("MTid")]?.booleanValue == true)
		#expect(records[2][.code("dscr")]?.stringValue?.contains("PCRE") == true)
		// A record's name goes straight back to mtc_get.
		#expect(settings.get(try #require(records[1][.code("pnam")])).result?.booleanValue == true)
	}

	@Test func errors() {
		let settings = SettingsCommands()
		let unknown = settings.get("nope")
		#expect(unknown.error?.number == -1728)
		#expect(unknown.error?.message?.contains("regex_syntax") == true)
		#expect(settings.get(constant("MTzz")).error?.number == -1728)
		#expect(settings.get(42).error == .coercionFailed)
		#expect(settings.send("MTCsget ").error == .missingParameter)
		#expect(settings.send("MTCsset ", ["----": regexSyntax]).error == .missingParameter)
		#expect(settings.set(idleTimeout, "300").error?.number == -1700)
		#expect(settings.set(idleTimeout, -1).error?.number == -50)
		#expect(settings.set(idleTimeout, 2.5).error?.number == -50)
		#expect(settings.set(dollarReferences, 1).error?.number == -1700)
		#expect(settings.set(regexSyntax, 1).error?.number == -1700)
		#expect(settings.set(regexSyntax, "NOT_A_SYNTAX").error?.number == -50)
		#expect(settings.set(regexSyntax, ["PCRE"]).error?.number == -1700)
		let missing = settings.set(regexSyntax, NSAppleEventDescriptor.missingValue)
		#expect(missing.error?.number == -1700)
		#expect(missing.error?.message?.contains("mtc_reset") == true)
		#expect(settings.set(allSettings, 1).error?.number == -50)
		// Nothing was stored by the failures.
		#expect(settings.defaults.dictionaryRepresentation().keys.filter { ["IdleTimeoutSeconds", "DollarReferences", "RegexSyntax"].contains($0) }.isEmpty)
	}

	/// Values stored with `defaults write` read the way the code using them reads them.
	@Test func storedValuesFromDefaultsWrite() {
		let settings = SettingsCommands()
		settings.defaults.set("120", forKey: "IdleTimeoutSeconds")
		#expect(settings.get(idleTimeout).result?.int32Value == 120)
		settings.defaults.set(-5, forKey: "IdleTimeoutSeconds")
		#expect(settings.get(idleTimeout).result?.int32Value == 3605)
		// What the app uses too: these crashed it at launch, or meant one second.
		for value in [1e30, true, "1e30"] as [Any] {
			settings.defaults.set(value, forKey: "IdleTimeoutSeconds")
			#expect(settings.get(idleTimeout).result?.int32Value == 3605, "\(value)")
			#expect(Settings.idleTimeout(in: settings.defaults) == .seconds(3605), "\(value)")
		}
		// The text commands and mtc_get read DollarReferences by one rule.
		for (value, on) in [("Y", false), ("TRUE", true), ("maybe", false), ("0", false)] as [(Any, Bool)] {
			settings.defaults.set(value, forKey: "DollarReferences")
			#expect(Settings.dollarReferences(in: settings.defaults) == on, "\(value)")
			#expect(settings.get(dollarReferences).result?.booleanValue == on, "\(value)")
		}
		settings.defaults.set("YES", forKey: "DollarReferences")
		#expect(settings.get(dollarReferences).result?.booleanValue == true)
		settings.defaults.set("bogus", forKey: "RegexSyntax")
		#expect(settings.get(regexSyntax).result?.stringValue == "RUBY")
		let list = settings.get(allSettings).result
		#expect(list?.atIndex(3).flatMap(RecordFields.init)?[.code("MTid")]?.booleanValue == true)
	}

	/// The text commands see a change from the next command.
	@Test func textCommandsFollowTheSettings() {
		let settings = SettingsCommands()
		let find: [String: any AppleEventEncodable] = ["----": #"\h+"#, "$in ": "x \t y", "UsGR": true, "WaMr": true]
		#expect(settings.send("SATIFINd", find).error == OSAXError(-2763))
		settings.set(regexSyntax, "PCRE")
		#expect(settings.send("SATIFINd", find).result?.stringValue == " \t ")
		settings.reset(regexSyntax)
		#expect(settings.send("SATIFINd", find).error == OSAXError(-2763))

		let change: [String: any AppleEventEncodable] = ["----": "(b)", "by  ": "[$1]", "$in ": "abc", "UsGR": true]
		#expect(settings.send("SATIRPLl", change).result?.stringValue == "a[$1]c")
		settings.set(dollarReferences, true)
		#expect(settings.send("SATIRPLl", change).result?.stringValue == "a[b]c")
	}
}
