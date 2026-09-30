import AppleEventCore
import Darwin
import Foundation

/// Satimage's "Files and folders suite" and "Symlink suite" (event class `Quom`, from its Files.osax).
/// Behavior recorded from SatimageOSAX in `Fixtures/FilesAndFolders`; where Satimage was broken, MTC_OSAX follows
/// the dictionary (`Fixtures/FilesAndFoldersFixes`, listed in Implemented/PLAN-FilesAndFolders.md).
///
/// Files can be given as aliases, file references, POSIX paths (with `~`), `file://` URLs or HFS paths. Results are
/// POSIX paths as text, with a trailing `/` for folders, as Satimage returns them.
public enum FilesAndFolders {
	@MainActor
	public static func commands() -> [CommandDefinition] {
		[
			CommandDefinition("filegetname", code: "QuomGFNa") { request in
				try Paths(request, keyword: Keyword.directObject).map { $0.lastPathComponent }
			},
			CommandDefinition("filenew", code: "QuomNewF", handler: fileNew),
			CommandDefinition("mkdir", code: "QuomMkDi", handler: makeDirectory),
			CommandDefinition("filerename", code: "QuomRenF", handler: rename),
			CommandDefinition("chmod", code: "Quomchmd", handler: changeMode),
			CommandDefinition("filecopy", code: "QuomCopy") { try copyOrMove($0, move: false) },
			CommandDefinition("filemove", code: "QuomMove") { try copyOrMove($0, move: true) },
			CommandDefinition("fileremove", code: "QuomRemo", handler: remove),
			CommandDefinition("mkstemp", code: "Quommkst") { try makeTemporary($0, folder: false) },
			CommandDefinition("mkdtemp", code: "Quommkdt") { try makeTemporary($0, folder: true) },
			CommandDefinition("create symlink", code: "QuomSymL", handler: createSymlink),
			CommandDefinition("testsymlink", code: "QuomIsSy") { request in
				FileItem.isSymlink(try request.requiredDirectParameter(as: URL.self))
			},
			CommandDefinition("readlink", code: "Quomrdsy") { request in
				let url = try request.requiredDirectParameter(as: URL.self)
				guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
					throw invalidInput
				}
				return destination
			},
		]
	}

	// MARK: Errors (numbers recorded from SatimageOSAX)

	static let notFound = OSAXError(-43) // fnfErr
	static let alreadyExists = OSAXError(-48) // dupFNErr
	static let invalidInput = OSAXError(-1)
	static let notAllowedTogether = OSAXError(-50) // paramErr

	/// A POSIX error number as Satimage returned it for `mkdir` (e.g. 17 for EEXIST).
	static func posixError(_ code: Int32) -> OSAXError {
		OSAXError(Int(code))
	}

	// MARK: Paths

	/// The text Satimage returns for an item: its POSIX path, with a trailing `/` for a folder.
	static func result(_ url: URL, folder: Bool? = nil) -> String {
		let isFolder = folder ?? FileItem.isDirectory(url)
		return url.path + (isFolder && url.path != "/" ? "/" : "")
	}

	/// The file for `directory`, or `directory/name` when `name` is given.
	static func destination(_ request: AppleEventRequest) throws -> URL {
		let base = try request.requiredDirectParameter(as: URL.self)
		guard let name = try nameParameter(request) else {
			return base
		}
		return base.appendingPathComponent(name)
	}

	/// The `name` parameter: one name, not a path, so a name that comes from a document can't reach outside the
	/// folder. -1 with a message otherwise (SatimageOSAX took `sub/file` as a path).
	static func nameParameter(_ request: AppleEventRequest) throws -> String? {
		guard let name = try request.parameter("pnam", as: String.self) else {
			return nil
		}
		try requireValidName(name)
		return name
	}

	/// -1 with a message for a name that isn't one name: empty, with `/` or NUL (which became `%00` in the file
	/// name), or `.` or `..`.
	static func requireValidName(_ name: String) throws {
		guard !name.contains("/"), !name.contains("\0"), isName(name) else {
			throw OSAXError(-1, "A name can’t be empty, contain “/” or be “.” or “..”. To use a subfolder, give its path as the folder instead.")
		}
	}

	/// Whether a path's last part is a name: not empty, “.” or “..”, which say where a folder is instead.
	static func isName(_ name: String) -> Bool {
		!name.isEmpty && name != "." && name != ".." && name != "/"
	}

	/// -1 unless a path ends in a name. An item made from other parameters (a path's last part) needs one:
	/// `filecopy "a/.." to f` would otherwise be `f/..`, the folder above `f`, which `with replacing` deleted. So
	/// does an item to delete, as with the shell's `rm`.
	static func requireName(_ url: URL, orNameParameter: Bool = true) throws {
		guard isName(url.lastPathComponent) else {
			throw OSAXError(-1, "“\(url.path)” doesn’t end in a name. Give a path that ends in the item’s name"
				+ (orNameParameter ? ", or a name." : "."))
		}
	}

	// MARK: filenew, mkdir, filerename

	/// Creates an empty file. Missing folders on the way are always created (Satimage ignored `recursively`).
	/// An existing item: -48.
	static func fileNew(_ request: AppleEventRequest) throws -> (any AppleEventEncodable)? {
		let url = try destination(request)
		_ = try request.parameter("RECU", default: false)
		guard !FileItem.exists(url) else {
			throw alreadyExists
		}
		do {
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		} catch {
			throw OSAXError.file(error, "make the folders for “\(url.lastPathComponent)”", fallback: notFound.number)
		}
		// Only if it's still not there (a file made since the check was overwritten).
		let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o666)
		guard descriptor >= 0 else {
			throw errno == EEXIST ? alreadyExists : invalidInput
		}
		close(descriptor)
		return result(url, folder: false)
	}

	/// Creates a folder (and missing folders on the way unless `recursively` is false). Errors are POSIX numbers,
	/// as in Satimage: 17 if it exists, 2 if a folder on the way is missing.
	static func makeDirectory(_ request: AppleEventRequest) throws -> (any AppleEventEncodable)? {
		let url = try destination(request)
		let recursively = try request.parameter("RECU", default: true)
		guard !FileItem.exists(url) else {
			throw posixError(EEXIST)
		}
		if recursively {
			do {
				try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			} catch {
				// The system's reason (a full disk was reported as no permission); guessed only without one.
				let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
				if let underlying, underlying.domain == NSPOSIXErrorDomain {
					throw posixError(Int32(underlying.code))
				}
				throw posixError(FileItem.isDirectory(url.deletingLastPathComponent()) ? EACCES : ENOTDIR)
			}
		} else if Darwin.mkdir(url.path, 0o777) != 0 {
			throw posixError(errno)
		}
		return result(url, folder: true)
	}

	/// Renames in place. The new name can't contain `/` (-1); an existing item with that name: -48. A new name that
	/// differs only in case (the same item on a case-insensitive volume) renames it (SatimageOSAX gave -48).
	static func rename(_ request: AppleEventRequest) throws -> (any AppleEventEncodable)? {
		let url = try request.requiredDirectParameter(as: URL.self)
		let name = try request.requiredParameter("to  ", as: String.self)
		// `/` or nothing is -1 without a message, as in SatimageOSAX; `.`, `..` (which was -48, the folder above
		// existing) and NUL as for the other commands' names.
		guard !name.contains("/"), !name.isEmpty else {
			throw invalidInput
		}
		try requireValidName(name)
		guard FileItem.exists(url) else {
			throw notFound
		}
		let renamed = url.deletingLastPathComponent().appendingPathComponent(name)
		if FileItem.exists(renamed), FileItem.isSameEntry(url, renamed) {
			guard Darwin.rename(url.path, renamed.path) == 0 else { throw invalidInput }
			return result(renamed, folder: false)
		}
		guard !FileItem.exists(renamed) else {
			throw alreadyExists
		}
		do {
			try FileManager.default.moveItem(at: url, to: renamed)
		} catch {
			throw invalidInput
		}
		// Satimage returns a renamed folder's path without a trailing slash.
		return result(renamed, folder: false)
	}

	// MARK: chmod

	/// Returns the permissions before any change, as octal text ("644"). `to` sets them from octal text ("0755" and
	/// "1755" are accepted; only the permission bits are shown). Invalid text or a missing item: -1.
	static func changeMode(_ request: AppleEventRequest) throws -> (any AppleEventEncodable)? {
		let url = try request.requiredDirectParameter(as: URL.self)
		var status = stat()
		guard stat(url.path, &status) == 0 else {
			throw invalidInput
		}
		let previous = String(status.st_mode & 0o777, radix: 8)
		if let text = try request.parameter("to  ", as: String.self) {
			guard let mode = mode_t(text, radix: 8), mode <= 0o7777, Darwin.chmod(url.path, mode) == 0 else {
				throw invalidInput
			}
		}
		return previous
	}

	// MARK: filecopy, filemove

	static func copyOrMove(_ request: AppleEventRequest, move: Bool) throws -> (any AppleEventEncodable)? {
		let sources = try Paths(request, keyword: Keyword.directObject)
		let replacing = try request.parameter("Repl", default: false)
		_ = try request.parameter("full", default: false) // FileManager copies attributes either way.
		let filePath = try request.parameter("into", as: URL.self) ?? request.parameter("intO", as: URL.self)
		let folder = try request.parameter("to  ", as: URL.self)
		let name = try nameParameter(request)

		if case .list = sources, filePath != nil || name != nil {
			throw notAllowedTogether // name and filepath are only for one item
		}
		guard filePath != nil || folder != nil else {
			throw OSAXError.missingParameter
		}

		return try sources.map(done: move ? "moved" : "copied") { source -> String in
			guard FileItem.exists(source) else {
				throw notFound
			}
			let target = filePath ?? folder!.appendingPathComponent(name ?? source.lastPathComponent)
			try requireName(target)
			guard FileItem.isDirectory(target.deletingLastPathComponent()) else {
				throw notFound
			}
			let isFolder = FileItem.isDirectory(source)
			// The target is the source itself (the same path, or a case variant): removing the "existing" target
			// would delete the source. Moving to another spelling renames it (SatimageOSAX gave -48); otherwise it's
			// -48 without `replacing` and left as it is with it, as in SatimageOSAX.
			if FileItem.exists(target), FileItem.isSameEntry(source, target) {
				if move, source.path != target.path {
					guard Darwin.rename(source.path, target.path) == 0 else { throw posixError(errno) }
					return result(target, folder: isFolder)
				}
				guard replacing else { throw alreadyExists }
				return result(source, folder: isFolder)
			}
			// A link to the target itself (a folder of links from elsewhere can hold one): replacing the target with
			// it deleted what it points at, leaving a link to nothing.
			if FileItem.isSymlink(source), FileItem.exists(target), !FileItem.isSymlink(target),
			   let identity = FileItem.identity(source), identity == FileItem.identity(target)
			{
				throw OSAXError(-1, "“\(source.path)” is a link to “\(target.path)”, which it would replace.")
			}
			guard FileItem.exists(target) else {
				do {
					if move {
						try FileManager.default.moveItem(at: source, to: target)
					} else {
						try FileManager.default.copyItem(at: source, to: target)
					}
				} catch {
					throw OSAXError(-1, OSAXError.file(error, "\(move ? "move" : "copy") “\(source.lastPathComponent)”").message)
				}
				return result(target, folder: isFolder)
			}
			guard replacing else {
				throw alreadyExists
			}
			try replace(target, from: source, move: move)
			return result(target, folder: isFolder)
		}
	}

	/// `with replacing`: the new item is made under a temporary name next to the old one first, so if the copy or
	/// move fails, or the old item can't be removed, the old item (and for a move, the source) is left as it was.
	static func replace(_ target: URL, from source: URL, move: Bool) throws {
		let manager = FileManager.default
		let temporary = target.deletingLastPathComponent().appendingPathComponent(FileItem.temporaryName())
		do {
			if move {
				try manager.moveItem(at: source, to: temporary)
			} else {
				try manager.copyItem(at: source, to: temporary)
			}
		} catch {
			throw OSAXError(-1, "Couldn’t \(move ? "move" : "copy") “\(source.lastPathComponent)”: \(error.localizedDescription)")
		}
		do {
			try manager.removeItem(at: target)
		} catch {
			if move {
				try? manager.moveItem(at: temporary, to: source)
			} else {
				try? manager.removeItem(at: temporary)
			}
			throw OSAXError(-1, "Couldn’t replace “\(target.lastPathComponent)”: \(error.localizedDescription)")
		}
		guard Darwin.rename(temporary.path, target.path) == 0 else {
			throw OSAXError(-1, "Couldn’t name the new item “\(target.lastPathComponent)”; it’s at \(temporary.path).")
		}
	}

	// MARK: fileremove

	/// Deletes permanently and returns how many items were deleted. With `filesonly`, a folder stands for the files
	/// directly in it (subfolders and their contents stay), optionally only those modified `after` or `before` a
	/// date (dates need `filesonly`: -1). Locked files are unlocked first unless `locked files` is false.
	/// (Satimage always reported 0 with `filesonly`.)
	static func remove(_ request: AppleEventRequest) throws -> (any AppleEventEncodable)? {
		let items = try Paths(request, keyword: Keyword.directObject)
		let filesOnly = try request.parameter("FOnl", default: false)
		let after = try request.parameter("afte", as: Date.self)
		let before = try request.parameter("befo", as: Date.self)
		let lockedFiles = try request.parameter("CUnl", default: true)
		_ = try request.parameter("BUnl", default: true) // Unlinking a busy file works anyway on macOS.
		guard filesOnly || (after == nil && before == nil) else {
			throw invalidInput
		}

		var urls: [URL]
		switch items {
		case let .single(url): urls = [url]
		case let .list(list): urls = list
		}
		// `x/..` or `.` (in a `from` folder) would delete the folder it is.
		try urls.forEach { try requireName($0, orNameParameter: false) }
		guard urls.allSatisfy(FileItem.exists) else {
			throw notFound
		}
		if filesOnly {
			urls = urls.flatMap { url -> [URL] in
				guard FileItem.isDirectory(url) else { return [url] }
				let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
				return contents.filter { !FileItem.isDirectory($0) }
			}
			urls = urls.filter { url in
				let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
				return (after.map { modified > $0 } ?? true) && (before.map { modified < $0 } ?? true)
			}
		}
		var removed = 0
		for url in urls {
			if lockedFiles {
				unlock(url)
			}
			do {
				try FileManager.default.removeItem(at: url)
				removed += 1
			} catch {
				// Still -1, but saying which item, why, and how many were already deleted (the count was lost).
				let reason = OSAXError.file(error, "delete “\(url.lastPathComponent)”").message ?? ""
				throw OSAXError(-1, urls.count > 1 ? "\(reason) \(removed) of the \(urls.count) items were deleted before it." : reason)
			}
		}
		return removed
	}

	/// Clears the user and system immutable flags (a Finder-locked file), recursively for folders. A link's own
	/// flags are changed (chflags would unlock what it points to, which isn't being removed); the system flag needs
	/// root, so without it only the user flag is cleared.
	private static func unlock(_ url: URL) {
		// What's in it only for a real folder: through a link to one, every locked file under the folder it pointed
		// to was unlocked, though only the link was deleted.
		let isFolder = FileItem.status(url).map { ($0.st_mode & S_IFMT) == S_IFDIR } == true
		let paths = [url.path] + (isFolder ? FileManager.default.enumerator(atPath: url.path)?.compactMap {
			($0 as? String).map { url.appendingPathComponent($0).path }
		} ?? [] : [])
		let locks = UInt32(UF_IMMUTABLE | SF_IMMUTABLE)
		for path in paths {
			var status = stat()
			if lstat(path, &status) == 0, status.st_flags & locks != 0, lchflags(path, status.st_flags & ~locks) != 0 {
				lchflags(path, status.st_flags & ~UInt32(UF_IMMUTABLE))
			}
		}
	}

	// MARK: mkstemp, mkdtemp

	/// A new file (mkstemp) or folder (mkdtemp) named prefix + random letters and digits + suffix. The template is
	/// `name` in the folder given, or the path given. `suffix` (files only) is how many of the name's last
	/// characters follow the random part; `wildcards` (default 6) how many random characters; `mode` octal text
	/// (default "666" for files, "777" for folders, less the umask). (Satimage ignored `wildcards` for folders.)
	static func makeTemporary(_ request: AppleEventRequest, folder: Bool) throws -> (any AppleEventEncodable)? {
		let base = try request.requiredDirectParameter(as: URL.self)
		let name = try nameParameter(request)
		let template = name.map { base.appendingPathComponent($0) } ?? base
		let suffixLength = folder ? 0 : try request.parameter("suff", default: 0)
		let wildcards = try request.parameter("wild", default: 6)
		let modeText = try request.parameter("Mode", default: folder ? "777" : "666")
		guard let mode = mode_t(modeText, radix: 8), mode <= 0o7777, wildcards >= 0 else {
			throw invalidInput
		}
		// More can't fit in a name (and 2147483647 made a 2 GB string).
		guard wildcards <= NAME_MAX else {
			throw OSAXError(-1, "A name can have at most \(NAME_MAX) wildcards.")
		}

		let fullName = template.lastPathComponent
		guard suffixLength >= 0, suffixLength <= fullName.count else {
			throw invalidInput
		}
		let prefix = String(fullName.dropLast(suffixLength))
		let suffix = String(fullName.suffix(suffixLength))
		let created = try createUnique(in: template.deletingLastPathComponent(), prefix: prefix, randomCount: wildcards, suffix: suffix,
		                               folder: folder, mode: mode)
		return result(URL(fileURLWithPath: created), folder: folder)
	}

	/// Creates a file or folder named prefix + random letters and digits + suffix that didn't exist, with `mode` less
	/// the umask; its path. The system applies the umask as it creates it (reading the umask meant setting the whole
	/// process's to 0 for a moment); setuid, setgid and sticky bits, which creating doesn't set, are added after.
	/// (mkstemps and mkdtemp replace every X at the end of their template, so a prefix ending in X lost it.)
	static func createUnique(in folder: URL, prefix: String, randomCount: Int, suffix: String, folder isFolder: Bool,
	                         mode: mode_t = 0o600) throws -> String
	{
		let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
		for _ in 0 ..< (randomCount == 0 ? 1 : 1000) {
			let random = String((0 ..< randomCount).map { _ in characters.randomElement()! })
			let path = folder.appendingPathComponent(prefix + random + suffix).path
			var created = false
			if isFolder {
				created = Darwin.mkdir(path, mode & 0o777) == 0
			} else {
				let descriptor = open(path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, mode & 0o777)
				if descriptor >= 0 {
					close(descriptor)
					created = true
				}
			}
			if created {
				var status = stat()
				if mode & 0o7000 != 0, lstat(path, &status) == 0 {
					Darwin.chmod(path, (status.st_mode & 0o777) | (mode & 0o7000))
				}
				return path
			}
			guard errno == EEXIST else { throw posixError(errno) }
		}
		throw posixError(EEXIST)
	}

	// MARK: create symlink

	/// Creates a symbolic link in the `in` folder, named `name` or after the target. A target given as text is kept
	/// as written (so relative targets stay relative); a file reference or alias becomes its absolute path.
	/// An existing link is replaced unless `replacing` is false (-48); any other existing item: -48.
	static func createSymlink(_ request: AppleEventRequest) throws -> (any AppleEventEncodable)? {
		let targetDescriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let target: String
		if let text = try? String(appleEventDescriptor: targetDescriptor), !text.hasPrefix("file://"),
		   targetDescriptor.descriptorType != typeFileURL, targetDescriptor.descriptorType != typeAlias
		{
			target = text.hasPrefix("~") ? (text as NSString).expandingTildeInPath : text
		} else {
			target = try URL(appleEventDescriptor: targetDescriptor).path
		}
		let folder = try request.requiredParameter("in  ", as: URL.self)
		let name = try nameParameter(request) ?? (target as NSString).lastPathComponent
		guard isName(name) else {
			throw OSAXError(-1, "“\(target)” doesn’t end in a name for the link. Give a name.")
		}
		let replacing = try request.parameter("Repl", default: true)
		let link = folder.appendingPathComponent(name)

		if FileItem.exists(link) {
			guard FileItem.isSymlink(link), replacing else {
				throw alreadyExists
			}
			try? FileManager.default.removeItem(at: link)
		}
		do {
			try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
		} catch {
			// A missing folder is still -43; anything else (no permission, …) its own number, not -43.
			throw OSAXError.file(error, "make the link “\(link.lastPathComponent)”", fallback: notFound.number)
		}
		return nil
	}
}

