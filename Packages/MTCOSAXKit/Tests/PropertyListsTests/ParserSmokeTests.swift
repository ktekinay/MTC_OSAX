import CTOML
import CYAML
import Testing

/// The vendored YAML and TOML parsers build and parse.
@MainActor
struct ParserSmokeTests {
	@Test func libyaml() {
		#expect(String(cString: yaml_get_version_string()) == "0.2.5")
		var parser = yaml_parser_t()
		#expect(yaml_parser_initialize(&parser) == 1)
		defer { yaml_parser_delete(&parser) }
		let text = Array("a: [1, 2]\n".utf8)
		text.withUnsafeBufferPointer { yaml_parser_set_input_string(&parser, $0.baseAddress, $0.count) }
		var document = yaml_document_t()
		#expect(yaml_parser_load(&parser, &document) == 1)
		defer { yaml_document_delete(&document) }
		#expect(yaml_document_get_root_node(&document)?.pointee.type == YAML_MAPPING_NODE)
	}

	@Test func tomlc17() {
		let text = "a = 1\n[b]\nc = 2026-09-28T14:30:00Z\n"
		let result = text.withCString { toml_parse($0, Int32(strlen($0))) }
		defer { toml_free(result) }
		#expect(result.ok)
		#expect(toml_get(result.toptab, "a").u.int64 == 1)
		#expect(toml_seek(result.toptab, "b.c").type == TOML_DATETIMETZ)
		let bad = "a = ".withCString { toml_parse($0, Int32(strlen($0))) }
		defer { toml_free(bad) }
		#expect(!bad.ok)
	}
}
