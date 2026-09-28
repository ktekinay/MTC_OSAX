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
			let filter = PanelFilter(PanelRules(showsPackages: options.showsPackages, opensPackages: options.opensPackages,
			                                    volumesOnly: options.kind == .volumes, allowedTypes: options.allowedTypes,
			                                    allowedExtensions: options.allowedExtensions))
			// With a delegate, open panels let packages be opened like folders, so only filter when needed.
			if filter.rules.isNeeded {
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
			// The delegate is weak; the filter must outlive the panel's run.
			let response = withExtendedLifetime(filter) { Self.runInFront { panel.runModal() } }
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
			let filter = PanelFilter(PanelRules(showsPackages: options.showsPackages, opensPackages: options.opensPackages, volumesOnly: false))
			if filter.rules.isNeeded {
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
			let response = withExtendedLifetime(filter) { Self.runInFront { panel.runModal() } }
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

/// Hands the panel's questions to `PanelRules`. `NSSavePanel.delegate` is weak: whoever sets it keeps it alive until
/// the panel is done.
private final class PanelFilter: NSObject, NSOpenSavePanelDelegate {
	let rules: PanelRules

	init(_ rules: PanelRules) {
		self.rules = rules
	}

	func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) {
		guard let url, let directory = rules.directory(replacing: url), let panel = sender as? NSSavePanel else {
			return
		}
		panel.directoryURL = directory
	}

	func panel(_ sender: Any, validate url: URL) throws {
		if let refusal = rules.refusal(of: url) {
			throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: refusal])
		}
	}

	func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
		rules.shouldEnable(url)
	}
}
