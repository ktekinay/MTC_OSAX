import AppKit
import AppleEventCore
import Foundation
import UniformTypeIdentifiers

/// `absoluteURL`, `relativeURL`, `URL info for` and `alias description for`.
extension FileAdditions {
	// MARK: absoluteURL

	static func absoluteURL(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		guard let descriptor = request.descriptor(for: Keyword.directObject) else {
			throw OSAXError.missingParameter
		}
		let base = try request.descriptor(for: "from").map { try scriptURL($0) }
		let form = ResultForm(request, default: .urlText)
		func convert(_ item: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
			try describe(resolve(scriptURL(item, relativeTo: base), against: base), as: form)
		}
		if descriptor.descriptorType == typeAEList {
			return try (0 ..< descriptor.numberOfItems).map { try convert(descriptor.atIndex($0 + 1)!) }.appleEventDescriptor
		}
		return try convert(descriptor)
	}

	/// A URL resolved against a base, with `.` and `..` segments removed. Error -1700 for a relative URL without
	/// a base.
	static func resolve(_ url: URL, against base: URL?) throws -> URL {
		if url.scheme != nil {
			return url.standardized
		}
		guard let base, let resolved = URL(string: url.relativeString, relativeTo: base)?.absoluteURL else {
			throw OSAXError.coercionFailed
		}
		return resolved.standardized
	}

	static func describe(_ url: URL, as form: ResultForm) throws -> NSAppleEventDescriptor {
		switch form {
		case .urlText:
			return NSAppleEventDescriptor(string: url.absoluteString)
		case .posixPath:
			return NSAppleEventDescriptor(string: url.path(percentEncoded: false))
		case .escapedPath:
			return NSAppleEventDescriptor(string: url.path(percentEncoded: true))
		case .alias, .fileReference:
			guard url.isLocalFile else {
				throw OSAXError.coercionFailed
			}
			return try form.descriptor(for: url, isDirectory: url.hasDirectoryPath)
		case .fileURL:
			// A file can't be a web page (SatimageOSAX made `http://x.com/a` a file `a` on the startup disk).
			guard url.isLocalFile else {
				throw OSAXError(-1700, "\(url.absoluteString) isn’t a file on this Mac.")
			}
			return NSAppleEventDescriptor(descriptorType: typeFileURL, data: Data(url.absoluteString.utf8))!
		}
	}

	/// A URL from a script: an alias or file reference, a POSIX path (a trailing `/` marks a folder; the disk isn't
	/// checked), a URL (possibly relative), or an HFS path.
	static func isText(_ descriptor: NSAppleEventDescriptor) -> Bool {
		[typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType)
	}

	/// With a base that isn't a file URL, text starting with `/` is a URL relative to the base, not a POSIX path.
	static func scriptURL(_ descriptor: NSAppleEventDescriptor, relativeTo base: URL? = nil) throws -> URL {
		guard isText(descriptor) else {
			guard let url = try descriptor.coerced(to: "furl").fileURLValue else {
				throw OSAXError.coercionFailed
			}
			return url
		}
		let text = try String(appleEventDescriptor: descriptor)
		if text.isEmpty {
			throw OSAXError(111) // As SatimageOSAX replied for an empty URL.
		}
		if base.map({ !$0.isFileURL }) == true, text.hasPrefix("/"),
		   let url = CFURLCreateWithString(nil, text as CFString, nil) as URL?
		{
			return url
		}
		if let url = existingHFSItem(text) {
			return url
		}
		if text.hasPrefix("/") || text.hasPrefix("~") {
			let path = (text as NSString).expandingTildeInPath
			return URL(fileURLWithPath: path, isDirectory: text.hasSuffix("/"))
		}
		if let url = CFURLCreateWithString(nil, text as CFString, nil) as URL? {
			if url.scheme == nil || !text.contains(" ") {
				return url
			}
		}
		if text.contains(":") {
			return try URL(scriptPath: text)
		}
		throw OSAXError.coercionFailed
	}

	/// An HFS path (`Volume:folder:file`) to an existing item. HFS paths also parse as URLs (with the volume name as
	/// the scheme), so only those naming an existing item are taken as paths.
	static func existingHFSItem(_ text: String) -> URL? {
		guard text.contains(":"), !text.contains("://"), !text.hasPrefix("/"), let url = try? URL(scriptPath: text),
		      FileItem.status(url) != nil
		else {
			return nil
		}
		return url
	}

	// MARK: relativeURL

