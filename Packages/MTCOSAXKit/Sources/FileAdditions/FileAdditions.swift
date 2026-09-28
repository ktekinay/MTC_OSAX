import AppleEventCore
import Foundation

/// Satimage's "Satimage File Additions" suite (event class `SATI`).
/// Behavior recorded from SatimageOSAX in `Fixtures/FileAdditions`; where Satimage was broken, MTC_OSAX follows
/// the dictionary (`Fixtures/FileAdditionsFixes`, listed in Implemented/PLAN-FileAdditions.md).
///
/// Items can be given as aliases, file references, POSIX paths (with `~`), `file://` URLs or HFS paths.
public enum FileAdditions {
	/// - Parameter dialogs: shows the `navchoose` dialogs and the `navask save` alert; the app passes its AppKit
	///   implementation. Without one, those commands reply "event not handled".
	public static func commands(dialogs: (any FileDialogs)? = nil) -> [CommandDefinition] {
		[
			CommandDefinition("alias description for", code: "SATIALIS", handler: aliasDescription),
			CommandDefinition("URL info for", code: "SATIIURL", handler: urlInfo),
			CommandDefinition("absoluteURL", code: "SATIaURL", handler: absoluteURL),
			CommandDefinition("relativeURL", code: "SATIrURL", handler: relativeURL),
			CommandDefinition("list files", code: "SATIlsfl", handler: listFiles),
			CommandDefinition("glob", code: "SATIGlob", handler: glob),
			CommandDefinition("backup", code: "SATISYNC", handler: backup),
		] + dialogCommands(dialogs)
	}

	// MARK: Errors (numbers recorded from SatimageOSAX)

	static let notFound = OSAXError(-43) // fnfErr
	static let parameterError = OSAXError.parameterError // -50
}

// MARK: - Results

/// How `list files`, `glob` and `absoluteURL` return items, chosen with their `as` parameter.
enum ResultForm: Equatable {
	/// `fsrf`, what `list files` and `glob` return by default.
	case fileReference
	case alias
	/// A file URL descriptor (`furl`), for `as file` and `as «class furl»`, and for types that make no sense.
	case fileURL
	/// A URL as text, for `as Unicode text`, `as text` and `as string`; what `absoluteURL` returns by default.
	case urlText
	/// `as unix path`: the POSIX path.
	case posixPath
	/// `as path`: the URL's path, percent-encoded.
	case escapedPath

	init(_ request: AppleEventRequest, default defaultForm: ResultForm) {
		guard let descriptor = request.descriptor(for: "rtyp") else {
			self = defaultForm
			return
		}
		switch descriptor.descriptorType {
		case typeType:
			switch descriptor.typeCodeValue.fourCharString {
			case "alis": self = .alias
			case "fsrf": self = .fileReference
			case "utxt", "TEXT", "ctxt": self = .urlText
			default: self = .fileURL
			}
		case typeObjectSpecifier:
			// `unix path` and `path` are properties of the suite's `URL information` record.
			switch descriptor.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue.fourCharString {
			case "psxP": self = .posixPath
			case "FTPc": self = .escapedPath
			default: self = .fileURL
			}
		default:
			self = .fileURL
		}
	}

	/// An existing (or, except for aliases and file references, possibly missing) local item in this form.
	/// Folders get a trailing `/` in URLs and paths.
	func descriptor(for url: URL, isDirectory: Bool) throws -> NSAppleEventDescriptor {
		let fileURL = URL(fileURLWithPath: url.path, isDirectory: isDirectory)
		switch self {
		case .fileReference:
			return .fileReference(url) ?? NSAppleEventDescriptor(fileURL: fileURL)
		case .alias:
			guard let alias = NSAppleEventDescriptor.alias(url) else {
				throw FileAdditions.notFound
			}
			return alias
		case .fileURL:
			return NSAppleEventDescriptor(fileURL: fileURL)
		case .urlText:
			return NSAppleEventDescriptor(string: fileURL.absoluteString)
		case .posixPath:
			return NSAppleEventDescriptor(string: url.path + (isDirectory && url.path != "/" ? "/" : ""))
		case .escapedPath:
			return NSAppleEventDescriptor(string: FileItem.escapedPath(fileURL))
		}
	}
}

/// File system facts the commands need, read without following a final symbolic link unless asked.
enum FileItem {
	static func status(_ url: URL) -> stat? {
		var status = stat()
		return lstat(url.path, &status) == 0 ? status : nil
	}

	/// An item's device and inode, which tell whether two paths are the same item.
	struct Identity: Equatable {
		let device: dev_t
		let inode: ino_t

		init(_ status: stat) {
			device = status.st_dev
			inode = status.st_ino
		}
	}

	/// The identity of what a path leads to, following links; nil if nothing's there.
	static func identity(_ url: URL) -> Identity? {
		var status = stat()
		return stat(url.path, &status) == 0 ? Identity(status) : nil
	}

	static func isDirectory(_ url: URL) -> Bool {
		var directory: ObjCBool = false
		return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
	}

	static func isPackage(_ url: URL) -> Bool {
		(try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
	}

	/// Invisible: a name starting with `.`, or the hidden flag.
	static func isHidden(_ url: URL) -> Bool {
		url.lastPathComponent.hasPrefix(".") || (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
	}

	static func date(_ time: timespec) -> Date {
		Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
	}

	static func modificationDate(_ url: URL) -> Date? {
		(try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
	}

	/// The names in a folder in the order the file system lists them (as Satimage returned them), without `.`
	/// and `..`.
	static func names(in folder: URL) -> [String] {
		guard let directory = opendir(folder.path) else {
			return []
		}
		defer { closedir(directory) }
		var names: [String] = []
		while let entry = readdir(directory) {
			let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
				String(decoding: bytes.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
			}
			if name != "." && name != ".." {
				names.append(name)
			}
		}
		return names
	}

	/// The part of a URL after the scheme and host, percent-encoded as it is in the URL.
	static func escapedPath(_ url: URL) -> String {
		url.path(percentEncoded: true)
	}
}
