import AppleEventCore
import Foundation
import TextMatching

extension TextAdditions {
	static func searchCommands(_ context: TextContext) -> [CommandDefinition] {
		[
			CommandDefinition("find text", code: "SATIFINd") { request in
				try findText(request, context: context)
			},
			CommandDefinition("change", code: "SATIRPLl") { request in
				try change(request, context: context)
			},
			CommandDefinition("splittext", code: "SATISplt") { request in
				try splitText(request, context: context)
			},
			CommandDefinition("filter text", code: "SATIGPli") { request in
				try filterText(request, context: context)
			},
			CommandDefinition("re_compile", code: "SATICmpi") { request in
				try reCompile(request, context: context)
			},
		]
	}

	// MARK: find text

	/// What `using` asks for: the whole match (or a group number), one template, or a list of templates.
	private enum FindResult {
		case group(Int)
		case template(Template)
		case templates([Template])
	}

	private static func findText(_ request: AppleEventRequest, context: TextContext) throws -> NSAppleEventDescriptor? {
		let pattern = try request.requiredDirectParameter(as: String.self)
		let input = try TextInput(request, keyword: "$in ")
		let options = try SearchOptions(request, context: context, readsBackward: true)
		let searcher = try TextSearcher(pattern: pattern, options: options, context: context)

		// `using` only applies to regex searches.
		var result = FindResult.group(0)
		if options.regexp, let using = request.descriptor(for: "by  ") {
			if using.descriptorType == typeAEList {
				result = .templates(try [String](appleEventDescriptor: using).map {
					try Template($0, dollarReferences: options.dollarReferences)
				})
			} else if using.descriptorType == typeSInt32 || using.descriptorType == typeSInt16 {
				let number = try Int(appleEventDescriptor: using)
				guard number >= 0 else {
					throw Template.invalidBackreference
				}
				result = .group(number)
			} else {
				result = .template(try Template(try String(appleEventDescriptor: using), dollarReferences: options.dollarReferences))
			}
		}

		func describe(_ match: TextMatch, in text: UTF16Text) throws -> NSAppleEventDescriptor {
			var range = match.range
			let value: any AppleEventEncodable
			switch result {
			case let .group(number):
				guard number <= searcher.groupCount else {
					throw Template.tooBigBackreference
				}
				range = match.range(ofGroup: number) ?? match.range
				value = match.text(ofGroup: number, in: text)
			case let .template(template):
				value = try template.expand(match, in: text, groupCount: searcher.groupCount, namedGroups: searcher.namedGroups)
			case let .templates(templates):
				value = try templates.map {
					try $0.expand(match, in: text, groupCount: searcher.groupCount, namedGroups: searcher.namedGroups)
				}
			}
			if options.stringResult {
				return value.appleEventDescriptor
			}
			return AppleEventRecord([
				"mPos": range.lowerBound,
				"mLen": range.count,
				"mRes": value,
			]).appleEventDescriptor
		}

		// For a single string, no match is error -2763; in a list, it's missing value for that item.
		let isList: Bool
		if case .list = input { isList = true } else { isList = false }

		return try input.map { string in
			let text = UTF16Text(string)
			if options.allOccurrences {
				return try searcher.allMatches(in: text).map { try describe($0, in: text) }.appleEventDescriptor
			}
			guard let match = try searcher.firstMatch(in: text) else {
				if isList { return nil }
				throw notFoundError
			}
			return try describe(match, in: text)
		}
	}

	// MARK: change

