import Foundation

/// A Swift type that can be read from an Apple event descriptor, coercing as AppleScript would.
public protocol AppleEventDecodable {
	init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws
}

/// A Swift type that can be returned to a script as an Apple event descriptor.
public protocol AppleEventEncodable {
	var appleEventDescriptor: NSAppleEventDescriptor { get }
}

public typealias AppleEventConvertible = AppleEventDecodable & AppleEventEncodable

// MARK: - Descriptors

extension NSAppleEventDescriptor: AppleEventEncodable {
	public var appleEventDescriptor: NSAppleEventDescriptor { self }

	/// AppleScript's `missing value`.
	public static var missingValue: NSAppleEventDescriptor {
		NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "msng"))
	}

	/// Coerces with the Apple Event Manager, as scripts would expect. Fails with -1700.
	public func coerced(to type: String) throws -> NSAppleEventDescriptor {
		guard let result = coerce(toDescriptorType: FourCharCode(fourCharString: type)) else {
			throw OSAXError.coercionFailed
		}
		return result
	}
}

/// Accepts any value unchanged (the SDEF's `any` / `anything` type).
public struct AnyDescriptor: AppleEventDecodable {
	public let descriptor: NSAppleEventDescriptor

	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) {
		self.descriptor = descriptor
	}
}

// MARK: - Scalars

extension String: AppleEventConvertible {
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		guard descriptor.descriptorType != typeAEList, descriptor.descriptorType != typeAERecord,
		      let string = try descriptor.coerced(to: "utxt").stringValue
		else {
			throw OSAXError.coercionFailed
		}
		self = string
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(string: self)
	}
}

extension Int: AppleEventConvertible {
	/// A 32-bit integer, as AppleScript's are. Text past that range is -1700, as a real is: the Apple Event Manager
	/// made it -2147483648 ("3000000000" became a large negative count or index).
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		if [typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType) {
			let real = try descriptor.coerced(to: "doub").doubleValue
			guard real > -2_147_483_649, real < 2_147_483_648 else {
				throw OSAXError.coercionFailed
			}
		}
		self = Int(try descriptor.coerced(to: "long").int32Value)
	}

	/// Returned as an AppleScript integer when it fits in 32 bits, otherwise as a real.
	public var appleEventDescriptor: NSAppleEventDescriptor {
		if let small = Int32(exactly: self) {
			return NSAppleEventDescriptor(int32: small)
		}
		return NSAppleEventDescriptor(double: Double(self))
	}
}

extension Double: AppleEventConvertible {
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		self = try descriptor.coerced(to: "doub").doubleValue
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(double: self)
	}
}

extension Bool: AppleEventConvertible {
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		self = try descriptor.coerced(to: "bool").booleanValue
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(boolean: self)
	}
}

extension Date: AppleEventConvertible {
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		guard let date = try descriptor.coerced(to: "ldt ").dateValue else {
			throw OSAXError.coercionFailed
		}
		self = date
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(date: self)
	}
}

extension Data: AppleEventConvertible {
	/// The raw bytes of the descriptor, whatever its type.
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) {
		self = descriptor.data
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(descriptorType: typeData, data: self) ?? .null()
	}
}

// MARK: - Lists

extension Array: AppleEventDecodable where Element: AppleEventDecodable {
	/// A non-list value is treated as a list of one item, as AppleScript does.
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		guard descriptor.descriptorType == typeAEList else {
			self = [try Element(appleEventDescriptor: descriptor)]
			return
		}
		self = try (0 ..< descriptor.numberOfItems).map { index in
			try Element(appleEventDescriptor: descriptor.atIndex(index + 1)!)
		}
	}
}

extension Array: AppleEventEncodable where Element: AppleEventEncodable {
	public var appleEventDescriptor: NSAppleEventDescriptor {
		let list = NSAppleEventDescriptor.list()
		for (index, element) in enumerated() {
			list.insert(element.appleEventDescriptor, at: index + 1)
		}
		return list
	}
}

