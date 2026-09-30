import AppleEventCore
import Darwin
import Foundation

/// `backup`: copies what's new or newer in a folder onto another, as SatimageOSAX did.
///
/// - Files and packages are copied when missing from the destination, or updated when the source was modified
///   later. Nothing is ever deleted from the destination: an update is copied under a temporary name and then
///   swapped in, so a failed copy leaves the old item, and a file never replaces a folder (or a package a file);
///   such a pair is an error (21 or 20). SatimageOSAX replaced a folder, and everything in it, with the file.
/// - Folders are created as needed; `except folders` skips folders (not packages) by name at any depth.
/// - Symbolic links are copied as links, never followed (SatimageOSAX made an empty folder for each), in the
///   destination too: a folder where the destination has a link is an error (20).
/// - Invisible items are skipped. `after`, `only extensions` and `except extensions` (case-sensitive, without
///   the dot) apply to files and packages.
/// - Level 0 reports what would change, listing a missing folder once rather than its contents; level 1 syncs and
///   returns "OK"; level 2 syncs and reports each file. "OK" also means there was nothing to report.
/// - A destination inside the source is left out of the walk (SatimageOSAX gave -50 after creating it); the
///   source itself as the destination is -50.
extension FileAdditions {
	static func backup(_ request: AppleEventRequest) throws -> String {
		let source = try request.requiredDirectParameter(as: URL.self)
		let destination = try request.requiredParameter("onto", as: URL.self)
		guard FileItem.isDirectory(source) else {
			throw parameterError
		}
		let level = try request.parameter("Repo", default: 0)
		// (SatimageOSAX took any other level as a report that still created the destination folder.)
		guard (0 ... 2).contains(level) else {
			throw OSAXError(-50, "The level is 0 (report only), 1 (synchronize) or 2 (synchronize and report).")
		}
		var sync = Backup(
			level: level,
			after: try request.parameter("afte", as: Date.self),
			recursively: try request.parameter("RECU", default: true),
			exceptFolders: Set(try request.parameter("fnam", default: [String]())),
			exceptExtensions: Set(try request.parameter("fext", default: [String]())),
			onlyExtensions: try request.parameter("oext", as: [String].self).map(Set.init)
		)
		let sourceIdentity = FileItem.identity(source)
		if FileItem.identity(destination) == sourceIdentity {
			throw OSAXError(-50, "The destination is the folder being backed up.")
		}
		if sync.level != 0 {
			try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		}
		sync.destinationIdentity = FileItem.identity(destination)
		sync.run(source, onto: destination)
		return sync.report
	}
}

struct Backup {
	var level: Int
	var after: Date?
	var recursively: Bool
	var exceptFolders: Set<String>
	var exceptExtensions: Set<String>
	var onlyExtensions: Set<String>?
	/// The destination folder, which is skipped if it's inside the source (it would otherwise be backed up into
	/// itself, deeper each time, until paths got too long).
	var destinationIdentity: FileItem.Identity?

	private var updated: [String] = []
	private var created: [String] = []
	private var errors: [(path: String, code: Int32)] = []

	init(level: Int, after: Date?, recursively: Bool, exceptFolders: Set<String>, exceptExtensions: Set<String>, onlyExtensions: Set<String>?) {
		self.level = level
		self.after = after
		self.recursively = recursively
		self.exceptFolders = exceptFolders
		self.exceptExtensions = exceptExtensions
		self.onlyExtensions = onlyExtensions
	}

	private var reportOnly: Bool { level == 0 }