	private static func change(_ request: AppleEventRequest, context: TextContext) throws -> NSAppleEventDescriptor? {
		let patternDescriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let replacementDescriptor = try request.requiredParameter("by  ", as: AnyDescriptor.self).descriptor
		let input = try TextInput(request, keyword: "$in ")
		let options = try SearchOptions(request, context: context)
		let verbatim = try request.parameter("RStr", default: false)
		let onlyGroup = request.descriptor(for: "back")

		// Pairs of pattern and replacement, applied one after the other.
		let pairs: [(pattern: String, replacement: String)]
		let patternsAreList = patternDescriptor.descriptorType == typeAEList
		let replacementsAreList = replacementDescriptor.descriptorType == typeAEList
		if patternsAreList {
			let patterns = try [String](appleEventDescriptor: patternDescriptor)
			if replacementsAreList {
				let replacements = try [String](appleEventDescriptor: replacementDescriptor)
				guard replacements.count >= patterns.count else {
					throw invalidOptionError
				}
				pairs = Array(zip(patterns, replacements))
			} else {
				let replacement = try String(appleEventDescriptor: replacementDescriptor)
				pairs = patterns.map { ($0, replacement) }
			}
		} else {
			guard !replacementsAreList else {
				throw invalidOptionError
			}
			pairs = [(try String(appleEventDescriptor: patternDescriptor), try String(appleEventDescriptor: replacementDescriptor))]
		}

		let searchers = try pairs.map { pair in
			try TextSearcher(pattern: pair.pattern, options: options, context: context)
		}

		/// All the pairs applied to `string`, and the number of replacements.
		func applyAll(to string: String) throws -> (text: String, count: Int) {
			var current = string
			var count = 0
			for (pair, searcher) in zip(pairs, searchers) {
				let changed = try replace(in: current, with: pair.replacement, searcher: searcher, verbatim: verbatim, onlyGroup: onlyGroup)
				current = changed.text
				count += changed.count
			}
			return (current, count)
		}

		// A file is rewritten in its own encoding, keeping its byte-order mark; the result is the number of changes.
		if case let .file(url) = input {
			let contents = try FileText.read(url)
			let changed = try applyAll(to: contents.text)
			if changed.count > 0 {
				let data = try FileText.encode(changed.text, encoding: contents.encoding, missingCharacter: nil)
				try FileText.write(contents.byteOrderMark + data, to: url, append: false)
			}
			return changed.count.appleEventDescriptor
		}
		return try input.map { string in
			try applyAll(to: string).text.appleEventDescriptor
		}
	}

	private static func replace(
		in string: String,
		with replacement: String,
		searcher: TextSearcher,
		verbatim: Bool,
		onlyGroup: NSAppleEventDescriptor?
	) throws -> (text: String, count: Int) {
		// The template is checked even when nothing matches, as SatimageOSAX did (-208 for "\\q" either way).
		let options = searcher.options
		let template = options.regexp && !verbatim ? try Template(replacement, dollarReferences: options.dollarReferences) : nil
		let text = UTF16Text(string)
		let matches = try searcher.allMatches(in: text)
		guard !matches.isEmpty else {
			return (string, 0)
		}

		// `only backreference`: a group number, or a group name.
		var groupNumbers = [0]
		if let onlyGroup, options.regexp {
			if onlyGroup.descriptorType == typeSInt32 || onlyGroup.descriptorType == typeSInt16 {
				let number = try Int(appleEventDescriptor: onlyGroup)
				guard number >= 0 else {
					throw Template.invalidBackreference
				}
				groupNumbers = [number]
			} else {
				groupNumbers = searcher.namedGroups[try String(appleEventDescriptor: onlyGroup)] ?? []
			}
		}

		var result: [UInt16] = []
		var position = 0
		var count = 0
		for match in matches {
			// A group that didn't take part leaves this match as it is (Satimage returned no result at all).
			// So does a group before the end of the previous replacement (a capture inside a lookbehind can be).
			guard let target = groupNumbers.last(where: { match.range(ofGroup: $0) != nil }).flatMap(match.range(ofGroup:)),
			      target.lowerBound >= position
			else {
				continue
			}
			count += 1
			let expanded = try template?.expand(match, in: text, groupCount: searcher.groupCount, namedGroups: searcher.namedGroups) ?? replacement
			result += text.units[position ..< target.lowerBound]
			result += Array(expanded.utf16)
			position = target.upperBound
		}
		result += text.units[position...]
		return (UTF16Text.string(result), count)
	}

	// MARK: splittext

	private static func splitText(_ request: AppleEventRequest, context: TextContext) throws -> NSAppleEventDescriptor? {
		let input = try TextInput(request, keyword: Keyword.directObject)
		let separator = try request.requiredParameter("by  ", as: String.self)
		let options = try SearchOptions(request, context: context)
		let searcher = try TextSearcher(pattern: separator, options: options, context: context)

		return try input.map { string in
			let text = UTF16Text(string)
			var pieces: [String] = []
			var position = 0
			for match in try searcher.allMatches(in: text) {
				pieces.append(text[position ..< match.range.lowerBound])
				position = match.range.upperBound
			}
			pieces.append(text[position ..< text.count])
			return pieces.appleEventDescriptor
		}
	}

	// MARK: re_compile

	/// Checks a pattern. Returns the pattern itself if it compiles, the engine's error code if not.
	private static func reCompile(_ request: AppleEventRequest, context: TextContext) throws -> NSAppleEventDescriptor? {
		let pattern = try request.requiredDirectParameter(as: String.self)
		var syntax = context.regexSyntaxDefault()
		if let name = try request.parameter("synt", as: String.self) {
			guard let parsed = RegexSyntax(name: name) else {
				throw invalidOptionError
			}
			syntax = parsed
		}
		do {
			_ = try context.regexCache.regex(pattern, syntax: syntax)
		} catch {
			throw OSAXError(error)
		}
		return pattern.appleEventDescriptor
	}
}
