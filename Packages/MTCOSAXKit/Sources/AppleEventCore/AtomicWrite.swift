import Darwin
import Foundation

extension Data {
	/// Replaces a file in one step, so a failure part way never leaves it cut short: the data is written to a
	/// temporary file and renamed over it. A symbolic link is followed (its target is replaced, not the link), and
	/// the old file's permissions are kept. Like any replacement, the file becomes a new one: extended attributes,
	/// other hard links to it and its owner, if someone else, aren't carried over.
	public func writeReplacing(_ url: URL) throws {
		let target = url.resolvingSymlinksInPath()
		var status = stat()
		let mode = stat(target.path, &status) == 0 ? status.st_mode & 0o7777 : nil
		try write(to: target, options: .atomic)
		if let mode {
			chmod(target.path, mode)
		}
	}
}
