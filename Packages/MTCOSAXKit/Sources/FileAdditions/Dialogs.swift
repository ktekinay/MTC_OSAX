import AppleEventCore
import Foundation
import UniformTypeIdentifiers

/// Shows the dialogs for the `navchoose` commands and `navask save`. The app implements it with AppKit; tests
/// use a fake. Every method throws error -128 ("User canceled") when the user cancels.
public protocol FileDialogs {
	/// Open dialog (`navchoose file`, `folder`, `object`, `volume`): the chosen items.
	func choose(_ options: ChooseOptions) throws -> [URL]
	/// Save dialog (`navchoose file name`, `navnew folder`): the new item's location; nothing is created.
	func chooseNewItem(_ options: NewItemOptions) throws -> URL
	/// The "save changes?" alert: 1 Save, 2 Cancel, 3 Don't Save.
	func askSave(fileName: String?, action: Int) -> Int
}

public struct ChooseOptions: Equatable, Sendable {
	public enum Kind: Equatable, Sendable {
		case files, folders, filesAndFolders, volumes
	}

	public var kind: Kind
	public var prompt: String?
	/// Files that may be chosen: those of these types (`of type`, including types that conform to them) or with
	/// these extensions (`of extension`, compared without case). Nil for no restriction.
	public var allowedTypes: [UTType]?
	public var allowedExtensions: [String]?
	public var startingAt: URL?
	public var multipleSelection = true
	/// Whether packages can be seen and chosen (`show packages`, default true).
	public var showsPackages = true
	/// Whether packages can be opened like folders (`open packages`, default false).
	public var opensPackages = false
	public var showsInvisibles = false

	public init(kind: Kind) {
		self.kind = kind
	}
}

public struct NewItemOptions: Equatable, Sendable {
	public var folder: Bool
	public var prompt: String?
	public var defaultName: String?
	/// `with menu`: items for a popup menu under the name field, with `menu index` (1-based) selected.
	public var menuItems: [String]?
	public var menuIndex: Int?
	public var startingAt: URL?
	public var showsPackages = true
	public var opensPackages = false

	public init(folder: Bool) {
		self.folder = folder
	}
}

extension FileAdditions {
	/// Where `key` folders are remembered, e.g. `["3": "/Users/me/Documents"]`.
	static let keyFoldersDefault = "NavKeyFolders"

	static func dialogCommands(_ dialogs: (any FileDialogs)?, defaults: UserDefaults = .standard) -> [CommandDefinition] {
		let chooseFile = { (kind: ChooseOptions.Kind) in
			{ (request: AppleEventRequest) throws -> NSAppleEventDescriptor in
				guard let dialogs else {
					throw OSAXError.eventNotHandled
				}
				return try choose(kind, request, dialogs: dialogs, defaults: defaults)
			}
		}
		let newItem = { (folder: Bool) in
			{ (request: AppleEventRequest) throws -> NSAppleEventDescriptor in
				guard let dialogs else {
					throw OSAXError.eventNotHandled
				}
				return try chooseNewItem(folder: folder, request, dialogs: dialogs, defaults: defaults)
			}
		}
		return [
			CommandDefinition("navchoose file", code: "SATIstdf", handler: chooseFile(.files)),
			CommandDefinition("navchoose folder", code: "SATIstfl", handler: chooseFile(.folders)),
			CommandDefinition("navchoose object", code: "SATIstob", handler: chooseFile(.filesAndFolders)),
			CommandDefinition("navchoose volume", code: "SATIstvo", handler: chooseFile(.volumes)),
			CommandDefinition("navchoose file name", code: "SATInwfl", handler: newItem(false)),
			CommandDefinition("navnew folder", code: "SATIstnf", handler: newItem(true)),
			CommandDefinition("navask save", code: "SATInask") { request in
				guard let dialogs else {
					throw OSAXError.eventNotHandled
				}
				let action = try request.parameter("acti", default: 0)
				guard (0 ... 2).contains(action) else {
					throw parameterError
				}
				return dialogs.askSave(fileName: try request.parameter("fnam", as: String.self), action: action)
			},
		]
	}

