import AppleEventCore
import Darwin
import Foundation

/// `backup`: copies what's new or newer in a folder onto another, as SatimageOSAX did.
///
/// - Files and packages are copied when missing from the destination, or updated when the source was modified
///   later. Nothing is ever deleted from the destination.
/// - Folders are created as needed; `except folders` skips folders (not packages) by name at any depth.
/// - Symbolic links are copied as links, never followed (SatimageOSAX made an empty folder for each).
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
		var sync = Backup(
			level: try request.parameter("Repo", default: 0),
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

	mutating func run(_ source: URL, onto destination: URL) {
		for name in FileItem.names(in: source) {
			let from = source.appendingPathComponent(name)
			let to = destination.appendingPathComponent(name)
			guard let status = FileItem.status(from), !FileItem.isHidden(from) else {
				continue
			}
			let isDirectory = (status.st_mode & S_IFMT) == S_IFDIR
			if isDirectory && !FileItem.isPackage(from) {
				guard recursively, !exceptFolders.contains(name), FileItem.Identity(status) != destinationIdentity else {
					continue
				}
				if FileItem.status(to) == nil {
					if reportOnly {
						created.append(to.path)
						continue
					}
					guard mkdir(to.path, 0o777) == 0 else {
						continue
					}
				}
				run(from, onto: to)
			} else {
				let pathExtension = from.pathExtension
				if exceptExtensions.contains(pathExtension) || onlyExtensions.map({ !$0.contains(pathExtension) }) == true {
					continue
				}
				// A link's own date: following it could leave the source (a link to .. copied the tree into itself).
				let isLink = (status.st_mode & S_IFMT) == S_IFLNK
				let modified = isLink ? FileItem.date(status.st_mtimespec) : FileItem.modificationDate(from) ?? .distantPast
				if let after, modified < after {
					continue
				}
				if let existing = FileItem.status(to) {
					let existingDate = (existing.st_mode & S_IFMT) == S_IFLNK ? FileItem.date(existing.st_mtimespec) : FileItem.modificationDate(to)
					if let existingDate, modified > existingDate {
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
		if !reportOnly {
			if !isNew {
				try? FileManager.default.removeItem(at: to)
			}
			let flags = copyfile_flags_t(COPYFILE_ALL | (isLink ? COPYFILE_NOFOLLOW : FileItem.isDirectory(from) ? COPYFILE_RECURSIVE : 0))
			guard copyfile(from.path, to.path, nil, flags) == 0 else {
				errors.append((to.path, errno))
				return
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
