import AppleEventCore
import Foundation
import TextMatching

/// MTC_OSAX's settings (an MTC_OSAX extension; SatimageOSAX had none), kept in the app's defaults domain, and the
/// "MTC_OSAX Settings" suite (event class `MTCs`) that reads and changes them: `mtc_get`, `mtc_set` and
/// `mtc_reset`. The code that uses a setting reads it through here, when it's needed, so a change applies from the
/// next command.
public enum Settings {
	// MARK: Reading

	/// `IdleTimeoutSeconds`: how long the app waits without commands before quitting; nil means never (0).
	/// Missing, negative or not a number: an hour.
	public static func idleTimeout(in defaults: UserDefaults) -> Duration? {
		IdleMonitor.timeout(in: defaults, key: Setting.idleTimeout.key, default: .seconds(Setting.defaultIdleTimeout))
	}

	/// `DollarReferences`: whether `$1`-style references are on when a command doesn't say. Off by default, and for
	/// anything `mtc_get` wouldn't report as a setting (the same rule for both).
	public static func dollarReferences(in defaults: UserDefaults) -> Bool {
		Setting.dollarReferences.stored(defaults)?.booleanValue ?? false
	}

	/// `RegexSyntax`: the regex syntax when a command doesn't say (`PCRE`, `RUBY`, …); `RUBY` if it's missing or
	/// not a syntax name.
	public static func regexSyntax(in defaults: UserDefaults) -> RegexSyntax {
		defaults.string(forKey: Setting.regexSyntax.key).flatMap(RegexSyntax.init(name:)) ?? .ruby
	}
}

/// A setting: how scripts name it, where it's stored, and what values it takes. Everything in it is immutable (the
/// descriptors are never changed, and the functions capture nothing), so the definitions can be shared.
struct Setting: @unchecked Sendable {
	/// The dictionary constant, e.g. `regex_syntax`, and its code.
	let constant: String
	let code: String
	/// The friendly name, e.g. "regex syntax".
	let name: String
	/// The `defaults` key, e.g. `RegexSyntax`.
	let key: String
	let description: String
	let defaultValue: NSAppleEventDescriptor
	/// The value in effect, as the code that uses the setting sees it; nil if nothing valid is stored.
	let stored: (UserDefaults) -> NSAppleEventDescriptor?
	/// Checks a script's value and converts it to what's stored: -1700 for the wrong kind of value, -50 for one
	/// that isn't allowed.
	let normalize: (NSAppleEventDescriptor) throws -> Any

	static let defaultIdleTimeout = 3600

	static let idleTimeout = Setting(
		constant: "idle_timeout", code: "MTsi", name: "idle timeout", key: "IdleTimeoutSeconds",
		description: "Seconds without commands before MTC_OSAX quits; 0 means never. It doesn't quit while property lists or XML documents are open.",
		defaultValue: NSAppleEventDescriptor(int32: Int32(defaultIdleTimeout)),
		stored: { defaults in
			// The rule IdleMonitor.timeout follows.
			IdleMonitor.seconds(in: defaults, key: "IdleTimeoutSeconds").map(number)
		},
		normalize: { value in
			guard ["long", "shor", "comp", "magn", "doub", "sing", "ldbl"].contains(value.descriptorType.fourCharString),
			      let seconds = value.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue
			else {
				throw OSAXError(-1700, "idle timeout must be a number of seconds.")
			}
			guard seconds.isFinite, seconds >= 0, seconds == seconds.rounded(), seconds <= Double(Int32.max) else {
				throw OSAXError(-50, "idle timeout must be a whole number of seconds, 0 or more (0 means never quit).")
			}
			return Int(seconds)
		}
	)

	static let dollarReferences = Setting(
		constant: "dollar_references", code: "MTsd", name: "dollar references", key: "DollarReferences",
		description: "Whether replacement templates also accept $0–$9, ${name} and $$ when a command doesn't say (the dollar references parameter).",
		defaultValue: NSAppleEventDescriptor(boolean: false),
		stored: { defaults in
			switch defaults.object(forKey: "DollarReferences") {
			case let number as NSNumber:
				return NSAppleEventDescriptor(boolean: number.boolValue)
			case let text as String where ["yes", "no", "true", "false", "1", "0"].contains(text.lowercased()):
				return NSAppleEventDescriptor(boolean: defaults.bool(forKey: "DollarReferences"))
			default:
				return nil
			}
		},
		normalize: { value in
			guard ["bool", "true", "fals"].contains(value.descriptorType.fourCharString) else {
				throw OSAXError(-1700, "dollar references must be true or false.")
			}
			return value.booleanValue
		}
	)

	static let regexSyntax = Setting(
		constant: "regex_syntax", code: "MTsr", name: "regex syntax", key: "RegexSyntax",
		description: "The regular expression syntax when a command doesn't give one: \(syntaxNames) (PCRE is MTC_OSAX's PCRE2 engine).",
		defaultValue: NSAppleEventDescriptor(string: RegexSyntax.ruby.rawValue),
		stored: { defaults in
			defaults.string(forKey: "RegexSyntax").flatMap(RegexSyntax.init(name:)).map { NSAppleEventDescriptor(string: $0.rawValue) }
		},
		normalize: { value in
			guard [typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16")].contains(value.descriptorType),
			      let text = value.stringValue
			else {
				throw OSAXError(-1700, "regex syntax must be text: \(syntaxNames).")
			}
			guard let syntax = RegexSyntax(name: text) else {
				throw OSAXError(-50, "regex syntax must be one of \(syntaxNames).")
			}
			return syntax.rawValue
		}
	)

	/// Every setting, in the order `mtc_get all_settings` lists them.
	static let all = [idleTimeout, dollarReferences, regexSyntax]

	private static var syntaxNames: String {
		RegexSyntax.allCases.map(\.rawValue).joined(separator: ", ")
	}

	/// A whole number as an integer, otherwise a real.
	static func number(_ value: Double) -> NSAppleEventDescriptor {
		if let integer = Int32(exactly: value) {
			return NSAppleEventDescriptor(int32: integer)
		}
		return NSAppleEventDescriptor(double: value)
	}

	/// The value in effect: the stored one if it's valid, otherwise the default.
	func value(in defaults: UserDefaults) -> NSAppleEventDescriptor {
		stored(defaults) ?? defaultValue
	}

	var constantDescriptor: NSAppleEventDescriptor {
		NSAppleEventDescriptor(enumCode: FourCharCode(fourCharString: code))
	}
}
