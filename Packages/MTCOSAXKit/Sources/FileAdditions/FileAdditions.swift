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
