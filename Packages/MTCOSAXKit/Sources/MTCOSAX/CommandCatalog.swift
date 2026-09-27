@_exported import AppleEventCore
import Diagnostics
import Foundation

/// Every suite the app implements. Add each new suite's commands here.
public enum CommandCatalog {
	public static func makeDispatcher(version: @escaping () -> String = bundleVersion) -> CommandDispatcher {
		let dispatcher = CommandDispatcher()
		dispatcher.register(Diagnostics.commands(version: version))
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
