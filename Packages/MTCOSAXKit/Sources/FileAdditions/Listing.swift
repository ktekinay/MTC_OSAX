import AppleEventCore
import Darwin
import Foundation
import UniformTypeIdentifiers

/// `list files` and `glob`.
///
/// Items come in the order the file system lists them (as Satimage returned them), or by modification date when
/// `after` or `before` is given. Symbolic links are skipped by `list files`; invisible items (a name starting with
/// `.`, or the hidden flag) are skipped unless `invisibles` is true. Extensions and name prefixes are compared
/// case-sensitively.
extension FileAdditions {
	static func listFiles(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		guard let descriptor = request.descriptor(for: Keyword.directObject) else {
			throw OSAXError.missingParameter
		}
		let folders = try [URL](appleEventDescriptor: descriptor)
		let recursively = try request.parameter("recu", default: true)
		let ignoringPackages = try request.parameter("inBu", default: false)
		let filter = try ItemFilter(request)
		let prefix = try request.parameter("Strw", as: String.self)

		var items: [ListedItem] = []
		func consider(_ url: URL, isDirectory: Bool) {
			if let prefix, !url.lastPathComponent.hasPrefix(prefix) {
				return
			}
			if filter.accepts(url, isDirectory: isDirectory) {
				items.append(ListedItem(url: url, isDirectory: isDirectory))
			}
		}
		func walk(_ folder: URL) {
			for name in FileItem.names(in: folder) {
				let url = folder.appendingPathComponent(name)
				guard let status = FileItem.status(url), (status.st_mode & S_IFMT) != S_IFLNK else {
					continue
				}
				if !filter.invisibles && FileItem.isHidden(url) {
					continue
				}
				let isDirectory = (status.st_mode & S_IFMT) == S_IFDIR
				if isDirectory && (ignoringPackages || !FileItem.isPackage(url)) {
					if recursively {
						walk(url)
					} else {
						consider(url, isDirectory: true)
					}
				} else {
					consider(url, isDirectory: isDirectory)
				}
			}
		}
		for folder in folders {
			guard FileItem.status(folder) != nil else {
				continue // A missing folder lists nothing.
			}
			let isDirectory = FileItem.isDirectory(folder)
			if isDirectory && (ignoringPackages || !FileItem.isPackage(folder)) {
				walk(folder)
			} else {
				consider(folder, isDirectory: isDirectory)
			}
		}
		return try filter.result(items, request: request)
	}

	/// Paths matching a shell pattern with `*`, `?`, `[…]`, `{a,b}` and `~`, in the order the file system lists
	/// them.
	static func glob(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		guard let descriptor = request.descriptor(for: Keyword.directObject) else {
			throw OSAXError.missingParameter
		}
		let patterns = try [String](appleEventDescriptor: descriptor)
		let base = try request.parameter("from", as: URL.self)
		let filter = try ItemFilter(request)

		var items: [ListedItem] = []
		for pattern in patterns where !pattern.isEmpty {
			// Without `from`, a relative pattern is relative to `/`, the working folder of a launched app. With it,
			// `~` is the home folder only as `~/…`, as for the file commands' paths: `~$*` is names in the folder.
			let full = if pattern.hasPrefix("/") || pattern.hasPrefix(base == nil ? "~" : "~/") {
				pattern
			} else {
				// The folder is a name, not a pattern: `g[1]` would otherwise match `g1`.
				escaped(base?.path ?? "") + "/" + pattern
			}
			guard braceExpansions(pattern) <= maximumBraceExpansions else {
				throw OSAXError(-50, "The pattern’s braces make more than \(maximumBraceExpansions) patterns to look for.")
			}
			for path in matches(full) {
				let url = URL(fileURLWithPath: path)
				// glob(3) matches `.` and `..` with `.*`; they're the folder itself and its parent, not items in it.
				if url.lastPathComponent == "." || url.lastPathComponent == ".." {
					continue
				}
				if !filter.invisibles && FileItem.isHidden(url) {
					continue
				}
				let isDirectory = FileItem.isDirectory(url)
				if filter.accepts(url, isDirectory: isDirectory) {
					items.append(ListedItem(url: url, isDirectory: isDirectory))
				}
			}
		}
		return try filter.result(items, request: request)
	}

