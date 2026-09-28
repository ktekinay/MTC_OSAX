import AppKit
import MTCOSAX
import UniformTypeIdentifiers

/// The `navchoose` dialogs and the `navask save` alert, with AppKit panels.
///
/// The app is faceless (`LSBackgroundOnly`), so while a dialog is open it becomes an accessory app (no Dock icon
/// or menu bar) and comes to the front; afterwards it goes back to the background. Apple event handlers run on the
/// main thread, so the dialogs run modally there; the idle timer doesn't run while a handler is busy.
final class PanelDialogs: FileDialogs {
	func choose(_ options: ChooseOptions) throws -> [URL] {
		try MainActor.assumeIsolated {
			let panel = NSOpenPanel()
			let filter = PanelFilter(showsPackages: options.showsPackages, opensPackages: options.opensPackages, volumesOnly: options.kind == .volumes)
			filter.allowedTypes = options.allowedTypes
			filter.allowedExtensions = options.allowedExtensions
			// With a delegate, open panels let packages be opened like folders, so only filter when needed.
			if filter.isNeeded {
				panel.delegate = filter
			}
			panel.canChooseFiles = options.kind == .files || options.kind == .filesAndFolders
			panel.canChooseDirectories = options.kind != .files
			panel.allowsMultipleSelection = options.multipleSelection
			panel.treatsFilePackagesAsDirectories = options.opensPackages
			panel.showsHiddenFiles = options.showsInvisibles
			panel.canCreateDirectories = options.kind != .volumes
			panel.message = options.prompt ?? ""
			panel.directoryURL = options.startingAt ?? (options.kind == .volumes ? URL(fileURLWithPath: "/Volumes") : nil)
			let response = Self.runInFront { panel.runModal() }
			guard response == .OK else {
				throw OSAXError(-128)
			}
			// The startup disk appears in /Volumes as a link to /.
			return options.kind == .volumes ? panel.urls.map { $0.resolvingSymlinksInPath() } : panel.urls
		}
	}

	func chooseNewItem(_ options: NewItemOptions) throws -> URL {
		try MainActor.assumeIsolated {
			let panel = NSSavePanel()
			let filter = PanelFilter(showsPackages: options.showsPackages, opensPackages: options.opensPackages, volumesOnly: false)
			if filter.isNeeded {
				panel.delegate = filter
			}
			panel.message = options.prompt ?? ""
			panel.nameFieldStringValue = options.defaultName ?? (options.folder ? "untitled folder" : "")
			panel.treatsFilePackagesAsDirectories = options.opensPackages
			panel.canCreateDirectories = true
			panel.directoryURL = options.startingAt
			if let items = options.menuItems, !items.isEmpty {
				let menu = NSPopUpButton(frame: .zero, pullsDown: false)
				menu.addItems(withTitles: items)
				if let index = options.menuIndex, items.indices.contains(index - 1) {
					menu.selectItem(at: index - 1)
				}
				menu.sizeToFit()
				panel.accessoryView = menu
			}
			let response = Self.runInFront { panel.runModal() }
			guard response == .OK, let url = panel.url else {
				throw OSAXError(-128)
			}
			return url
		}
	}

	func askSave(fileName: String?, action: Int) -> Int {
		MainActor.assumeIsolated {
			let alert = NSAlert()
			let document = fileName.map { "the document “\($0)”" } ?? "this document"
			alert.messageText = switch action {
			case 1: "Save changes to \(document) before closing?"
			case 2: "Save changes to \(document) before quitting?"
			default: "Save changes to \(document)?"
			}
			alert.informativeText = "Your changes will be lost if you don’t save them."
			alert.addButton(withTitle: "Save")
			alert.addButton(withTitle: "Cancel")
			alert.addButton(withTitle: "Don’t Save")
			alert.buttons[1].keyEquivalent = "\u{1b}"
			alert.buttons[2].keyEquivalent = "d"
			alert.buttons[2].keyEquivalentModifierMask = .command
			return switch Self.runInFront({
				alert.layout()
				alert.window.makeKeyAndOrderFront(nil)
				return alert.runModal()
			}) {
			case .alertFirstButtonReturn: 1
			case .alertThirdButtonReturn: 3
			default: 2
			}
		}
	}

	/// Shows a dialog in front of other apps, then returns the app to the background.
	@MainActor
	private static func runInFront(_ run: () -> NSApplication.ModalResponse) -> NSApplication.ModalResponse {
		let application = NSApplication.shared
		application.setActivationPolicy(.accessory)
		// A faceless app asking to become active is otherwise only a request, which macOS may not grant; the dialog
		// would then show without taking keystrokes (Return, Escape, typing).
		application.activate(ignoringOtherApps: true)
		defer { application.setActivationPolicy(.prohibited) }
		return run()
	}
}

/// Which items a panel enables: files of the allowed types or extensions, packages unless hidden
/// (`show packages` false and not opened), and only volumes in the volume dialog. Folders stay enabled so they
/// can be opened.
///
/// Open panels can't hide items, and they let the user open a disabled package like a folder. So a hidden package
/// is shown greyed out, the panel is moved back out of it if the user opens it, and choosing it is refused.
private final class PanelFilter: NSObject, NSOpenSavePanelDelegate {
	let showsPackages: Bool
	let opensPackages: Bool
	let volumesOnly: Bool
	var allowedTypes: [UTType]?
	var allowedExtensions: [String]?

	init(showsPackages: Bool, opensPackages: Bool, volumesOnly: Bool) {
		self.showsPackages = showsPackages
		self.opensPackages = opensPackages
		self.volumesOnly = volumesOnly
	}

	private var hidesPackages: Bool { !showsPackages && !opensPackages }

	/// Whether there's anything to filter; without a filter the panel's own behavior is used.
	var isNeeded: Bool { hidesPackages || volumesOnly || allowedTypes != nil || allowedExtensions != nil }

	/// The outermost package containing `url` (or `url` itself), if any.
	private func enclosingPackage(_ url: URL) -> URL? {
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

	func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) {
		guard hidesPackages, let url, let package = enclosingPackage(url), let panel = sender as? NSSavePanel else {
			return
		}
		panel.directoryURL = package.deletingLastPathComponent()
	}

	/// Whether `url` is a volume, following links (the startup disk is a link to `/` in /Volumes).
	static func isVolume(_ url: URL) -> Bool {
		(try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
	}

	func panel(_ sender: Any, validate url: URL) throws {
		// Choose with nothing selected chooses the folder being shown, such as /Volumes.
		if volumesOnly, !Self.isVolume(url) {
			throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "Choose a volume."])
		}
		if hidesPackages, enclosingPackage(url) != nil {
			throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "Packages can’t be chosen here."])
		}
	}

	func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
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
