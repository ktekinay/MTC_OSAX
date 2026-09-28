import AppleEventCore
import Foundation
import JavaScriptCore

/// JSON through JavaScriptCore's `JSON.stringify` and `JSON.parse`, as SatimageOSAX made it: JavaScript's number
/// formatting, dictionary keys in their (hashing) order, and `replacer` functions.
enum JSON {
	/// Dates become ISO 8601 text and data base64 text (JSON has neither; SatimageOSAX returned nothing).
	/// `formatted` indents with tabs (SatimageOSAX added no returns). A `replacer` that isn't a JavaScript function is -1.
	static func stringify(_ object: Any, formatted: Bool, replacer: String?) throws -> String {
		let context = JSContext()!
		let value = JSValue(object: jsonReady(object), in: context)!
		var replacerFunction: JSValue = JSValue(undefinedIn: context)
		if let replacer {
			guard let function = context.evaluateScript("(\(replacer))"), context.exception == nil, function.isObject else {
				throw PropertyLists.invalid
			}
			replacerFunction = function
		}
		let stringify = context.objectForKeyedSubscript("JSON").objectForKeyedSubscript("stringify")!
		let space: Any = formatted ? "\t" : JSValue(undefinedIn: context)!
		guard let result = stringify.call(withArguments: [value, replacerFunction, space]), context.exception == nil, result.isString else {
			throw PropertyLists.invalid
		}
		return result.toString()
	}

	/// JSON as Foundation objects: every number a real (as SatimageOSAX made them), objects' keys in their order,
	/// `null` as `NSNull`. Error -1 for text that isn't JSON.
	static func parse(_ text: String) throws -> Any {
		let context = JSContext()!
		let parse = context.objectForKeyedSubscript("JSON").objectForKeyedSubscript("parse")!
		guard let value = parse.call(withArguments: [text]), context.exception == nil else {
			throw PropertyLists.invalid
		}
		return try foundation(value)
	}

	/// -50 past `PropertyLists.maximumDepth` (JavaScriptCore itself takes a million levels).
	private static func foundation(_ value: JSValue, depth: Int = 0) throws -> Any {
		guard depth <= PropertyLists.maximumDepth else { throw PropertyLists.tooDeep }
		if value.isNull || value.isUndefined {
			return NSNull()
		}
		if value.isBoolean {
			return value.toBool() ? kCFBooleanTrue! : kCFBooleanFalse!
		}
		if value.isNumber {
			return NSNumber(value: value.toDouble())
		}
		if value.isString {
			return value.toString() as NSString
		}
		if value.isArray {
			let count = Int(value.objectForKeyedSubscript("length").toInt32())
			return try (0 ..< count).map { try foundation(value.objectAtIndexedSubscript($0), depth: depth + 1) } as NSArray
		}
		let dictionary = NSMutableDictionary()
		let keys = value.context.objectForKeyedSubscript("Object").objectForKeyedSubscript("keys").call(withArguments: [value])
		for key in (keys?.toArray() as? [String]) ?? [] {
			dictionary[key] = try foundation(value.objectForKeyedSubscript(key), depth: depth + 1)
		}
		return dictionary
	}

	/// Replaces what JSON can't hold: dates with ISO 8601 text, data with base64 text.
	static func jsonReady(_ object: Any) -> Any {
		switch object {
		case let dictionary as NSDictionary:
			return dictionary.mappingValues(jsonReady)
		case let array as NSArray:
			return array.map(jsonReady) as NSArray
		case let date as Date:
			return ISO8601DateFormatter().string(from: date)
		case let data as Data:
			return data.base64EncodedString()
		default:
			return object
		}
	}

	/// The hidden `PlistToJavaScript`: JSON with a space after each comma, as SatimageOSAX wrote it.
	static func javaScript(_ object: Any) -> String {
		switch object {
		case let dictionary as NSDictionary:
			let entries = dictionary.allKeys.map { key in "\(scalar(key)):\(javaScript(dictionary[key]!))" }
			return "{" + entries.joined(separator: ", ") + "}"
		case let array as NSArray:
			return "[" + array.map(javaScript).joined(separator: ", ") + "]"
		default:
			return scalar(object)
		}
	}

	private static func scalar(_ object: Any) -> String {
		(try? stringify(object, formatted: false, replacer: nil)) ?? "null"
	}
}
