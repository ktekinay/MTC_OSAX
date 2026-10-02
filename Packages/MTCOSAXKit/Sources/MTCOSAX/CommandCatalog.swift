@_exported import AppleEventCore
import Diagnostics
@_exported import FileAdditions
import Arrays
import ListUtilities
import MathFunctions
import XML
@_exported import PropertyLists
import FilesAndFolders
import TextAdditions
@_exported import Settings
import Foundation

/// Every suite the app implements. Add each new suite's commands here.
public enum CommandCatalog {
	/// - Parameters:
	///   - timeZone: the zone for date commands; tests pass the zone a fixture was recorded in. Nil (the app's) is the
	///     system's zone, as it is at each command.
	///   - dialogs: the app's dialogs for the `navchoose` commands; without them, those commands aren't handled.
	///   - documents: the open property lists and XML documents; the app keeps it to know when any are open.
	///   - settings: where MTC_OSAX's settings are kept; tests pass their own, so they don't read or change the app's.
	@MainActor
	public static func makeDispatcher(
		version: @escaping () -> String = bundleVersion,
		timeZone: TimeZone? = nil,
		dialogs: (any FileDialogs)? = nil,
		documents: DocumentStore = DocumentStore(),
		settings: UserDefaults = .standard
	) -> CommandDispatcher {
		let dispatcher = CommandDispatcher()
		dispatcher.register(Diagnostics.commands(version: version))
		dispatcher.register(Settings.commands(defaults: settings))
		dispatcher.register(TextAdditions.commands(timeZone: timeZone, settings: settings) { reference, entries in
			try PropertyLists.add(entries, to: reference, store: documents)
		})
		dispatcher.register(FilesAndFolders.commands())
		dispatcher.register(FileAdditions.commands(dialogs: dialogs))
		dispatcher.register(MathFunctions.commands())
		dispatcher.register(ListUtilities.commands())
		dispatcher.register(Arrays.commands())
		dispatcher.register(PropertyLists.commands(store: documents))
		dispatcher.register(XML.commands(store: documents))
		return dispatcher
	}

	/// e.g. `"MTC_OSAX 1.0.1 (1)"`, from the main bundle's Info.plist.
	public static func bundleVersion() -> String {
		let info = Bundle.main.infoDictionary ?? [:]
		let name = info["CFBundleName"] as? String ?? "MTC_OSAX"
		let version = info["CFBundleShortVersionString"] as? String ?? "?"
		let build = info["CFBundleVersion"] as? String ?? "?"
		return "\(name) \(version) (\(build))"
	}
}
