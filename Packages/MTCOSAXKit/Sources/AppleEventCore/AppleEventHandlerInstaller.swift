import CoreServices
import Foundation

/// Connects a dispatcher to the running app's Apple Event Manager.
///
/// Handlers are installed with `AEInstallEventHandler` rather than `NSAppleEventManager`: when a handler's reply
/// carries error -1708 ("not handled"), `NSAppleEventManager` reports the event as unhandled, Cocoa Scripting takes
/// over, and every later command fails until the app quits. Satimage replies -1708 for `file offset`, so our
/// handler always reports success to the system and puts the error only in the reply.
@MainActor
public final class AppleEventHandlerInstaller {
	private let dispatcher: CommandDispatcher
	private let idleMonitor: IdleMonitor?

	public init(dispatcher: CommandDispatcher, idleMonitor: IdleMonitor? = nil) {
		self.dispatcher = dispatcher
		self.idleMonitor = idleMonitor
	}

	/// Installs a handler for every registered command. Safe to call again; later calls replace any handlers
	/// Cocoa Scripting installed for the same events. The installer must stay alive while the app runs.
	public func install() {
		let context = Unmanaged.passUnretained(self).toOpaque()
		for key in dispatcher.commands.keys {
			AEInstallEventHandler(key.eventClass, key.eventID, handleAppleEvent, context, false)
		}
	}

	fileprivate func handle(_ event: NSAppleEventDescriptor, reply: UnsafeMutablePointer<AppleEvent>) {
		idleMonitor?.beginActivity()
		defer { idleMonitor?.endActivity() }
		guard !Self.isFromAnotherMac(event) else {
			Self.write(AppleEventReply(error: Self.remoteSenderRefused), into: reply)
			return
		}
		Self.write(dispatcher.dispatch(event), into: reply)
	}

	/// MTC_OSAX extends AppleScript on the Mac it runs on. With Remote Apple Events turned on in Sharing, a script
	/// on another Mac could otherwise send it the file commands; such events are refused (-10004, a privilege error).
	static let remoteSenderRefused = OSAXError(-10004, "MTC_OSAX only takes commands from scripts on this Mac.")

	/// Whether an event came from another computer, by the Apple Event Manager's own record of its source.
	static func isFromAnotherMac(_ event: NSAppleEventDescriptor) -> Bool {
		isRemote(source: event.attributeDescriptor(forKeyword: AEKeyword(keyEventSourceAttr))?.int32Value)
	}

	/// Whether an event source (`AEEventSource`) is another computer. An event with no source recorded is local.
	static func isRemote(source: Int32?) -> Bool {
		source == Int32(kAERemoteProcess)
	}

	/// Writes an outcome into the reply the Apple Event Manager gave the handler.
	static func write(_ outcome: AppleEventReply, into reply: UnsafeMutablePointer<AppleEvent>) {
		guard reply.pointee.descriptorType != typeNull else {
			return // The sender asked for no reply.
		}
		outcome.write { descriptor, keyword in
			guard let desc = descriptor.aeDesc else { return OSErr(errAEDescNotFound) }
			return AEPutParamDesc(reply, keyword, desc)
		}
	}
}

/// The C callback the Apple Event Manager calls, on the main thread.
private let handleAppleEvent: AEEventHandlerUPP = { event, reply, context in
	guard let event, let reply, let context else {
		return OSErr(errAEEventNotHandled)
	}
	var copy = AEDesc()
	guard AEDuplicateDesc(event, &copy) == noErr else {
		return OSErr(errAEEventNotHandled)
	}
	// The Apple Event Manager calls handlers on the main thread, so these never cross threads.
	let call = MainThreadOnly((NSAppleEventDescriptor(aeDescNoCopy: &copy), reply, context))
	MainActor.assumeIsolated {
		let (descriptor, reply, context) = call.value
		Unmanaged<AppleEventHandlerInstaller>.fromOpaque(context).takeUnretainedValue().handle(descriptor, reply: reply)
	}
	return OSErr(noErr)
}

/// Values used only on the main thread, passed into `MainActor.assumeIsolated`.
private struct MainThreadOnly<Value>: @unchecked Sendable {
	let value: Value

	init(_ value: Value) {
		self.value = value
	}
}
