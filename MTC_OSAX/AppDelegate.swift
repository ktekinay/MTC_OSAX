import AppKit
import MTCOSAX

/// A faceless app: installs an Apple event handler for every implemented command, then quits once it has had no
/// events for the `idle_timeout` setting (an hour and five seconds by default; never while documents are open). The next script
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
		// Open property lists, XML documents and 3D arrays would be lost, so the app doesn't quit for being idle while
		// any are open.
		let documents = DocumentStore()
		// The idle timeout setting (`mtc_set idle_timeout`) is read each time the countdown starts, so a change
		// applies after the next command.
		// Before quitting for being idle, the commands already in the event queue are handled (taking events without
		// waiting dispatches the Apple events among them): one that arrived as the countdown ended keeps the app
		// running instead of failing with -609 as the app quits under it. Then the app goes at once, with `_exit`
		// (the settings are saved first, and nothing else is pending in an idle app): `terminate` takes longer, and in
		// a trial more commands sent meanwhile failed (13 of 300 sent a timeout apart, against 3). A command sent in the instant the process is
		// going can still fail; nothing here can catch that one.
		let idleMonitor = IdleMonitor(
			timeout: { documents.hasOpenDocuments ? nil : Settings.idleTimeout(in: .standard) },
			drain: {
				UserDefaults.standard.synchronize()
				while let event = NSApplication.shared.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
					NSApplication.shared.sendEvent(event)
				}
			},
			onIdle: { _exit(0) }
		)
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
