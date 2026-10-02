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
			// Without the destination nothing can be copied: an error, not "OK" (which it was at level 1).
			do {
				try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
			} catch {
				throw OSAXError.file(error, "make the destination folder “\(destination.lastPathComponent)”")
			}
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
	private var granularities: [dev_t: Int64] = [:]

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
		// A folder that can't be read is reported, not taken as empty.
		guard let names = FileItem.namesIfReadable(in: source) else {
			errors.append((destination.path, errno))
			return
		}
		for name in names {
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
					// is reported with its error, as nothing under it can be copied (SatimageOSAX, and this before,
					// left it and everything under it out of the report).
					guard mkdir(to.path, 0o700) == 0 else {
						errors.append((to.path, errno))
						continue
					}
					FileItem.changeMode(ofNewFolder: to.path) { _ in status.st_mode & 0o7777 }
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
					if Self.isNewer(status.st_mtimespec, than: existing.st_mtimespec, granularity: timeGranularity(of: to, device: existing.st_dev)) {
						copy(from, to, isNew: false, isLink: isLink)
					}
				} else {
					copy(from, to, isNew: true, isLink: isLink)
				}
			}
		}
	}

	/// Whether a source's modification time is later than its copy's, as far as the copy's volume can tell: a
	/// volume that keeps times to the second (HFS+), two seconds (FAT) or 10 ms (exFAT) cuts the copied time short,
	/// so to the nanosecond every file on it was older than its source, and every run copied everything again.
	static func isNewer(_ source: timespec, than copy: timespec, granularity: Int64) -> Bool {
		// Seconds and nanoseconds apart: a date can be far enough from 1970 that its nanoseconds don't fit in 64 bits.
		var seconds = Int64(source.tv_sec), nanoseconds = Int64(source.tv_nsec)
		if granularity >= 1_000_000_000 {
			let step = granularity / 1_000_000_000
			seconds -= (seconds % step + step) % step
			nanoseconds = 0
		} else {
			nanoseconds -= nanoseconds % granularity
		}
		return (seconds, nanoseconds) > (Int64(copy.tv_sec), Int64(copy.tv_nsec))
	}

	/// How finely a volume keeps modification times, in nanoseconds, by the kind of file system it is.
	static func timeGranularity(ofFileSystem name: String) -> Int64 {
		switch name {
		case "hfs": 1_000_000_000
		case "msdos": 2_000_000_000
		case "exfat": 10_000_000
		default: 1
		}
	}

	/// The granularity of the volume an item is on, looked up once per volume.
	private mutating func timeGranularity(of url: URL, device: dev_t) -> Int64 {
		if let known = granularities[device] { return known }
		var info = statfs()
		var granularity: Int64 = 1
		if statfs(url.path, &info) == 0 {
			let name = withUnsafeBytes(of: &info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
			granularity = Self.timeGranularity(ofFileSystem: name)
		}
		granularities[device] = granularity
		return granularity
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
			// it was looked at. A new item isn't written over one that appeared meanwhile. A package (a folder) is
			// copied under a temporary name even when new, since a copy that fails part way leaves what it made:
			// a partial package, newer than the source, that later runs took as up to date.
			let viaTemporary = !isNew || isFolder
			let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | (isFolder ? COPYFILE_RECURSIVE : 0) | (viaTemporary ? 0 : COPYFILE_EXCL))
			let target = viaTemporary ? to.deletingLastPathComponent().appendingPathComponent(FileItem.temporaryName()) : to
			guard copyfile(from.path, target.path, nil, flags) == 0 else {
				let code = errno
				if viaTemporary { try? FileManager.default.removeItem(at: target) }
				errors.append((to.path, code))
				return
			}
			if isNew, isFolder {
				// Into place only if nothing appeared there meanwhile (as COPYFILE_EXCL does for a file).
				if renamex_np(target.path, to.path, UInt32(RENAME_EXCL)) != 0 {
					let code = errno
					try? FileManager.default.removeItem(at: target)
					errors.append((to.path, code))
					return
				}
			} else if !isNew {
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
