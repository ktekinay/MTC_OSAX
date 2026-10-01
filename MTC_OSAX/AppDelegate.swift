import AppKit
import MTCOSAX

/// A faceless app: installs an Apple event handler for every implemented command, then quits once it has had no
/// events for the `idle_timeout` setting (an hour by default; never while documents are open). The next script
/// that targets it relaunches it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var installer: AppleEventHandlerInstaller?
	private var idleMonitor: IdleMonitor?

	func applicationWillFinishLaunching(_ notification: Notification) {
		// Cocoa Scripting loads the dictionary the first time it handles an event itself (e.g. `get` of an object
		// specifier such as `POSIX file (someVariable)`), and then installs its own handlers for every command,
		// replacing ours. Loading it now means ours are installed after it and stay.
		_ = NSScriptSuiteRegistry.shared()
		// Open property lists would be lost, so the app doesn't quit for being idle while any are open.
		let documents = DocumentStore()
		// The idle timeout setting (`mtc_set idle_timeout`) is read each time the countdown starts, so a change
		// applies after the next command.
		let idleMonitor = IdleMonitor(timeout: { documents.hasOpenDocuments ? nil : Settings.idleTimeout(in: .standard) }) {
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
}