	/// The open dialogs: a list of aliases.
	static func choose(_ kind: ChooseOptions.Kind, _ request: AppleEventRequest, dialogs: any FileDialogs, defaults: UserDefaults) throws -> NSAppleEventDescriptor {
		var options = ChooseOptions(kind: kind)
		options.prompt = try request.parameter("prmp", as: String.self)
		options.multipleSelection = try request.parameter("mlfl", default: true)
		options.showsPackages = try request.parameter("vipa", default: true)
		options.opensPackages = try request.parameter("oppa", default: false)
		options.showsInvisibles = try request.parameter("lfiv", default: false)
		options.allowedTypes = try allowedTypes(request)
		options.allowedExtensions = try request.parameter("Nmxt", as: [String].self)?.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
		let key = try request.parameter("key ", as: Int.self)
		options.startingAt = try request.parameter("from", as: URL.self) ?? key.flatMap { keyFolder($0, defaults: defaults) }
		if kind == .volumes {
			options.multipleSelection = false
		}
		let chosen = try dialogs.choose(options)
		if let key, let first = chosen.first {
			remember(first.deletingLastPathComponent(), key: key, defaults: defaults)
		}
		return try chosen.map { url in
			guard let alias = NSAppleEventDescriptor.alias(url) else {
				throw notFound
			}
			return alias
		}.appleEventDescriptor
	}

	/// The save dialogs: a file URL for the new item.
	static func chooseNewItem(folder: Bool, _ request: AppleEventRequest, dialogs: any FileDialogs, defaults: UserDefaults) throws -> NSAppleEventDescriptor {
		var options = NewItemOptions(folder: folder)
		options.prompt = try request.parameter("prmt", as: String.self)
		options.opensPackages = try request.parameter("oppa", default: false)
		if !folder {
			options.defaultName = try request.parameter("dfnm", as: String.self)
			options.menuItems = try request.parameter("wmnu", as: [String].self)
			options.menuIndex = try request.parameter("PInd", as: Int.self)
			options.showsPackages = try request.parameter("vipa", default: true)
		}
		let key = try request.parameter("key ", as: Int.self)
		options.startingAt = try request.parameter("from", as: URL.self) ?? key.flatMap { keyFolder($0, defaults: defaults) }
		let chosen = try dialogs.chooseNewItem(options)
		if let key {
			remember(chosen.deletingLastPathComponent(), key: key, defaults: defaults)
		}
		return NSAppleEventDescriptor(fileURL: URL(fileURLWithPath: chosen.path, isDirectory: folder))
	}

	/// `of type`: UTIs, or four-character file types; nil when not given. `of extension` is kept as extensions,
	/// since matching by type would also allow files whose types merely conform (AppleScript files are plain text).
	static func allowedTypes(_ request: AppleEventRequest) throws -> [UTType]? {
		try request.parameter("ftyp", as: [String].self)?.compactMap { type in
			if type.utf8.count == 4, !type.contains(".") {
				return UTType(tag: type, tagClass: UTTagClass(rawValue: "com.apple.ostype"), conformingTo: nil)
			}
			return UTType(type)
		}
	}

	static func keyFolder(_ key: Int, defaults: UserDefaults) -> URL? {
		guard let path = (defaults.dictionary(forKey: keyFoldersDefault) as? [String: String])?[String(key)],
		      FileItem.isDirectory(URL(fileURLWithPath: path))
		else {
			return nil
		}
		return URL(fileURLWithPath: path, isDirectory: true)
	}

	static func remember(_ folder: URL, key: Int, defaults: UserDefaults) {
		var folders = defaults.dictionary(forKey: keyFoldersDefault) as? [String: String] ?? [:]
		folders[String(key)] = folder.path
		defaults.set(folders, forKey: keyFoldersDefault)
	}
}
