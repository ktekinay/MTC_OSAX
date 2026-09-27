import AppleEventCore
import Foundation
import TextMatching

/// The "Satimage Text Additions" suite (event class `SATI`).
public enum TextAdditions {
	/// - Parameter timeZone: the zone dates are formatted and parsed in. Tests replay fixtures in the zone they were
	///   recorded in; the app uses the system's.
	public static func commands(timeZone: TimeZone = .current) -> [CommandDefinition] {
		commands(context: TextContext(timeZone: timeZone))
	}

	static func commands(context: TextContext) -> [CommandDefinition] {
		searchCommands(context) + simpleCommands() + fileCommands() + formatCommands(context)
	}
}

/// State shared by the suite's commands for the life of the app.
final class TextContext {
	let regexCache = RegexCache()
	/// Whether `$1`-style references are on when a command doesn't say (the `DollarReferences` default).
	let dollarReferencesDefault: () -> Bool
	/// The zone `strftime` and `strptime` work in.
	let timeZone: TimeZone

	init(
		dollarReferencesDefault: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "DollarReferences") },
		timeZone: TimeZone = .current
	) {
		self.dollarReferencesDefault = dollarReferencesDefault
		self.timeZone = timeZone
	}
}
