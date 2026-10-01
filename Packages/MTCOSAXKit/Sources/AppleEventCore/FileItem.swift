import Darwin
import Foundation

/// File system facts the commands need, read without following a final symbolic link unless asked.
public enum FileItem {
	public static func status(_ url: URL) -> stat? {
		var status = stat()
		return lstat(url.path, &status) == 0 ? status : nil
	}

	/// An item's device and inode, which tell whether two paths are the same item.
	public struct Identity: Equatable, Sendable {
		public let device: dev_t
		public let inode: ino_t

		public init(_ status: stat) {
			device = status.st_dev
			inode = status.st_ino
		}
	}

	/// The identity of what a path leads to, following links; nil if nothing's there.
	public static func identity(_ url: URL) -> Identity? {
		var status = stat()
		return stat(url.path, &status) == 0 ? Identity(status) : nil
	}

	/// A hidden name for a new item made beside another before replacing it: short and the same length whatever the
	/// other's name (its name with a UUID added made names over about 206 bytes too long to be replaced).
	public static func temporaryName() -> String {
		let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
		return ".mtc-" + String((0 ..< 12).map { _ in characters.randomElement()! })
	}

	/// Whether anything is there, including a symbolic link whose target isn't.
	public static func exists(_ url: URL) -> Bool {
		(try? url.checkResourceIsReachable()) == true || isSymlink(url)
	}

	public static func isSymlink(_ url: URL) -> Bool {
		status(url).map { ($0.st_mode & S_IFMT) == S_IFLNK } == true
	}

	/// Whether two paths are the same item (a case variant on a case-insensitive volume, or a hard link), by device
	/// and inode, without following links.
	public static func isSameItem(_ a: URL, _ b: URL) -> Bool {
		guard let first = status(a), let second = status(b) else { return false }
		return Identity(first) == Identity(second)
	}

	/// Whether two paths name one item by one name, spelled differently (a case variant on a case-insensitive
	/// volume): the same item, in the same folder, by the same name but for case. Hard links are the same item under
	/// different names, and renaming one onto the other does nothing (rename(2) succeeds and leaves both).
	public static func isSameEntry(_ a: URL, _ b: URL) -> Bool {
		isSameItem(a, b) && identity(a.deletingLastPathComponent()) == identity(b.deletingLastPathComponent())
			&& a.lastPathComponent.lowercased() == b.lastPathComponent.lowercased()
	}

	/// Whether `url` is `folder` or inside it, by the identity of each folder on the way up (so by any spelling,
	/// and through links in the path); false if either doesn't exist.
	public static func isInside(_ url: URL, _ folder: URL) -> Bool {
		guard let target = identity(folder) else { return false }
		var path = ""
		for component in url.standardizedFileURL.pathComponents {
			path = (path as NSString).appendingPathComponent(component)
			if identity(URL(fileURLWithPath: path)) == target { return true }
		}
		return false
	}

	/// Whether the path leads to a volume's root: `/`, a mount point such as `/Volumes/Backup`, or a link to one
	/// (`/Volumes/<startup disk>` is a link to `/`).
	public static func isVolumeRoot(_ url: URL) -> Bool {
		guard let item = identity(url) else { return false }
		if (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true { return true }
		let resolved = url.resolvingSymlinksInPath()
		return resolved.path == "/" || identity(resolved.deletingLastPathComponent())?.device != item.device
	}

	public static func isDirectory(_ url: URL) -> Bool {
		var directory: ObjCBool = false
		return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
	}

	public static func isPackage(_ url: URL) -> Bool {
		(try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
	}

	/// Invisible: a name starting with `.`, or the hidden flag.
	public static func isHidden(_ url: URL) -> Bool {
		url.lastPathComponent.hasPrefix(".") || (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
	}

	/// `isHidden` from an item's name and `lstat`, without asking the file system again.
	public static func isHidden(name: String, status: stat) -> Bool {
		name.hasPrefix(".") || status.st_flags & UInt32(UF_HIDDEN) != 0
	}

	public static func date(_ time: timespec) -> Date {
		Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
	}

	public static func modificationDate(_ url: URL) -> Date? {
		(try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
	}

	/// The names in a folder in the order the file system lists them (as Satimage returned them), without `.`
	/// and `..`; none for a folder that can't be read.
	public static func names(in folder: URL) -> [String] {
		namesIfReadable(in: folder) ?? []
	}

	/// `names(in:)`, or nil (with `errno` set) for a folder that can't be read.
	public static func namesIfReadable(in folder: URL) -> [String]? {
		guard let directory = opendir(folder.path) else {
			return nil
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
	public static func escapedPath(_ url: URL) -> String {
		url.path(percentEncoded: true)
	}
}