	/// A path with glob(3)'s special characters backslash-escaped, so it only matches itself (scalar by scalar: a
	/// special character followed by a combining mark is one Character, which glob doesn't see as one).
	static func escaped(_ path: String) -> String {
		var result = String.UnicodeScalarView()
		for scalar in path.unicodeScalars {
			if "\\*?[]{}~".unicodeScalars.contains(scalar) {
				result.append("\\")
			}
			result.append(scalar)
		}
		return String(result)
	}

	/// glob(3) looks for every pattern a pattern's braces make, one after another, with the main thread (and every
	/// script) waiting: `{a,b}` 25 times made 33 million.
	static let maximumBraceExpansions = 10_000

	/// How many patterns `{…}` groups make (nested ones too; `\` escapes a brace), saturating far above the limit.
	static func braceExpansions(_ pattern: String) -> Int {
		let characters = Array(pattern)
		let cap = 1 << 40
		var index = 0
		func saturating(_ a: Int, _ b: Int) -> Int {
			let (product, overflow) = a.multipliedReportingOverflow(by: b)
			return overflow ? cap : min(product, cap)
		}
		// Text and groups up to the end, or (in a group) an unnested `,` or `}`: the product of its groups.
		func run(inGroup: Bool) -> Int {
			var product = 1
			while index < characters.count {
				let character = characters[index]
				if character == "\\" {
					index += 2
					continue
				}
				if inGroup, character == "," || character == "}" {
					return product
				}
				index += 1
				guard character == "{" else { continue }
				var alternatives = 0
				while true {
					alternatives = min(alternatives + run(inGroup: true), cap)
					guard index < characters.count else { return product }
					index += 1
					if characters[index - 1] == "}" { break }
				}
				product = saturating(product, max(alternatives, 1))
			}
			return product
		}
		return run(inGroup: false)
	}

	static func matches(_ pattern: String) -> [String] {
		var result = glob_t()
		defer { globfree(&result) }
		guard Darwin.glob(pattern, GLOB_BRACE | GLOB_TILDE | GLOB_NOSORT, nil, &result) == 0 else {
			return []
		}
		return (0 ..< Int(result.gl_pathc)).compactMap { index in
			result.gl_pathv[index].map { String(cString: $0) }
		}
	}
}

struct ListedItem {
	var url: URL
	var isDirectory: Bool
}

/// The filters `list files` and `glob` share, and how they return their results.
struct ItemFilter {
	var invisibles: Bool
	var extensions: [String]?
	var conforming: [UTType]?
	var notConforming: [UTType]?
	var after: Date?
	var before: Date?

	init(_ request: AppleEventRequest) throws {
		invisibles = try request.parameter("invi", default: false)
		extensions = try request.parameter("Nmxt", as: [String].self)
		conforming = try request.parameter("yUTI", as: [String].self).map { $0.compactMap { UTType($0) } }
		notConforming = try request.parameter("nUTI", as: [String].self).map { $0.compactMap { UTType($0) } }
		after = try request.parameter("afte", as: Date.self)
		before = try request.parameter("befo", as: Date.self)
		if conforming != nil && notConforming != nil {
			throw FileAdditions.parameterError
		}
	}

	func accepts(_ url: URL, isDirectory: Bool) -> Bool {
		if let extensions, !extensions.contains(url.pathExtension) {
			return false
		}
		if conforming != nil || notConforming != nil {
			let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
			if let conforming, !conforming.contains(where: { type?.conforms(to: $0) == true }) {
				return false
			}
			if let notConforming, notConforming.contains(where: { type?.conforms(to: $0) == true }) {
				return false
			}
		}
		if after != nil || before != nil {
			guard let date = FileItem.modificationDate(url) else {
				return false
			}
			if let after, date <= after {
				return false
			}
			if let before, date >= before {
				return false
			}
		}
		return true
	}

	/// The items as the `names only` and `as` parameters ask, sorted by modification date when dates were given.
	func result(_ items: [ListedItem], request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		var items = items
		if after != nil || before != nil {
			let dates = items.map { FileItem.modificationDate($0.url) ?? .distantPast }
			items = zip(items, dates).enumerated()
				.sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
				.map(\.element.0)
		}
		if try request.parameter("namo", default: false) {
			return items.map(\.url.lastPathComponent).appleEventDescriptor
		}
		let form = ResultForm(request, default: .fileReference)
		return try items.map { try form.descriptor(for: $0.url, isDirectory: $0.isDirectory) }.appleEventDescriptor
	}
}