	/// The shortest URL that leads from the base to the URL: a path relative to the base's folder, `""` for the
	/// base itself, `.` for its folder, or the whole URL when the scheme or host differ.
	static func relativeURL(_ request: AppleEventRequest) throws -> String {
		guard let targetDescriptor = request.descriptor(for: Keyword.directObject),
		      let baseDescriptor = request.descriptor(for: "from")
		else {
			throw OSAXError.missingParameter
		}
		let target = try resolve(scriptURL(targetDescriptor), against: nil)
		let base = try resolve(scriptURL(baseDescriptor), against: nil)
		return relative(target, from: base)
	}

	static func relative(_ target: URL, from base: URL) -> String {
		if target.absoluteString == base.absoluteString {
			return ""
		}
		guard target.scheme?.lowercased() == base.scheme?.lowercased(), target.host() == base.host(),
		      target.port == base.port, target.user() == base.user()
		else {
			return target.absoluteString
		}
		let basePath = base.path(percentEncoded: true)
		let baseFolder = basePath.split(separator: "/", omittingEmptySubsequences: false).dropLast().filter { !$0.isEmpty }
		var targetParts = target.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: false)
		if targetParts.first == "" {
			targetParts.removeFirst()
		}
		let name = targetParts.popLast() ?? ""
		let common = zip(baseFolder, targetParts).prefix { $0 == $1 }.count
		var result = String(repeating: "../", count: baseFolder.count - common)
		for part in targetParts.dropFirst(common) {
			result += part + "/"
		}
		result += name
		if result.isEmpty {
			result = "."
		}
		if let query = target.query(percentEncoded: true) {
			result += "?" + query
		}
		if let fragment = target.fragment(percentEncoded: true) {
			result += "#" + fragment
		}
		return result
	}

	// MARK: alias description for

	/// The original item of an alias file or symbolic link, or the item itself. Folders end with `/` when the
	/// reference says it's a folder (an alias, or a path ending with `/`) or a link leads to one; the disk isn't
	/// checked otherwise, as in SatimageOSAX.
	static func aliasDescription(_ request: AppleEventRequest) throws -> String {
		guard let descriptor = request.descriptor(for: Keyword.directObject) else {
			throw OSAXError.missingParameter
		}
		let url = try scriptURL(descriptor)
		guard url.isFileURL else {
			throw OSAXError.coercionFailed
		}
		var isDirectory = url.hasDirectoryPath
		var original = url
		let isLink = FileItem.status(url).map { ($0.st_mode & S_IFMT) == S_IFLNK } == true
		if isLink || (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true,
		   // Never a dialog (the app is faceless) or mounting a server volume the alias points to.
		   let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting])
		{
			original = resolved
			isDirectory = FileItem.isDirectory(resolved)
		}
		let path = realPath(original.path) ?? original.path
		return path + (isDirectory && path != "/" ? "/" : "")
	}

	static func realPath(_ path: String) -> String? {
		guard let real = realpath(path, nil) else {
			return nil
		}
		defer { free(real) }
		return String(cString: real)
	}

	// MARK: URL info for

	static func urlInfo(_ request: AppleEventRequest) throws -> AppleEventRecord {
		guard let descriptor = request.descriptor(for: Keyword.directObject) else {
			throw OSAXError.missingParameter
		}
		let withSize = try request.parameter("ptsz", default: false)
		if isText(descriptor), let text = try? String(appleEventDescriptor: descriptor), !text.hasPrefix("/"),
		   !text.hasPrefix("~"), !text.lowercased().hasPrefix("file:")
		{
			if text.isEmpty {
				return remoteInfo(URLParts(""))
			}
			if let url = existingHFSItem(text) {
				return try localInfo(url, withSize: withSize)
			}
			if CFURLCreateWithString(nil, text as CFString, nil) != nil {
				return remoteInfo(URLParts(text))
			}
			guard text.contains(":"), let url = try? URL(scriptPath: text) else {
				throw OSAXError.coercionFailed
			}
			return try localInfo(url, withSize: withSize)
		}
		let url = try URL(appleEventDescriptor: descriptor)
		return try localInfo(url, withSize: withSize)
	}

	/// Like Standard Additions' `info for`, followed by the URL's scheme and paths. Symbolic links are followed for
	/// the item's information, but the paths are the link's.
	static func localInfo(_ url: URL, withSize: Bool) throws -> AppleEventRecord {
		guard FileItem.status(url) != nil, let realPath = realPath(url.path) else {
			throw notFound
		}
		let item = URL(fileURLWithPath: realPath)
		let keys: Set<URLResourceKey> = [
			.creationDateKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
			.hasHiddenExtensionKey, .isAliasFileKey, .localizedTypeDescriptionKey, .contentTypeKey, .isUserImmutableKey,
		]
		// (Foundation's errors would reach the script as -2700 with Foundation's English text.)
		let values: URLResourceValues
		do {
			values = try item.resourceValues(forKeys: keys)
		} catch {
			throw OSAXError.file(error, "read the information of “\(item.lastPathComponent)”")
		}
		let isDirectory = values.isDirectory == true
		let isPackage = values.isPackage == true
		let name = item.lastPathComponent
		let missing = NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "msng"))
		let finderInfo = FinderInfo(item)

		var record = AppleEventRecord([
			"pnam": name,
			"ascd": values.creationDate ?? Date(),
			"asmo": values.contentModificationDate ?? Date(),
			"ptsz": withSize ? totalSize(item).compDescriptor : missing,
			"asdr": isDirectory,
			"alis": values.isAliasFile == true,
			"ispk": isPackage,
			"pvis": !(values.isHidden == true || name.hasPrefix(".")),
			"hidx": values.hasHiddenExtension == true,
			"nmxt": item.pathExtension.isEmpty ? missing : NSAppleEventDescriptor(string: item.pathExtension),
			"dnam": name,
		])
		let application = NSWorkspace.shared.urlForApplication(toOpen: item).flatMap(NSAppleEventDescriptor.alias) ?? missing
		let kind = values.localizedTypeDescription ?? ""
		let typeIdentifier = values.contentType?.identifier ?? ""
		if isPackage {
			let info = Bundle(url: item)?.infoDictionary ?? [:]
			let text = { (key: String) in (info[key] as? String).map(NSAppleEventDescriptor.init(string:)) ?? missing }
			let isApplication = values.contentType?.conforms(to: .application) == true
			record.fields += [
				("cfbn", text("CFBundleName")),
				("asda", application),
				("kind", kind),
				("assv", text("CFBundleShortVersionString")),
				("aslv", text("CFBundleGetInfoString")),
				("bnid", text("CFBundleIdentifier")),
				("asty", FinderInfo.code(info["CFBundlePackageType"] as? String ?? (isApplication ? "APPL" : nil))),
				("asct", FinderInfo.code(info["CFBundleSignature"] as? String ?? (isApplication ? "????" : nil))),
				("utid", typeIdentifier),
				("bzst", false),
			]
		} else if isDirectory {
			record.fields += [
				("asda", application),
				("kind", kind),
				("asfw", NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "qdrt"), data: Data(count: 8))!),
				("asty", finderInfo.type),
				("asct", finderInfo.creator),
			]
		} else {
			record.fields += [
				("asda", application),
				("kind", kind),
				("asty", finderInfo.type),
				("asct", finderInfo.creator),
				("utid", typeIdentifier),
				("aslk", values.isUserImmutable == true),
				("bzst", false),
				("assv", FinderInfo.text("")),
				("aslv", FinderInfo.text("")),
			]
		}
		let fileURL = URL(fileURLWithPath: url.path, isDirectory: isDirectory)
		record.fields += [
			("pusc", "file"),
			("psxP", url.path),
			("FTPc", fileURL.path(percentEncoded: true)),
		]
		return record
	}

	/// The logical size of a file, or of everything in a folder.
	static func totalSize(_ url: URL) -> Int64 {
		guard FileItem.isDirectory(url) else {
			return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
		}
		let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
		var total: Int64 = 0
		while let item = enumerator?.nextObject() as? URL {
			let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
			if values?.isRegularFile == true {
				total += Int64(values?.fileSize ?? 0)
			}
		}
		return total
	}

	/// The parts of a URL that isn't a local file, as Satimage reported them.
	static func remoteInfo(_ parts: URLParts) -> AppleEventRecord {
		let missing = NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "msng"))
		var record = AppleEventRecord([:])
		if let scheme = parts.scheme {
			record.fields.append(("pusc", scheme))
		}
		if let host = parts.host {
			record.fields.append(("HOST", host))
		}
		if let user = parts.user {
			record.fields.append(("RAun", user))
		}
		if let password = parts.password {
			record.fields.append(("RApw", password))
		}
		if parts.hasPath {
			record.fields.append(("psxP", parts.path.removingPercentEncoding ?? parts.path))
			record.fields.append(("FTPc", parts.path))
		}
		if let parameters = parts.parameters {
			record.fields.append(("Upar", parameters))
		}
		if let query = parts.query {
			record.fields.append(("Quer", query))
		}
		if let fragment = parts.fragment {
			record.fields.append(("Ufra", fragment))
		}
		let name = parts.hasPath ? parts.name : ""
		let pathExtension = (name as NSString).pathExtension
		record.fields.append(("pnam", name))
		record.fields.append(("nmxt", pathExtension.isEmpty ? missing : NSAppleEventDescriptor(string: pathExtension)))
		if !pathExtension.isEmpty, let type = UTType(tag: pathExtension, tagClass: .filenameExtension, conformingTo: nil) {
			record.fields.append(("utid", type.identifier))
		}
		record.fields += [
			("asty", FinderInfo.text("")),
			("asct", FinderInfo.text("")),
			("asdr", parts.hasPath && parts.path.hasSuffix("/")),
			("ispk", false),
			("alis", false),
		]
		return record
	}
}