/// A list whose items have different types, e.g. `{"a", 2.5}`.
public struct AppleEventList: AppleEventEncodable {
	public var items: [any AppleEventEncodable]

	public init(_ items: [any AppleEventEncodable]) {
		self.items = items
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		items.map(\.appleEventDescriptor).appleEventDescriptor
	}
}

// MARK: - Records

/// An AppleScript record with four-character keys, e.g. Satimage's `matchrecord`.
/// Fields keep the order they were added in.
public struct AppleEventRecord: AppleEventEncodable {
	public var fields: [(key: String, value: any AppleEventEncodable)]

	public init(_ fields: KeyValuePairs<String, any AppleEventEncodable>) {
		self.fields = fields.map { (key: $0.key, value: $0.value) }
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		let record = NSAppleEventDescriptor.record()
		for field in fields {
			record.setDescriptor(field.value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: field.key))
		}
		return record
	}
}

// MARK: - Files

extension URL: AppleEventConvertible {
	/// Accepts file references (`furl`, `alis`, `fsrf`, `bmrk`, …) and path strings (see `init(scriptPath:)`). A
	/// `furl` holding a URL that isn't a file's (`http://…`) is -1700: files are read and written with APIs that
	/// would otherwise fetch it from the network.
	public init(appleEventDescriptor descriptor: NSAppleEventDescriptor) throws {
		if descriptor.descriptorType == typeUnicodeText || descriptor.descriptorType == typeUTF8Text
			|| descriptor.descriptorType == typeChar
		{
			self = try URL(scriptPath: try String(appleEventDescriptor: descriptor))
			return
		}
		guard let url = try descriptor.coerced(to: "furl").fileURLValue else {
			throw OSAXError.coercionFailed
		}
		guard url.isLocalFile else {
			throw OSAXError(-1700, "\(url.absoluteString) isn’t a file on this Mac.")
		}
		self = url
	}

	/// A file URL on this Mac: no host, or `localhost`. (`file://otherhost/x` as a URL value was used as the local
	/// `/x`; only text was checked.)
	public var isLocalFile: Bool {
		isFileURL && (host.map { $0.isEmpty || $0.lowercased() == "localhost" } ?? true)
	}

