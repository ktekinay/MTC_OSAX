import CLibXML
import Foundation

/// Limits on what libxml2 and libxslt load by URL while they follow a document's own choices (XInclude, a
/// stylesheet the document names): nothing from the network, and files only from some folders.
///
/// Everything libxml2 and libxslt load (DTDs and entities, includes, `xsl:import`, `document()`, the entities in
/// what those load) goes through the external entity loader, and everything from the network also through
/// `NetworkInput`, so the limits are checked there, whatever the parser options or libxslt's security preferences
/// say. `XML_PARSE_NONET` only stops http, and libxslt's preferences don't see the entities of what it loads.
enum LoadRestrictions {
	/// The limits in force, and what they refused.
	final class Scope {
		/// The folders files may come from (and folders inside them), resolved; nil for any file.
		let folders: [String]?
		private(set) var refused: [String] = []

		init(folders: [URL]?) {
			self.folders = folders?.map { LoadRestrictions.resolved($0.path) }
		}

		/// Whether a URL or path libxml2 asks for may be loaded; if not, it's noted and warned about.
		func allows(_ location: String) -> Bool {
			let allowed = LoadRestrictions.paths(of: location).map { paths in
				folders.map { folders in paths.allSatisfy { path in folders.contains { path == $0 || path.hasPrefix($0 + "/") } } } ?? true
			} ?? false
			if !allowed {
				refused.append(location)
				XMLIssues.warn(folders == nil
					? "A document can’t load from the network here: \(location)"
					: "A document can only load files from its own folder here: \(location)")
			}
			return allowed
		}
	}

	private static let key = "MTCXMLLoadRestrictions"

	/// The limits in force on this thread (libxml2 calls its loaders on the thread doing the work), if any.
	static var current: Scope? {
		Thread.current.threadDictionary[key] as? Scope
	}

	/// Runs `body` with nothing loaded from the network, and files only from `folders` (nil: any file); also gives
	/// what was refused.
	static func restricted<T>(toFolders folders: [URL]?, _ body: () throws -> T) rethrows -> (result: T, refused: [String]) {
		install()
		let previous = Thread.current.threadDictionary[key]
		let scope = Scope(folders: folders)
		Thread.current.threadDictionary[key] = scope
		defer { Thread.current.threadDictionary[key] = previous }
		return (try body(), scope.refused)
	}

	/// The local paths a location names, as given and with escapes decoded (libxml2 tries both); nil for one on
	/// the network (or any URL that isn't a file's). A relative path is in the current folder, as libxml2 opens it.
	static func paths(of location: String) -> [String]? {
		let lowercased = location.lowercased()
		var path = location
		if lowercased.hasPrefix("file:") {
			guard let url = URL(string: location), url.isFileURL, url.host.map({ $0.isEmpty || $0 == "localhost" }) ?? true else { return nil }
			path = url.path
		} else if location.contains("://") {
			return nil
		}
		return Set([path, path.removingPercentEncoding ?? path]).map(resolved)
	}

	/// A path made absolute, without `.` or `..`, and with its links followed.
	static func resolved(_ path: String) -> String {
		let absolute = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
		return URL(fileURLWithPath: absolute).standardizedFileURL.resolvingSymlinksInPath().path
	}

	private static func install() {
		_ = installation
	}

	nonisolated(unsafe) private static var defaultLoader: xmlExternalEntityLoader?

	private static let installation: Void = {
		defaultLoader = xmlGetExternalEntityLoader()
		xmlSetExternalEntityLoader { url, id, context in
			if let url, let scope = LoadRestrictions.current, !scope.allows(String(cString: url)) {
				return nil
			}
			return LoadRestrictions.defaultLoader?(url, id, context)
		}
	}()
}