	/// Everything about an item comes from one `lstat`: `appendingPathComponent(_:)` checked the disk for each name
	/// to see whether it was a folder, and the hidden flag and dates were read again through URL resource values.
	mutating func run(_ source: URL, onto destination: URL) {
		for name in FileItem.names(in: source) {
			var status = stat()
			guard lstat(source.path + "/" + name, &status) == 0, !FileItem.isHidden(name: name, status: status) else {
				continue
			}
			let isDirectory = (status.st_mode & S_IFMT) == S_IFDIR
			let from = source.appendingPathComponent(name, isDirectory: isDirectory)
			let to = destination.appendingPathComponent(name, isDirectory: isDirectory)
			if isDirectory && !FileItem.isPackage(from) {
				guard recursively, !exceptFolders.contains(name), FileItem.Identity(status) != destinationIdentity else {
					continue
				}
				if let existing = FileItem.status(to) {
					// Not through a link (one an earlier backup copied, say): the files would be written wherever it
					// points. (Under a file, each file is an error of its own, as in SatimageOSAX.)
					guard (existing.st_mode & S_IFMT) != S_IFLNK else {
						errors.append((to.path, ENOTDIR))
						continue
					}
				} else {
					if reportOnly {
						created.append(to.path)
						continue
					}
					// With the source folder's permissions (mkdir's are less the umask). A folder that can't be made
					// isn't listed itself, as in SatimageOSAX's reports (the files under it are, where they fail).
					guard mkdir(to.path, 0o700) == 0 else {
						continue
					}
					chmod(to.path, status.st_mode & 0o7777)
				}
				run(from, onto: to)
			} else {
				let pathExtension = from.pathExtension
				if exceptExtensions.contains(pathExtension) || onlyExtensions.map({ !$0.contains(pathExtension) }) == true {
					continue
				}
				// A link's own date: following it could leave the source (a link to .. copied the tree into itself).
				let isLink = (status.st_mode & S_IFMT) == S_IFLNK
				let modified = FileItem.date(status.st_mtimespec)
				if let after, modified < after {
					continue
				}
				if let existing = FileItem.status(to) {
					if modified > FileItem.date(existing.st_mtimespec) {
						copy(from, to, isNew: false, isLink: isLink)
					}
				} else {
					copy(from, to, isNew: true, isLink: isLink)
				}
			}
		}
	}

	/// Copies (or, for a report, lists) a new or newer file, package or link.
	private mutating func copy(_ from: URL, _ to: URL, isNew: Bool, isLink: Bool) {
		let isFolder = !isLink && FileItem.isDirectory(from)
		if !isNew, let existing = FileItem.status(to), ((existing.st_mode & S_IFMT) == S_IFDIR) != isFolder {
			errors.append((to.path, isFolder ? ENOTDIR : EISDIR))
			return
		}
		if !reportOnly {
			// Links are copied as links, inside packages too (following them copied what a link in an untrusted
			// package pointed at, such as a private key, into the backup), and so is an item that became a link since
			// it was looked at. A new item isn't written over one that appeared meanwhile.
			let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | (isFolder ? COPYFILE_RECURSIVE : 0) | (isNew ? COPYFILE_EXCL : 0))
			let target = isNew ? to : to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).mtc-backup-\(UUID().uuidString)")
			guard copyfile(from.path, target.path, nil, flags) == 0 else {
				let code = errno
				if !isNew { try? FileManager.default.removeItem(at: target) }
				errors.append((to.path, code))
				return
			}
			if !isNew {
				// rename replaces a file or link in one step; a package (a folder) is swapped by FileManager.
				var code: Int32 = 0
				if !isFolder {
					code = rename(target.path, to.path) == 0 ? 0 : errno
				} else {
					do {
						_ = try FileManager.default.replaceItemAt(to, withItemAt: target, options: .usingNewMetadataOnly)
					} catch {
						code = Int32(((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? Int(EIO))
					}
				}
				if code != 0 {
					try? FileManager.default.removeItem(at: target)
					errors.append((to.path, code))
					return
				}
			}
		}
		if isNew {
			created.append(to.path)
		} else {
			updated.append(to.path)
		}
	}

	var report: String {
		guard level != 1 else {
			return "OK"
		}
		var text = ""
		func section(_ title: String, _ paths: [String]) {
			if !paths.isEmpty {
				text += title + " : \r" + paths.map { "\t\($0)\n" }.joined()
			}
		}
		section(reportOnly ? "Items to update" : "Items updated", updated)
		section(reportOnly ? "Items to create" : "Items created", created)
		if !errors.isEmpty {
			text += "Errors : \r" + errors.map { "\($0.path)  Error : \($0.code) \n" }.joined()
		}
		return text.isEmpty ? "OK" : text
	}
}
