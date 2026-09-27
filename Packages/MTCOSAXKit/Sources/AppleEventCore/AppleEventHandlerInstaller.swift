import Foundation

/// Connects a dispatcher to the running app's Apple Event Manager.
@MainActor
public final class AppleEventHandlerInstaller: NSObject {
	private let dispatcher: CommandDispatcher
	private let idleMonitor: IdleMonitor?

	public init(dispatcher: CommandDispatcher, idleMonitor: IdleMonitor? = nil) {
		self.dispatcher = dispatcher
		self.idleMonitor = idleMonitor
	}

	/// Installs a handler for every registered command. Safe to call again; later calls
	/// replace any handlers Cocoa Scripting installed for the same events.
	public func install() {
		let manager = NSAppleEventManager.shared()
		for key in dispatcher.commands.keys {
			manager.setEventHandler(
				self,
				andSelector: #selector(handle(_:withReply:)),
				forEventClass: key.eventClass,
				andEventID: key.eventID
			)
		}
	}

	@objc private func handle(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
		idleMonitor?.beginActivity()
		defer { idleMonitor?.endActivity() }
		dispatcher.handle(event: event, reply: reply)
	}
}
