import COnigmo
import Foundation

/// A compiled Onigmo pattern.
///
/// Matches Satimage's build of Onigmo (see the line-end fixtures): CR, LF, NEL, U+2028 and U+2029 are line ends,
/// negated classes exclude `\n` and `\r` in every syntax unless `newlineInNegativeCC` is given, and unnamed groups
/// are numbered alongside named ones.
final class OnigmoEngine: RegexEngine {
	let groupCount: Int
	let namedGroups: [String: [Int]]
	private let flags: RegexFlags

	private let regex: OnigRegex
	/// Onigmo keeps a pointer to the syntax, so the modified copy must live as long as the regex.
	private let customSyntax: UnsafeMutablePointer<OnigSyntaxType>

	init(_ pattern: String, syntax: RegexSyntax, flags: RegexFlags) throws(RegexError) {
		guard let onigmoSyntax = syntax.onigmoSyntax else {
			throw RegexError(code: -1, message: "not an Onigmo syntax")
		}
		// DOTALL is PCRE's name; with Onigmo, MULTILINE does this.
		guard !flags.contains(.dotAll) else {
			throw RegexError(code: -1, message: "DOTALL is only for PCRE")
		}
		self.flags = flags

		let syntaxCopy = UnsafeMutablePointer<OnigSyntaxType>.allocate(capacity: 1)
		onig_copy_syntax(syntaxCopy, mtc_onig_syntax(onigmoSyntax))
		var behavior = onig_get_syntax_behavior(syntaxCopy) | MTCOnigSynNotNewlineInNegativeCC
		if flags.contains(.newlineInNegativeCC) {
			behavior &= ~MTCOnigSynNotNewlineInNegativeCC
		}
		onig_set_syntax_behavior(syntaxCopy, behavior)
		customSyntax = syntaxCopy

		var compiled: OnigRegex?
		var errorInfo = OnigErrorInfo()
		let units = Array(pattern.utf16)
		// The message is made inside the closure: the error info can point into the pattern's buffer.
		let (status, message) = units.withUnsafeBytes { bytes in
			let start = bytes.baseAddress!.assumingMemoryBound(to: OnigUChar.self)
			let status = onig_new(&compiled, start, start + bytes.count, flags.onigmoCompileOptions, mtc_onig_encoding_satimage_utf16le(),
			                      syntaxCopy, &errorInfo)
			return (status, status == ONIG_NORMAL ? nil : Self.message(for: Int(status), info: &errorInfo))
		}
		guard status == ONIG_NORMAL, let compiled else {
			syntaxCopy.deallocate()
			throw RegexError(code: Int(status), message: message ?? "")
		}
		regex = compiled
		groupCount = Int(onig_number_of_captures(compiled))
		namedGroups = Self.namedGroups(of: compiled)
	}

	deinit {
		onig_free(regex)
		customSyntax.deallocate()
	}

	/// Runs `onig_search`: the text seen by the regex ends at `bounds.upperBound`, but starts at the beginning
	/// of the whole text, so lookbehind and `^` see what comes before `bounds.lowerBound`.
	func search(_ text: UTF16Text, bounds: Range<Int>, start: Int, limit: Int) throws(RegexError) -> RegexMatch? {
		Self.setLimits()
		guard let region = onig_region_new() else {
			throw RegexError(code: Int(ONIGERR_MEMORY), message: "out of memory")
		}
		defer { onig_region_free(region, 1) }

		let position = text.units.withUnsafeBytes { bytes -> OnigPosition in
			// Empty text has no buffer. Any non-null address will do: with the start equal to the end, Onigmo reads
			// nothing there (it points empty subjects at an address of its own).
			let base = bytes.baseAddress?.assumingMemoryBound(to: OnigUChar.self) ?? UnsafePointer(bitPattern: 1)!
			return onig_search(
				regex,
				base,
				base + bounds.upperBound * 2,
				base + start * 2,
				base + limit * 2,
				region,
				flags.onigmoSearchOptions
			)
		}
		guard position >= 0 else {
			// Anything but "no match" is an error, such as ONIGERR_MATCH_STACK_LIMIT_OVER (-15).
			guard position == ONIG_MISMATCH else {
				if mtc_onig_took_too_long() != 0 {
					throw RegexDeadline.tookTooLong(code: Int(position))
				}
				var info = OnigErrorInfo()
				throw RegexError(code: Int(position), message: Self.message(for: Int(position), info: &info))
			}
			return nil
		}
		let groups = (0 ..< Int(region.pointee.num_regs)).map { index -> Range<Int>? in
			let begin = region.pointee.beg[index]
			let end = region.pointee.end[index]
			return begin < 0 ? nil : Int(begin) / 2 ..< Int(end) / 2
		}
		return RegexMatch(groups: groups)
	}

	/// Onigmo's backtracking stack is unlimited by default: a pattern like `(a|b)*c` over a huge text could take all
	/// the memory. Five million entries (a few hundred MB) is far more than ordinary patterns need. (Time is limited by
	/// `RegexDeadline`: `(a*)*b` is still exponential, as it was in SatimageOSAX.)
	static let matchStackLimit: UInt32 = 5_000_000

	private static func setLimits() {
		_ = limits
	}

	private static let limits: Void = {
		_ = onig_set_match_stack_limit_size(matchStackLimit)
	}()

	private static func message(for code: Int, info: inout OnigErrorInfo) -> String {
		var buffer = [OnigUChar](repeating: 0, count: Int(MTCOnigMaxErrorMessageLength) + 1)
		let length = mtc_onig_error_message(&buffer, OnigPosition(code), &info)
		// Error messages quote the pattern in its own encoding (UTF-16LE); decode leniently.
		let bytes = Array(buffer.prefix(Int(max(length, 0))))
		return String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
	}

	private static func namedGroups(of regex: OnigRegex) -> [String: [Int]] {
		final class Collector {
			var names: [String: [Int]] = [:]
		}
		let collector = Collector()
		_ = onig_foreach_name(regex, { nameStart, nameEnd, count, groups, _, context in
			let collector = Unmanaged<Collector>.fromOpaque(context!).takeUnretainedValue()
			let byteCount = nameEnd! - nameStart!
			let name = UnsafeRawPointer(nameStart!).withMemoryRebound(to: UInt16.self, capacity: byteCount / 2) {
				String(decoding: UnsafeBufferPointer(start: $0, count: byteCount / 2), as: UTF16.self)
			}
			collector.names[name] = (0 ..< Int(count)).map { Int(groups![$0]) }
			return 0
		}, Unmanaged.passUnretained(collector).toOpaque())
		return collector.names
	}
}
