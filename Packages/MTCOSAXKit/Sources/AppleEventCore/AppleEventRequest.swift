import Foundation

/// Read access to the parameters of an incoming command.
public struct AppleEventRequest {
	public let event: NSAppleEventDescriptor

	public init(_ event: NSAppleEventDescriptor) {
		self.event = event
	}

	/// The raw descriptor for a parameter, or nil if the script didn't pass it.
	/// AppleScript sends an omitted direct parameter as `null`, which also counts as missing.
	public func descriptor(for keyword: String) -> NSAppleEventDescriptor? {
		guard let descriptor = event.paramDescriptor(forKeyword: FourCharCode(fourCharString: keyword)),
		      descriptor.descriptorType != typeNull
		else {
			return nil
		}
		return descriptor
	}

	public func has(_ keyword: String) -> Bool {
		descriptor(for: keyword) != nil
	}

	/// A parameter the command can't run without. Throws -1701 if missing, -1700 if it can't be coerced.
	public func requiredParameter<T: AppleEventDecodable>(_ keyword: String, as type: T.Type = T.self) throws -> T {
		guard let descriptor = descriptor(for: keyword) else {
			throw OSAXError.missingParameter
		}
		return try T(appleEventDescriptor: descriptor)
	}

	/// An optional parameter, or nil if missing. Throws -1700 if it can't be coerced.
	public func parameter<T: AppleEventDecodable>(_ keyword: String, as type: T.Type = T.self) throws -> T? {
		try descriptor(for: keyword).map { try T(appleEventDescriptor: $0) }
	}

	/// An optional parameter with a default value.
	public func parameter<T: AppleEventDecodable>(_ keyword: String, default defaultValue: T) throws -> T {
		try parameter(keyword, as: T.self) ?? defaultValue
	}

	public func requiredDirectParameter<T: AppleEventDecodable>(as type: T.Type = T.self) throws -> T {
		try requiredParameter(Keyword.directObject, as: type)
	}

	public func directParameter<T: AppleEventDecodable>(as type: T.Type = T.self) throws -> T? {
		try parameter(Keyword.directObject, as: type)
	}
}
