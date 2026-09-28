import Foundation
import UniformTypeIdentifiers

/// Which items the `navchoose` dialogs enable and accept: files of the allowed types or extensions, packages unless
/// hidden (`show packages` false and not opened), and only volumes in the volume dialog. Folders stay enabled so
/// they can be opened. The app's panel delegate asks these rules, so they can be tested without a panel.
///
/// Open panels can't hide items, and they let the user open a disabled package like a folder. So a hidden package
/// is shown greyed out, the panel is moved back out of it if the user opens it, and choosing it is refused.
public struct PanelRules: Sendable {
	public let showsPackages: Bool
	public let opensPackages: Bool
	public let volumesOnly: Bool
	public let allowedTypes: [UTType]?
	public let allowedExtensions: [String]?

	public init(showsPackages: Bool, opensPackages: Bool, volumesOnly: Bool, allowedTypes: [UTType]? = nil, allowedExtensions: [String]? = nil) {
		self.showsPackages = showsPackages
		self.opensPackages = opensPackages
		self.volumesOnly = volumesOnly
		self.allowedTypes = allowedTypes
		self.allowedExtensions = allowedExtensions
	}

	var hidesPackages: Bool { !showsPackages && !opensPackages }

	/// Whether there's anything to filter; without a filter the panel's own behavior is used.
	public var isNeeded: Bool { hidesPackages || volumesOnly || allowedTypes != nil || allowedExtensions != nil }

	/// The outermost package containing `url` (or `url` itself), if any.
	static func enclosingPackage(_ url: URL) -> URL? {
		var package: URL?
		var current = url.standardizedFileURL
		while current.path != "/" {
			if (try? current.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
				package = current
			}
			current = current.deletingLastPathComponent()
		}
		return package
	}

	/// Whether `url` is a volume, following links (the startup disk is a link to `/` in /Volumes).
	static func isVolume(_ url: URL) -> Bool {
		(try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
	}

	/// Where the panel goes instead when the user opens `url` inside a hidden package: the package's folder.
	public func directory(replacing url: URL) -> URL? {
		guard hidesPackages, let package = Self.enclosingPackage(url) else { return nil }
		return package.deletingLastPathComponent()
	}

	/// Why `url` can't be chosen, or nil if it can. (Choose with nothing selected chooses the folder being shown,
	/// such as /Volumes.)
	public func refusal(of url: URL) -> String? {
		if volumesOnly, !Self.isVolume(url) {
			return "Choose a volume."
		}
		if hidesPackages, Self.enclosingPackage(url) != nil {
			return "Packages can’t be chosen here."
		}
		return nil
	}

	public func shouldEnable(_ url: URL) -> Bool {
		let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isVolumeKey, .contentTypeKey])
		if volumesOnly {
			return Self.isVolume(url)
		}
		let isPackage = values?.isPackage == true && !opensPackages
		if isPackage && !showsPackages {
			return false
		}
		if values?.isDirectory == true && !isPackage {
			return true
		}
		guard allowedTypes != nil || allowedExtensions != nil else {
			return true
		}
		let pathExtension = url.pathExtension.lowercased()
		if allowedExtensions?.contains(where: { $0.lowercased() == pathExtension }) == true {
			return true
		}
		guard let type = values?.contentType else {
			return false
		}
		return allowedTypes?.contains { type.conforms(to: $0) } == true
	}
}