/// A URL split into its parts (RFC 1808, which has `;parameters`), percent-encoded as written.
struct URLParts {
	var scheme: String?
	var user: String?
	var password: String?
	var host: String?
	var path = ""
	var parameters: String?
	var query: String?
	var fragment: String?
	/// Whether the URL has a path, possibly empty: a relative URL, or one with a host or a path starting with `/`.
	/// `mailto:` URLs don't.
	var hasPath = false

	init(_ text: String) {
		var rest = Substring(text)
		if let hash = rest.firstIndex(of: "#") {
			fragment = String(rest[rest.index(after: hash)...])
			rest = rest[..<hash]
		}
		if let question = rest.firstIndex(of: "?") {
			query = String(rest[rest.index(after: question)...])
			rest = rest[..<question]
		}
		if let colon = rest.firstIndex(of: ":"), !rest[..<colon].containsASCII("/"), !rest[..<colon].isEmpty {
			scheme = String(rest[..<colon])
			rest = rest[rest.index(after: colon)...]
		}
		var hasNetworkLocation = false
		if rest.hasPrefix("//") {
			hasNetworkLocation = true
			rest = rest.dropFirst(2)
			let end = rest.firstIndex(of: "/") ?? rest.endIndex
			var location = rest[..<end]
			rest = rest[end...]
			if let at = location.lastIndex(of: "@") {
				let userInfo = location[..<at]
				location = location[location.index(after: at)...]
				if let colon = userInfo.firstIndex(of: ":") {
					user = String(userInfo[..<colon])
					password = String(userInfo[userInfo.index(after: colon)...])
				} else {
					user = String(userInfo)
				}
			}
			if let colon = location.lastIndex(of: ":"), !location[colon...].contains("]") {
				location = location[..<colon]
			}
			host = String(location)
		}
		if let semicolon = rest.firstIndex(of: ";") {
			parameters = String(rest[rest.index(after: semicolon)...])
			rest = rest[..<semicolon]
		}
		path = String(rest)
		hasPath = hasNetworkLocation || path.hasPrefix("/") || (scheme == nil && !path.isEmpty)
	}

