import AppleEventCore
import Foundation

extension Settings {
	/// `mtc_get`, `mtc_set` and `mtc_reset`, reading and writing `defaults` (the app's own; tests pass another).
	@MainActor
	public static func commands(defaults: UserDefaults = .standard) -> [CommandDefinition] {
		[
			CommandDefinition("mtc_get", code: "MTCsget ") { request in
				switch try target(request) {
				case let .one(setting):
					return setting.value(in: defaults)
				case .all:
					return Setting.all.map { info($0, defaults: defaults).appleEventDescriptor }.appleEventDescriptor
				}
			},

			CommandDefinition("mtc_set", code: "MTCsset ") { request in
				guard case let .one(setting) = try target(request) else {
					throw OSAXError(-50, "mtc_set changes one setting; mtc_reset all_settings puts them all back to their defaults.")
				}
				guard let value = request.descriptor(for: "to  ") else {
					throw OSAXError.missingParameter
				}
				guard value.descriptorType != typeType || value.typeCodeValue.fourCharString != "msng" else {
					throw OSAXError(-1700, "Use mtc_reset to put \(setting.constant) back to its default.")
				}
				defaults.set(try setting.normalize(value), forKey: setting.key)
				return nil
			},

			CommandDefinition("mtc_reset", code: "MTCsrset") { request in
				switch try target(request) {
				case let .one(setting):
					defaults.removeObject(forKey: setting.key)
				case .all:
					Setting.all.forEach { defaults.removeObject(forKey: $0.key) }
				}
				return nil
			},
		]
	}

	enum Target {
		case one(Setting)
		case all
	}

	static let allSettingsCode = "MTsa"

	/// The direct parameter: a setting's constant (`regex_syntax`), `all_settings`, or text naming either (the
	/// friendly name, the `defaults` key or the constant), ignoring case, spaces and underscores. -1728 for a name
	/// that isn't a setting; -1701 without one.
	static func target(_ request: AppleEventRequest) throws -> Target {
		guard let descriptor = request.descriptor(for: Keyword.directObject) else {
			throw OSAXError.missingParameter
		}
		if descriptor.descriptorType == typeEnumerated {
			let code = descriptor.enumCodeValue.fourCharString
			if code == allSettingsCode {
				return .all
			}
			if let setting = Setting.all.first(where: { $0.code == code }) {
				return .one(setting)
			}
			throw unknown(code)
		}
		guard [typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(descriptor.descriptorType),
		      let text = descriptor.stringValue
		else {
			throw OSAXError.coercionFailed
		}
		let name = normalized(text)
		if name == "allsettings" {
			return .all
		}
		if let setting = Setting.all.first(where: { [$0.constant, $0.name, $0.key].map(normalized).contains(name) }) {
			return .one(setting)
		}
		throw unknown(text)
	}

	static func normalized(_ name: String) -> String {
		name.lowercased().filter { $0 != " " && $0 != "_" }
	}

	private static func unknown(_ name: String) -> OSAXError {
		OSAXError(-1728, "There's no setting named \"\(name)\". The settings are \(Setting.all.map(\.constant).joined(separator: ", ")).")
	}

	/// A `setting info` record for `mtc_get all_settings`.
	static func info(_ setting: Setting, defaults: UserDefaults) -> RecordFields {
		RecordFields([
			(.code("pnam"), setting.constantDescriptor),
			(.code("key "), NSAppleEventDescriptor(string: setting.key)),
			(.code("val "), setting.value(in: defaults)),
			(.code("MTdv"), setting.defaultValue),
			(.code("dscr"), NSAppleEventDescriptor(string: setting.description)),
			(.code("MTid"), NSAppleEventDescriptor(boolean: setting.stored(defaults) == nil)),
		])
	}
}
