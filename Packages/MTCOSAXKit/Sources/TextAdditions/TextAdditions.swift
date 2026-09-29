import AppleEventCore
import Foundation
import Settings
import TextMatching

/// The "Satimage Text Additions" suite (event class `SATI`).
public enum TextAdditions {
	/// Adds keys and values to the property list dictionary a CFRef refers to (from the PropertyList suite), for
	/// `filter text … into`. Values are text or lists of text.
	public typealias PropertyListWriter = (_ reference: NSAppleEventDescriptor, _ entries: [(key: String, value: Any)]) throws -> Void

	/// - Parameters:
	///   - timeZone: the zone dates are formatted and parsed in. Tests replay fixtures in the zone they were
	///     recorded in; the app uses the system's.
	///   - settings: where the `DollarReferences` and `RegexSyntax` settings are read; fixture replays pass their own.
	///   - propertyLists: writes `filter text … into` a CFRef.
	@MainActor
	public static func commands(timeZone: TimeZone = .current, settings: UserDefaults = .standard, propertyLists: PropertyListWriter? = nil) -> [CommandDefinition] {
		commands(context: TextContext(
			dollarReferencesDefault: { Settings.dollarReferences(in: settings) },
			regexSyntaxDefault: { Settings.regexSyntax(in: settings) },
			timeZone: timeZone,
			propertyLists: propertyLists
		))
	}

	@MainActor
	static func commands(context: TextContext) -> [CommandDefinition] {
		searchCommands(context) + simpleCommands() + fileCommands() + formatCommands(context)
	}
}

/// State shared by the suite's commands for the life of the app.
@MainActor
final class TextContext {
	let regexCache = RegexCache()
	/// Whether `$1`-style references are on when a command doesn't say (the `DollarReferences` default).
	let dollarReferencesDefault: () -> Bool
	/// The regex syntax when a command doesn't say (the `RegexSyntax` default, e.g. `PCRE`); Satimage's `RUBY` if
	/// it's not set or not a syntax name.
	let regexSyntaxDefault: () -> RegexSyntax
	/// The zone `strftime` and `strptime` work in.
	let timeZone: TimeZone
	let propertyLists: TextAdditions.PropertyListWriter?

	init(
		dollarReferencesDefault: @escaping () -> Bool = { Settings.dollarReferences(in: .standard) },
		regexSyntaxDefault: @escaping () -> RegexSyntax = { Settings.regexSyntax(in: .standard) },
		timeZone: TimeZone = .current,
		propertyLists: TextAdditions.PropertyListWriter? = nil
	) {
		self.dollarReferencesDefault = dollarReferencesDefault
		self.regexSyntaxDefault = regexSyntaxDefault
		self.timeZone = timeZone
		self.propertyLists = propertyLists
	}
}
