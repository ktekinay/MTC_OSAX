import Foundation

/// One scripting command: its SDEF code and the handler that implements it.
public struct CommandDefinition {
	public typealias Handler = (AppleEventRequest) throws -> (any AppleEventEncodable)?

	/// The command's AppleScript name, as in the SDEF (for diagnostics only).
	public let name: String
	public let key: EventKey
	public let handler: Handler

	/// - Parameter code: the SDEF's eight-character command code, event class followed by event ID (e.g. `"SATIUPPE"`).
	public init(_ name: String, code: String, handler: @escaping Handler) {
		self.name = name
		self.key = EventKey(code: code)
		self.handler = handler
	}
}

/// An (event class, event ID) pair.
public struct EventKey: Hashable, CustomStringConvertible {
	public let eventClass: AEEventClass
	public let eventID: AEEventID

	public init(eventClass: AEEventClass, eventID: AEEventID) {
		self.eventClass = eventClass
		self.eventID = eventID
	}

	/// - Parameter code: eight characters, e.g. `"SATIUPPE"`.
	public init(code: String) {
		precondition(code.count == 8, "Command code must be 8 characters: \"\(code)\"")
		self.init(
			eventClass: FourCharCode(fourCharString: String(code.prefix(4))),
			eventID: FourCharCode(fourCharString: String(code.suffix(4)))
		)
	}

	/// The eight-character SDEF form, e.g. `"SATIUPPE"`.
	public var code: String {
		eventClass.fourCharString + eventID.fourCharString
	}

	public var description: String { code }
}

/// The outcome of a command: a result, an error, or neither.
public struct AppleEventReply {
	public var result: NSAppleEventDescriptor?
	public var error: OSAXError?

	public init(result: NSAppleEventDescriptor? = nil, error: OSAXError? = nil) {
		self.result = result
		self.error = error
	}

	/// Reads a reply event (`aevt/ansr`) as sent back to a script.
	public init(replyEvent reply: NSAppleEventDescriptor) {
		result = reply.paramDescriptor(forKeyword: keyDirectObject)
		if let number = reply.paramDescriptor(forKeyword: keyErrorNumber) {
			error = OSAXError(Int(number.int32Value), reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue)
		}
	}

	/// Writes the result or error into the reply event the Apple Event Manager provides.
	public func write(to reply: NSAppleEventDescriptor) {
		guard reply.descriptorType != typeNull else {
			return // The sender asked for no reply.
		}
		if let error {
			reply.setParam(NSAppleEventDescriptor(int32: Int32(clamping: error.number)), forKeyword: keyErrorNumber)
			if let message = error.message {
				reply.setParam(NSAppleEventDescriptor(string: message), forKeyword: keyErrorString)
			}
		} else if let result {
			reply.setParam(result, forKeyword: keyDirectObject)
		}
	}
}

/// Routes incoming Apple events to registered commands.
public final class CommandDispatcher {
	public private(set) var commands: [EventKey: CommandDefinition] = [:]

	public init() {}

	public func register(_ command: CommandDefinition) {
		precondition(commands[command.key] == nil, "Duplicate command code \(command.key) for \(command.name)")
		commands[command.key] = command
	}

	public func register(_ commands: [CommandDefinition]) {
		commands.forEach(register)
	}

	/// Runs the command for an event and returns its outcome. Never throws: every failure becomes an error reply.
	public func dispatch(_ event: NSAppleEventDescriptor) -> AppleEventReply {
		let key = EventKey(eventClass: event.eventClass, eventID: event.eventID)
		guard let command = commands[key] else {
			return AppleEventReply(error: .eventNotHandled)
		}
		do {
			let result = try command.handler(AppleEventRequest(event))
			return AppleEventReply(result: result?.appleEventDescriptor)
		} catch let error as OSAXError {
			return AppleEventReply(error: error)
		} catch {
			return AppleEventReply(error: .general(error.localizedDescription))
		}
	}

	public func handle(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
		dispatch(event).write(to: reply)
	}
}