	public var appleEventDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(fileURL: self)
	}

	/// Interprets a path string given by a script: a POSIX path (`/…` or `~…`), a `file://` URL (on this Mac:
	/// no host, or `localhost`), or an HFS path (`Volume:folder:file`). With `base` (a command's `from`), a relative
	/// path (`isRelativeScriptPath`) is in that folder, and `~` is the home folder only as `~/…`; without, a
	/// relative path is -1700, as is any other URL (`http://…`).
	/// An empty path is -1700 either way (in a folder, it was the folder itself: `fileremove {""} from f` deleted
	/// `f`). Every command that takes a path as text goes through here.
	public init(scriptPath path: String, relativeTo base: URL? = nil) throws {
		// No file has a NUL in its path (it became `%00` in the name).
		guard !path.contains("\0") else { throw OSAXError(-1700, "A path can’t contain a NUL character.") }
		if let base, URL.isRelativeScriptPath(path) {
			guard !path.isEmpty else { throw OSAXError(-1700, "An empty path doesn’t name a file.") }
			self = base.appendingPathComponent(path)
			return
		}
		if path.lowercased().hasPrefix("file://") {
			guard let url = URL(string: path), url.isFileURL, !url.path.isEmpty,
			      url.host.map({ $0.isEmpty || $0.lowercased() == "localhost" }) ?? true
			else {
				throw OSAXError.coercionFailed
			}
			self = URL(fileURLWithPath: url.path)
		} else if path.hasPrefix("/") || path.hasPrefix("~") {
			self = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
		} else if path.contains("://") {
			throw OSAXError(-1700, "\(path) isn’t a file.")
		} else if path.contains(":") {
			self = URL(fileURLWithPath: try URL.posixPath(fromHFSPath: path))
		} else {
			throw OSAXError.coercionFailed
		}
	}

	/// A path with nothing to say where it starts: no `/` or `~/` at the front, not a URL, and not an HFS path, whose
	/// first part is a mounted volume's name. (A name with a colon, such as "Notes: 2024.txt", which is fine in a
	/// file name, was taken for an HFS path on a volume "Notes".) A name that only starts with `~` is a name too
	/// (`~`, `~backup`, Office's `~$Budget.xlsx`): `~` was the home folder, whatever the folder, so
	/// `fileremove {"~"} from f` deleted it.
	public static func isRelativeScriptPath(_ path: String) -> Bool {
		if path.hasPrefix("/") || path.hasPrefix("~/") { return false }
		if path.hasPrefix("~") { return true }
		guard path.contains(":") else { return true }
		if path.lowercased().hasPrefix("file:") || path.contains("://") { return false }
		return !isVolumeName(String(path.prefix { $0 != ":" }))
	}

	/// Whether a volume by that name is mounted: the startup disk (in any case, as HFS paths are read) or one in
	/// /Volumes.
	static func isVolumeName(_ name: String) -> Bool {
		guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return false }
		let startup = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName
		if let startup, name.caseInsensitiveCompare(startup) == .orderedSame { return true }
		return FileManager.default.fileExists(atPath: "/Volumes/" + name)
	}

	/// Converts `"Volume:folder:file"` to `"/folder/file"` (startup volume) or `"/Volumes/Volume/folder/file"`. As
	/// in HFS, `::` is the parent folder (`Volume:a::b` is `b` on the volume); `.` and `..` are names, not folders
	/// (-1700), and so is a missing volume name.
	static func posixPath(fromHFSPath hfsPath: String) throws -> String {
		var components = hfsPath.split(separator: ":", omittingEmptySubsequences: false).map {
			$0.replacingOccurrences(of: "/", with: ":")
		}
		if components.last == "" {
			components.removeLast()
		}
		let volume = components.removeFirst()
		guard !volume.isEmpty else {
			throw OSAXError(-1700, "An HFS path starts with the volume’s name.")
		}
		// As for folders (`..:etc:hosts` was /Volumes/../etc/hosts).
		guard volume != ".", volume != ".." else {
			throw OSAXError(-1700, "HFS paths go up a folder with “::”, not “..”.")
		}
		var folders: [String] = []
		for component in components {
			if component.isEmpty {
				// `a::b`: each extra colon goes up one folder.
				guard !folders.isEmpty else { throw OSAXError(-1700, "\(hfsPath) goes above its volume.") }
				folders.removeLast()
			} else if component == "." || component == ".." {
				throw OSAXError(-1700, "HFS paths go up a folder with “::”, not “..”.")
			} else {
				folders.append(component)
			}
		}
		let startupVolume = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName
		let isStartup = startupVolume.map { volume.caseInsensitiveCompare($0) == .orderedSame } ?? false
		let root = isStartup ? "" : "/Volumes/\(volume)"
		return root + "/" + folders.joined(separator: "/")
	}
}

// MARK: - Creating events

private let eventCreationLock = NSLock()

extension NSAppleEventDescriptor {
	/// Creates an Apple event with no target, e.g. to pass straight to a dispatcher.
	///
	/// Creation is serialized: each creation asks Launch Services about the current process, and several
	/// threads doing that at once can hang indefinitely (seen with parallel tests under `xcodebuild test`).
	public static func untargetedEvent(_ key: EventKey) -> NSAppleEventDescriptor {
		eventCreationLock.withLock {
			appleEvent(
				withEventClass: key.eventClass,
				eventID: key.eventID,
				targetDescriptor: nil,
				returnID: AEReturnID(kAutoGenerateReturnID),
				transactionID: AETransactionID(kAnyTransactionID)
			)
		}
	}
}
