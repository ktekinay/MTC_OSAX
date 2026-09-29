import AppleEventCore
import Foundation
import JavaScriptCore

/// JSON through JavaScriptCore's `JSON.stringify` and `JSON.parse`, as SatimageOSAX made it: JavaScript's number
/// formatting, dictionary keys in their (hashing) order, and `replacer` functions.
enum JSON {
	/// One virtual machine for every call (making one took 0.3 ms); each call still gets its own context, so a
	/// replacer's globals don't outlive it. Commands run one at a time, on the main thread.
	nonisolated(unsafe) private static let machine = JSVirtualMachine()!

	/// Dates become ISO 8601 text and data base64 text (JSON has neither; SatimageOSAX returned nothing).
	/// `formatted` indents with tabs (SatimageOSAX added no returns). A `replacer` that isn't a JavaScript function is -1.
	/// The replacer is the script's own code and runs with no time limit (JavaScriptCore's public API has none), so
	/// `function(){for(;;){}}` blocks the app, and every script using it, until the app is quit.
	static func stringify(_ object: Any, formatted: Bool, replacer: String?) throws -> String {
		let context = JSContext(virtualMachine: machine)!
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
	/// `null` as `NSNull`. Error -1 for text that isn't JSON, -50 past `PropertyLists.maximumDepth`.
	///
	/// JavaScriptCore converts the whole value at once (asking it for each value in turn made a wrapper object and
	/// took its lock each time: most of `PlistFromJSON`'s time). It isn't told a depth limit, so text nested too
	/// deeply is refused before it's converted: freeing a million nested arrays would run out of stack.
	static func parse(_ text: String) throws -> Any {
		let context = JSContext(virtualMachine: machine)!
		let parse = context.objectForKeyedSubscript("JSON").objectForKeyedSubscript("parse")!
		guard let value = parse.call(withArguments: [text]), context.exception == nil else {
			throw PropertyLists.invalid
		}
		// Containers nested one level deeper than the limit can still be valid (if the innermost is empty), which
		// `PropertyLists.checkDepth` decides.
		guard nesting(of: text) <= PropertyLists.maximumDepth + 1 else {
			throw PropertyLists.tooDeep
		}
		return value.toObject() ?? NSNull()
	}

	/// How deeply arrays and objects nest in JSON text (brackets in strings aside), or more than `limit`
	/// once it's known to be.
	private static func nesting(of text: String, limit: Int = PropertyLists.maximumDepth + 1) -> Int {
		var depth = 0
		var deepest = 0
		var inString = false
		var escaped = false
		// UTF-16: the text usually comes from an `NSString`, which reads UTF-8 slowly.
		for unit in text.utf16 {
			if inString {
				if escaped {
					escaped = false
				} else if unit == 0x5C { // \
					escaped = true
				} else if unit == 0x22 { // "
					inString = false
				}
				continue
			}
			switch unit {
			case 0x22: // "
				inString = true
			case 0x5B, 0x7B: // [ {
				depth += 1
				deepest = max(deepest, depth)
				if deepest > limit {
					return deepest
				}
			case 0x5D, 0x7D: // ] }
				depth -= 1
			default:
				break
			}
		}
		return deepest
	}

	/// Replaces what JSON can't hold: dates with ISO 8601 text, data with base64 text; `missing value` (which
	/// `PlistFromJSON` makes of `null`) is `null` again. (Objective-C classes are checked: Swift casts such as
	/// `as Date` are slow for Objective-C objects.)
	static func jsonReady(_ object: Any) -> Any {
		switch object as AnyObject {
		case let dictionary as NSDictionary:
			return dictionary.mappingValues(jsonReady)
		case let array as NSArray:
			return array.map(jsonReady) as NSArray
		case let date as NSDate:
			return ISO8601DateFormatter().string(from: date as Date)
		case let data as NSData:
			return isMissingValue(data) ? NSNull() : data.base64EncodedString()
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