	/// The last path component, decoded; for `/dir/`, `dir`.
	var name: String {
		let component = path.split(separator: "/").last.map(String.init) ?? ""
		return component.removingPercentEncoding ?? component
	}
}

/// A file's classic type and creator codes, from its Finder information; four zero bytes when it has none.
struct FinderInfo {
	var type: NSAppleEventDescriptor
	var creator: NSAppleEventDescriptor

	init(_ url: URL) {
		var bytes = [UInt8](repeating: 0, count: 32)
		let length = getxattr(url.path, "com.apple.FinderInfo", &bytes, bytes.count, 0, 0)
		if length < 8 {
			bytes = [UInt8](repeating: 0, count: 32)
		}
		type = Self.text(Data(bytes[0 ..< 4]))
		creator = Self.text(Data(bytes[4 ..< 8]))
	}

	/// Text in Mac OS Roman (`TEXT`), as `info for` returns type and creator codes.
	static func text(_ data: Data) -> NSAppleEventDescriptor {
		NSAppleEventDescriptor(descriptorType: typeChar, data: data)!
	}

	static func text(_ string: String) -> NSAppleEventDescriptor {
		text(string.data(using: .macOSRoman) ?? Data())
	}

	/// A four-character code as text, or four zero bytes.
	static func code(_ code: String?) -> NSAppleEventDescriptor {
		guard let code, let data = code.data(using: .macOSRoman), data.count == 4 else {
			return text(Data(count: 4))
		}
		return text(data)
	}
}

extension Int64 {
	/// A 64-bit integer descriptor (`comp`), as `info for` returns sizes.
	var compDescriptor: NSAppleEventDescriptor {
		withUnsafeBytes(of: littleEndian) { NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "comp"), data: Data($0))! }
	}
}
