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
	///     recorded in; the app gives none, for the system's zone as it is at each command.
	///   - settings: where the `DollarReferences` and `RegexSyntax` settings are read; fixture replays pass their own.
	///   - propertyLists: writes `filter text … into` a CFRef.
	@MainActor
	public static func commands(timeZone: TimeZone? = nil, settings: UserDefaults = .standard, propertyLists: PropertyListWriter? = nil) -> [CommandDefinition] {
		commands(context: TextContext(
			dollarReferencesDefault: { Settings.dollarReferences(in: settings) },
			regexSyntaxDefault: { Settings.regexSyntax(in: settings) },
			timeZone: timeZone,
			propertyLists: propertyLists
		))
	}

	/// Each command's regex searches together get `RegexDeadline.budget`.
	@MainActor
	static func commands(context: TextContext) -> [CommandDefinition] {
		(searchCommands(context) + simpleCommands() + fileCommands() + formatCommands(context)).map { command in
			CommandDefinition(command.name, code: command.key.code) { request in
				try RegexDeadline.withBudget { try command.handler(request) }
			}
		}
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
	/// A zone given for `strftime` and `strptime` to work in; nil for the system's.
	private let fixedTimeZone: TimeZone?
	/// The zone `strftime` and `strptime` work in: the one given, or the system's as it is now. (The system's was
	/// taken once, when the commands were made: after the Mac's zone changed, dates were formatted with the new
	/// zone's hour and the old zone's name and offset until the app quit.)
	var timeZone: TimeZone { fixedTimeZone ?? TimeZone.current }
	let propertyLists: TextAdditions.PropertyListWriter?

	init(
		dollarReferencesDefault: @escaping () -> Bool = { Settings.dollarReferences(in: .standard) },
		regexSyntaxDefault: @escaping () -> RegexSyntax = { Settings.regexSyntax(in: .standard) },
		timeZone: TimeZone? = nil,
		propertyLists: TextAdditions.PropertyListWriter? = nil
	) {
		self.dollarReferencesDefault = dollarReferencesDefault
		self.regexSyntaxDefault = regexSyntaxDefault
		self.fixedTimeZone = timeZone
		self.propertyLists = propertyLists
	}
}
