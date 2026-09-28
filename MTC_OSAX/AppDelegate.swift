import AppKit
import MTCOSAX

/// A faceless app: installs an Apple event handler for every implemented command,
/// then quits after an hour without events. The next script that targets it relaunches it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	/// `defaults write com.mactechnologies.mtc-osax IdleTimeoutSeconds 10` sets the timeout in seconds; 0 means
	/// never quit. Read each time the countdown starts, so a change applies after the next command.
	private static let idleTimeoutDefaultsKey = "IdleTimeoutSeconds"
	private static let defaultIdleTimeout = Duration.seconds(60 * 60)

	private var installer: AppleEventHandlerInstaller?
	private var idleMonitor: IdleMonitor?

	func applicationWillFinishLaunching(_ notification: Notification) {
		// Cocoa Scripting loads the dictionary the first time it handles an event itself (e.g. `get` of an object
		// specifier such as `POSIX file (someVariable)`), and then installs its own handlers for every command,
		// replacing ours. Loading it now means ours are installed after it and stay.
		_ = NSScriptSuiteRegistry.shared()
		// Open property lists would be lost, so the app doesn't quit for being idle while any are open.
		let documents = DocumentStore()
		let idleMonitor = IdleMonitor(timeout: { documents.hasOpenDocuments ? nil : Self.idleTimeout() }) {
			NSApplication.shared.terminate(nil)
		}
		let dispatcher = CommandCatalog.makeDispatcher(dialogs: PanelDialogs(), documents: documents)
		let installer = AppleEventHandlerInstaller(dispatcher: dispatcher, idleMonitor: idleMonitor)
		installer.install()
		self.installer = installer
		self.idleMonitor = idleMonitor
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		// Cocoa Scripting may have installed its own handlers for the SDEF's commands during launch.
		installer?.install()
		idleMonitor?.start()
	}

	private static func idleTimeout() -> Duration? {
		IdleMonitor.timeout(in: .standard, key: idleTimeoutDefaultsKey, default: defaultIdleTimeout)
	}
}
