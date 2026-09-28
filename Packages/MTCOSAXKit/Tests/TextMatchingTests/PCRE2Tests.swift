import CPCRE2
import Testing

/// The vendored PCRE2 builds and matches UTF-16 text.
struct PCRE2Tests {
	@Test func version() {
		var buffer = [UInt16](repeating: 0, count: 32)
		let length = pcre2_config_16(UInt32(PCRE2_CONFIG_VERSION), &buffer)
		#expect(String(decoding: buffer.prefix(Int(length) - 1), as: UTF16.self).hasPrefix("10.49"))
	}

	@Test func compilesAndMatches() throws {
		let pattern = Array("(?<word>\\w+)é".utf16)
		var error: Int32 = 0
		var offset = 0
		let code = try #require(pcre2_compile_16(pattern, pattern.count, UInt32(PCRE2_UTF | PCRE2_UCP), &error, &offset, nil))
		defer { pcre2_code_free_16(code) }
		let subject = Array("😀 café".utf16)
		let data = try #require(pcre2_match_data_create_from_pattern_16(code, nil))
		defer { pcre2_match_data_free_16(data) }
		#expect(pcre2_match_16(code, subject, subject.count, 0, 0, data, nil) == 2)
		let vector = try #require(pcre2_get_ovector_pointer_16(data))
		// UTF-16 offsets: the emoji is two code units, then a space.
		#expect(vector[0] == 3)
		#expect(vector[1] == 7)
	}
}