/// One file or a list of files, from a parameter; relative paths are resolved against the `from` parameter.
enum Paths {
	case single(URL)
	case list([URL])

	init(_ request: AppleEventRequest, keyword: String) throws {
		guard let descriptor = request.descriptor(for: keyword) else {
			throw OSAXError.missingParameter
		}
		let base = try request.parameter("from", as: URL.self)
		func url(_ item: NSAppleEventDescriptor) throws -> URL {
			if let base, let text = try? String(appleEventDescriptor: item), URL.isRelativeScriptPath(text) {
				return try URL(scriptPath: text, relativeTo: base)
			}
			return try URL(appleEventDescriptor: item)
		}
		if descriptor.descriptorType == typeAEList {
			self = .list(try (0 ..< descriptor.numberOfItems).map { try url(descriptor.atIndex($0 + 1)!) })
		} else {
			self = .single(try url(descriptor))
		}
	}

	/// One result per path: a single value, or a list.
	/// For a list, an error says how many items were `done` before it (as fileremove's does).
	func map(done: String? = nil, _ transform: (URL) throws -> String) throws -> NSAppleEventDescriptor {
		switch self {
		case let .single(url):
			return try transform(url).appleEventDescriptor
		case let .list(urls):
			var results: [String] = []
			for url in urls {
				do {
					results.append(try transform(url))
				} catch let error as OSAXError {
					guard let done, urls.count > 1 else { throw error }
					let reason = error.message.map { $0 + " " } ?? ""
					throw OSAXError(error.number, reason + "\(results.count) of the \(urls.count) items were \(done) before it.")
				}
			}
			return results.appleEventDescriptor
		}
	}
}
