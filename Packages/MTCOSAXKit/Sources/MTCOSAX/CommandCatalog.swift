@_exported import AppleEventCore
import Diagnostics
@_exported import FileAdditions
import FilesAndFolders
import TextAdditions
import Foundation

/// Every suite the app implements. Add each new suite's commands here.
public enum CommandCatalog {
	/// - Parameters:
	///   - timeZone: the zone for date commands; tests pass the zone a fixture was recorded in.
	///   - dialogs: the app's dialogs for the `navchoose` commands; without them, those commands aren't handled.
	public static func makeDispatcher(
		version: @escaping () -> String = bundleVersion,
		timeZone: TimeZone = .current,
		dialogs: (any FileDialogs)? = nil
	) -> CommandDispatcher {
		let dispatcher = CommandDispatcher()
		dispatcher.register(Diagnostics.commands(version: version))
		dispatcher.register(TextAdditions.commands(timeZone: timeZone))
		dispatcher.register(FilesAndFolders.commands())
		dispatcher.register(FileAdditions.commands(dialogs: dialogs))
		return dispatcher
	}

	/// e.g. `"MTC_OSAX 0.1 (1)"`, from the main bundle's Info.plist.
	public static func bundleVersion() -> String {
		let info = Bundle.main.infoDictionary ?? [:]
		let name = info["CFBundleName"] as? String ?? "MTC_OSAX"
		let version = info["CFBundleShortVersionString"] as? String ?? "?"
		let build = info["CFBundleVersion"] as? String ?? "?"
		return "\(name) \(version) (\(build))"
	}
}
