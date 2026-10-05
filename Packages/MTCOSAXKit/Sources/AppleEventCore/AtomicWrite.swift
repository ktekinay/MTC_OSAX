import Darwin
import Foundation

extension Data {
	/// Replaces a file in one step, so a failure part way never leaves it cut short: the data is written to a
	/// temporary file and renamed over it. A symbolic link is followed (its target is replaced, or made, not the
	/// link), and the old file's permissions are kept, other than setuid and setgid, as any write clears them. Like
	/// any replacement, the file becomes a new one: extended attributes, other hard links to it and its owner, if
	/// someone else, aren't carried over. An existing file that can be written in a folder that can't (where the
	/// temporary file can't be made) is written in place, as before one-step saves, rather than not at all. An
	/// existing file that can't be written isn't replaced (EACCES): renaming a new file over it only needs the
	/// folder's permission, so a read-only file was replaced, and given its read-only mode again, as SatimageOSAX
	/// (error 1) and any write in place refuse to.
	public func writeReplacing(_ url: URL) throws {
		let target = try URL.followingLinks(url)
		var status = stat()
		let mode = stat(target.path, &status) == 0 ? status.st_mode & 0o777 : nil
		if mode != nil, access(target.path, W_OK) != 0 {
			throw POSIXError(.EACCES)
		}
		if mode != nil, access(target.deletingLastPathComponent().path, W_OK) != 0, access(target.path, W_OK) == 0 {
			try write(to: target)
			return
		}
		try write(to: target, options: .atomic)
		if let mode {
			chmod(target.path, mode)
		}
	}
}

extension URL {
	/// Where a path leads through symbolic links, which needn't exist yet. (`resolvingSymlinksInPath` leaves a link
	/// to something missing as it is, so writing replaced the link with a file, taking the link's 0755.)
	static func followingLinks(_ url: URL) throws -> URL {
		var path = url.path
		for _ in 0 ..< 32 {
			var status = stat()
			guard lstat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFLNK else {
				return URL(fileURLWithPath: path).resolvingSymlinksInPath()
			}
			var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
			let length = readlink(path, &buffer, buffer.count - 1)
			guard length >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
			let destination = String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
			path = destination.hasPrefix("/") ? destination : (path as NSString).deletingLastPathComponent + "/" + destination
			path = (path as NSString).standardizingPath
		}
		throw POSIXError(.ELOOP)
	}
}
