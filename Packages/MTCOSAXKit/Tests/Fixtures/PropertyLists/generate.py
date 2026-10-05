# Generates cases.json for the PropertyList and Pool suites, recorded from SatimageOSAX. Run: python3 generate.py
# Cases open files in Input/ (made by make_inputs.py) through $FILES and write to $TMP. Each case closes the
# documents it opens, and cases that change the default pool set it back, since SatimageOSAX keeps both between
# scripts. A case that stops at an error may leave a document open, so cases that list documents use their own pool.
import json, os

cases, names = [], set()
def case(name, *lines):
    assert name.lower() not in names, name
    names.add(name.lower())
    cases.append({"name": name, "script": "\n".join(lines)})

def q(text):
    """An AppleScript string literal."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

F = lambda name: f'(POSIX file "$FILES/{name}")'
T = lambda name: f'(POSIX file "$TMP/{name}")'
OPEN = lambda name="simple.plist", var="p": f"set {var} to PlistOpen {F(name)}"
CLOSE = "PlistClose p"
DATE = 'date "Saturday, January 1, 2000 at 12:00:00 AM"'

# Your scripts
case("script-prefs-read", f"set p to PlistOpen ({F('prefs.plist')} as alias)", 'PlistGet p key "String_Utils_Script_Path"', CLOSE)
case("script-prefs-new-save", "set p to PlistNew", 'PlistSet p key "String_Utils_Script_Path" to "/Users/me/x.scpt"',
     f"PlistSave p in {T('script-prefs.plist')}", CLOSE, f"set p to PlistOpen {T('script-prefs.plist')}", "PlistGet p", CLOSE)
case("script-prefs-update", f"set p to PlistNew {{String_Utils_Script_Path:\"old\"}}", f"PlistSave p in {T('update.plist')}", CLOSE,
     f"set p to PlistOpen {T('update.plist')}", 'PlistSet p key "String_Utils_Script_Path" to "new"', f"PlistSave p in {T('update.plist')}", CLOSE,
     f"set p to PlistOpen {T('update.plist')}", 'PlistGet p key "String_Utils_Script_Path"', CLOSE)
case("script-spamcop", OPEN("messages.plist"), 'PlistGet p key "MessageList"', CLOSE)

# PlistNew and the values it takes
VALUES = {
    "empty": None, "record": '{a:1, b:"two", c:2.5}', "list": '{1, "two", 2.5, true}', "text": '"hello"', "integer": "42",
    "real": "2.5", "negative": "-7", "boolean": "false", "date": DATE, "nested": '{a:{b:{c:{1, {d:"deep"}}}}}',
    "keywords": '{name:"x", id:3}', "missing-value": "{a:missing value, b:1}", "list-missing-value": "{1, missing value, 2}",
    "big-real": "1.0E+20", "empty-record-in-list": "{{}, {a:1}}", "unicode": '{t:"café ☃"}', "alias": f"{F('prefs.plist')} as alias",
    "file": F("prefs.plist"), "data": "«data rdat00010203»", "type": "{t:integer}", "record-with-list-key": '{|a b|:1, |c/d|:2}',
}
# Aliases and file references are stored as flattened descriptors, whose bytes name the machine's volume and the
# recording folder, so they can't be replayed elsewhere; unit tests cover them.
del VALUES["alias"], VALUES["file"]
for name, value in VALUES.items():
    new = "set p to PlistNew" + ("" if value is None else f" {value}")
    case(f"new-{name}", new, "PlistType p", "PlistGetXML p", "PlistGet p", CLOSE)
case("new-untyped-record", '{a:1}'.join(["set p to PlistNew ", " without typed"]), "PlistGetXML p", "PlistGet p", CLOSE)
case("new-untyped-text", 'set p to PlistNew {t:"x"} without typed', "PlistGetXML p", 'PlistGet p key "t" as text', CLOSE)
for name, value in [("real", "2.5"), ("boolean", "true"), ("date", DATE), ("list", "{1, 2}"), ("integer", "7")]:
    case(f"new-untyped-{name}", f"set p to PlistNew {{v:{value}}} without typed", "PlistGetXML p", 'PlistGet p key "v"', CLOSE)

# PlistOpen
case("open-xml", OPEN(), "PlistType p", "PlistCount p", "PlistGet p", CLOSE)
case("open-binary", OPEN("binary.plist"), "PlistBinaryFormat p", "PlistGet p", CLOSE)
case("open-xml-format", OPEN(), "PlistBinaryFormat p", CLOSE)
case("open-array", OPEN("array.plist"), "PlistType p", "PlistGet p", CLOSE)
case("open-big-numbers", OPEN("big.plist"), "PlistGet p", "PlistGetXML p", CLOSE)
case("open-invalid", OPEN("invalid.plist"))
case("open-missing", OPEN("nope.plist"))
case("open-alias", f"set p to PlistOpen ({F('simple.plist')} as alias)", "PlistCount p", CLOSE)
case("open-path-string", 'set p to PlistOpen "$FILES/simple.plist"', "PlistCount p", CLOSE)
XML_DICT = q('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>a</key><integer>1</integer></dict></plist>')
XML_ARRAY = q('<plist version="1.0"><array><string>x</string></array></plist>')
case("open-from-string", f"set p to PlistOpen from string {XML_DICT}", "PlistGet p", CLOSE)
case("open-from-string-array", f"set p to PlistOpen from string {XML_ARRAY}", "PlistGet p", CLOSE)
case("open-from-string-invalid", 'set p to PlistOpen from string "not xml"')
case("open-twice", OPEN(), OPEN(var="r"), "PlistEqual p to r", CLOSE, "PlistClose r")
case("open-no-parameter", "PlistOpen")

# PlistType, PlistCount
for key in ("name", "count", "ratio", "enabled", "disabled", "when", "blob", "list", "dict", "emptyList", "emptyText"):
    case(f"type-{key}", OPEN(), f'PlistType (PlistChild p key "{key}")', CLOSE)
case("count-array", OPEN(), 'PlistCount (PlistChild p key "list")', CLOSE)
case("count-empty-dict", OPEN(), 'PlistCount (PlistChild p using "dict/empty")', CLOSE)
case("count-string", OPEN(), 'PlistCount (PlistChild p key "name")', CLOSE)
case("count-list", OPEN(), 'PlistCount {PlistChild p key "list", PlistChild p key "dict"}', CLOSE)

# PlistChild and paths
for name, spec in [
    ("key", 'key "dict"'), ("index", 'index 1'), ("using-key", 'using "dict"'), ("using-path", 'using "dict/y/z"'),
    ("using-index", 'using "list[5]/nested"'), ("using-array-of-dicts", 'using "people[2]/first"'), ("using-leading-slash", 'using "/dict/x"'),
    ("using-trailing-slash", 'using "dict/"'), ("using-index-only", 'using "[1]"'), ("using-bad-index", 'using "list[9]"'),
    ("using-zero-index", 'using "list[0]"'), ("using-missing-key", 'using "dict/nope"'), ("using-garbage", 'using "list[x"'),
    ("missing-key", 'key "nope"'), ("index-out-of-range", 'index 99'), ("index-zero", 'index 0'), ("index-negative", 'index -1'),
    ("key-list", 'key {"name", "count"}'), ("index-list", 'index {1, 2}'), ("no-selector", ''), ("key-and-index", 'key "name" index 1'),
]:
    case(f"child-{name}", OPEN(), f"set c to PlistChild p {spec}".rstrip(), "PlistGet c", CLOSE)
case("child-array-index", OPEN(), 'set c to PlistChild (PlistChild p key "list") index 2', "PlistGet c", CLOSE)
case("child-array-key", OPEN(), 'PlistChild (PlistChild p key "list") key "a"', CLOSE)
case("child-of-string", OPEN(), 'PlistChild (PlistChild p key "name") index 1', CLOSE)
case("child-keys-with-slash", OPEN("keys.plist"), 'PlistGet p key "a/b"', 'PlistGet p key "c[1]"', 'PlistGet p key ""', CLOSE)
case("child-path-keys-with-slash", OPEN("keys.plist"), 'PlistGet p using "nest/a/b/c"', CLOSE)
case("child-path-escaped", OPEN("keys.plist"), 'PlistGet p using "nest/a\\\\/b/c"', CLOSE)

# PlistGet
for name, spec in [
    ("whole", ""), ("key", 'key "name"'), ("index", "index 2"), ("using", 'using "people[1]/age"'), ("date", 'key "when"'),
    ("data", 'key "blob"'), ("real", 'key "ratio"'), ("boolean", 'key "enabled"'), ("list", 'key "list"'), ("dict", 'key "dict"'),
    ("empty-dict", 'using "dict/empty"'), ("empty-list", 'key "emptyList"'), ("unicode", 'key "unicode"'), ("missing-key", 'key "nope"'),
    ("key-list", 'key {"name", "count"}'), ("key-list-missing", 'key {"name", "nope"}'), ("data-as-text", 'key "blob" as text'),
    ("text-as-integer", 'key "count" as integer'),
]:
    case(f"get-{name}", OPEN(), f"PlistGet p {spec}".rstrip(), CLOSE)
case("get-big-numbers", OPEN("big.plist"), 'PlistGet p key "big"', 'PlistGet p key "huge"', 'PlistGet p key "small"', CLOSE)
case("get-xml-child", OPEN(), 'PlistGetXML (PlistChild p key "dict")', CLOSE)
case("get-xml-string", OPEN(), 'PlistGetXML (PlistChild p key "name")', CLOSE)
case("get-keys", OPEN(), "PlistGetKeys p", CLOSE)
case("get-keys-child", OPEN(), 'PlistGetKeys (PlistChild p key "dict")', CLOSE)
case("get-keys-array", OPEN(), 'PlistGetKeys (PlistChild p key "list")', CLOSE)

# PlistSet
N = 'set p to PlistNew {a:1, l:{"x", "y"}, d:{e:1}}'
for name, lines in [
    ("key-new", ['PlistSet p key "b" to "new"']), ("key-existing", ['PlistSet p key "a" to 2']),
    ("index", ['PlistSet (PlistChild p key "l") index 2 to "z"']), ("index-append", ['PlistSet (PlistChild p key "l") index 3 to "z"']),
    ("index-out-of-range", ['PlistSet (PlistChild p key "l") index 9 to "z"']), ("using", ['PlistSet p using "d/e" to 5']),
    ("using-new-key", ['PlistSet p using "d/f" to 6']), ("using-missing-path", ['PlistSet p using "q/r" to 7']),
    ("using-index", ['PlistSet p using "l[1]" to "w"']), ("to-list", ['PlistSet p key "a" to {1, 2}']),
    ("to-record", ['PlistSet p key "a" to {x:1}']), ("to-date", [f'PlistSet p key "a" to {DATE}']),
    ("to-reference", ['PlistSet p key "copy" to (PlistChild p key "d")', 'PlistSet (PlistChild p key "d") key "e" to 99']),
    ("to-reference-other-document", ['set r to PlistNew {z:1}', 'PlistSet p key "other" to r', 'PlistClose r']),
    ("missing-values-suppressed", ['PlistSet p key "d" to {e:missing value, f:2}']),
    ("missing-values-kept", ['PlistSet p key "d" to {e:missing value, f:2} without suppressing']),
    ("missing-value-list", ['PlistSet p key "l" to {1, missing value, 2}']), ("untyped", ['PlistSet p key "a" to 5 without typed']),
    ("key-on-array", ['PlistSet (PlistChild p key "l") key "x" to 1']), ("index-on-dict", ['PlistSet p index 1 to 1']),
    ("no-to", ['PlistSet p key "a"']), ("no-selector", ['PlistSet p to 3']),
    ("key-list", ['PlistSet p key {"a", "b"} to {10, 20}']),
    ("key-list-missing-value", ['PlistSet p key {"a", "b"} to {5, missing value}']),
    ("key-list-missing-value-kept", ['PlistSet p key {"a", "b"} to {5, missing value} without suppressing']),
    ("key-list-remove-existing", ['PlistSet p key {"a", "d"} to {missing value, 3}']),
    ("untyped-real", ['PlistSet p key "a" to 2.5 without typed']), ("untyped-text", ['PlistSet p key "a" to "t" without typed']),
]:
    case(f"set-{name}", N, *lines, "PlistGetXML p", CLOSE)

# PlistNewChild
for name, lines in [
    ("dict-key", ['set c to PlistNewChild "v" at p key "b"', "PlistGet c"]),
    ("dict-existing-key", ['PlistNewChild "v" at p key "a"']),
    ("dict-no-key", ['PlistNewChild "v" at p']),
    ("array-append", ['set c to PlistNewChild "z" at (PlistChild p key "l")', "PlistGet c"]),
    ("array-index", ['PlistNewChild "z" at (PlistChild p key "l") index 1']),
    ("array-index-end", ['PlistNewChild "z" at (PlistChild p key "l") index 3']),
    ("array-index-too-big", ['PlistNewChild "z" at (PlistChild p key "l") index 5']),
    ("default-record", ['set c to PlistNewChild at p key "r"', "PlistType c"]),
    ("record-then-fill", ['set c to PlistNewChild {} at p key "r"', 'PlistSet c key "k" to 1']),
    ("using", ['PlistNewChild "v" at p using "d/f"']),
    ("reference", ['PlistNewChild (PlistChild p key "d") at p key "copy"']),
    ("untyped", ['PlistNewChild 5 at p key "u" without typed']),
    ("no-at", ['PlistNewChild "v" key "b"']),
]:
    case(f"newchild-{name}", N, *lines, "PlistGetXML p", CLOSE)

# PlistRemoveChild
for name, lines in [
    ("key", ['PlistRemoveChild p key "a"']), ("index", ['PlistRemoveChild (PlistChild p key "l") index 1']),
    ("using", ['PlistRemoveChild p using "d/e"']), ("missing-key", ['PlistRemoveChild p key "nope"']),
    ("index-out-of-range", ['PlistRemoveChild (PlistChild p key "l") index 5']),
    ("then-use-removed", ['set c to PlistChild p key "d"', 'PlistRemoveChild p key "d"', "PlistGet c"]),
    ("no-selector", ["PlistRemoveChild p"]),
]:
    case(f"remove-{name}", N, *lines, "PlistGetXML p", CLOSE)

# PlistEqual, PlistExist, PlistMatch
case("equal-same", N, 'set r to PlistNew {a:1, l:{"x", "y"}, d:{e:1}}', "PlistEqual p to r", CLOSE, "PlistClose r")
case("equal-different", N, 'set r to PlistNew {a:2}', "PlistEqual p to r", CLOSE, "PlistClose r")
case("equal-children", OPEN(), 'PlistEqual (PlistChild p using "people[1]/age") to (PlistChild p using "people[3]/age")', CLOSE)
case("equal-integer-real", 'set p to PlistNew {a:1}', 'set r to PlistNew {a:1.0}', "PlistEqual p to r", CLOSE, "PlistClose r")
for name, lines in [
    ("array", ['PlistExist "y" in (PlistChild p key "l")']), ("array-missing", ['PlistExist "q" in (PlistChild p key "l")']),
    ("dict", ['PlistExist 1 in p']), ("dict-record", ['PlistExist {e:1} in p']), ("several", ['PlistExist {"x", "y"} in (PlistChild p key "l") with several values']),
    ("list-without-several", ['PlistExist {"x", "y"} in (PlistChild p key "l")']), ("case", ['PlistExist "X" in (PlistChild p key "l")']),
    ("number-as-text", ['PlistExist "1" in p']),
]:
    case(f"exist-{name}", N, *lines, CLOSE)
for name, spec in [("key", 'key "pet"'), ("key-value", 'key "age" value 30'), ("key-value-text", 'key "first" value "Bob"'),
                   ("none", 'key "zzz"'), ("value-type", 'key "age" value "30"'), ("using", 'using "pet"')]:
    case(f"match-{name}", OPEN(), f'PlistMatch (PlistChild p key "people") {spec}', CLOSE)
case("match-not-array", OPEN(), 'PlistMatch p key "name"', CLOSE)

# PlistAdd
for name, lines in [
    ("arrays-after", ['set r to PlistNew {"a", "b"}', 'set s to PlistNew {"c"}', "PlistAdd s after r", "PlistGet r", "PlistClose r", "PlistClose s"]),
    ("arrays-before", ['set r to PlistNew {"a", "b"}', 'set s to PlistNew {"c"}', "PlistAdd s before r", "PlistGet r", "PlistClose r", "PlistClose s"]),
    ("dicts", ['set r to PlistNew {a:1, b:2}', 'set s to PlistNew {b:3, c:4}', "PlistAdd s after r", "PlistGetXML r", "PlistClose r", "PlistClose s"]),
    ("dicts-before", ['set r to PlistNew {a:1, b:2}', 'set s to PlistNew {b:3, c:4}', "PlistAdd s before r", "PlistGetXML r", "PlistClose r", "PlistClose s"]),
    ("list", ['set r to PlistNew {"a"}', 'PlistAdd {"b", "c"} after r', "PlistGet r", "PlistClose r"]),
    ("record", ['set r to PlistNew {a:1}', "PlistAdd {b:2} after r", "PlistGetXML r", "PlistClose r"]),
    ("mismatch", ['set r to PlistNew {"a"}', "PlistAdd {b:2} after r", "PlistClose r"]),
    ("no-target", ['set r to PlistNew {"a"}', 'PlistAdd {"b"}', "PlistClose r"]),
]:
    case(f"add-{name}", *lines)

# PlistSave, PlistBinaryFormat, PlistURL, PlistDocument
case("save-xml", N, f"PlistSave p in {T('save-xml.plist')}", CLOSE, f"readtext {T('save-xml.plist')}")
case("save-binary", N, f"PlistSave p in {T('save-binary.plist')} with binary", CLOSE, f"set p to PlistOpen {T('save-binary.plist')}", "PlistBinaryFormat p", "PlistGetXML p", CLOSE)
case("save-without-in", N, f"PlistSave p in {T('save-again.plist')}", 'PlistSet p key "a" to 2', "PlistSave p", CLOSE, f"readtext {T('save-again.plist')}")
case("save-new-without-in", N, "PlistSave p", CLOSE)
case("save-opened-without-in", f"PlistSave (PlistNew {{a:1}}) in {T('opened.plist')}", f"set p to PlistOpen {T('opened.plist')}",
     'PlistSet p key "a" to 3', "PlistSave p", CLOSE, f"readtext {T('opened.plist')}")
case("save-binary-opened", OPEN("binary.plist"), f"PlistSave p in {T('from-binary.plist')}", CLOSE, f"set p to PlistOpen {T('from-binary.plist')}", "PlistBinaryFormat p", CLOSE)
case("save-string-path", N, 'PlistSave p in "$TMP/string-path.plist"', CLOSE, f"readtext {T('string-path.plist')}")
case("save-missing-folder", N, f"PlistSave p in {T('nope/x.plist')}", CLOSE)
case("save-child", N, f'PlistSave (PlistChild p key "d") in {T("child.plist")}', CLOSE, f"readtext {T('child.plist')}")
case("binary-format-new", N, "PlistBinaryFormat p", CLOSE)
case("url", OPEN(), "PlistURL p", CLOSE)
case("url-parent", OPEN(), "PlistURL p with parent", CLOSE)
# URLs as text are percent-encoded, so these use $TMP, whose path has no spaces (the fixtures' Input folder may).
case("url-as-text", N, f"PlistSave p in {T('url-as-text.plist')}", "PlistURL p as text", CLOSE)
case("url-as-alias", OPEN(), "PlistURL p as alias", CLOSE)
case("url-as-string", N, f"PlistSave p in {T('url as string.plist')}", "PlistURL p as string", "PlistURL p as string with parent", CLOSE)
case("url-new", N, "PlistURL p", CLOSE)
case("url-child", OPEN(), 'PlistURL (PlistChild p key "dict")', CLOSE)
case("url-after-save", N, f"PlistSave p in {T('url-after-save.plist')}", "PlistURL p", CLOSE)
case("document", OPEN(), f"set r to PlistDocument {F('simple.plist')}", "PlistEqual p to r", "PlistCount r", CLOSE)
case("document-not-open", f"PlistDocument {F('simple.plist')}")
case("document-string", OPEN(), 'PlistCount (PlistDocument "$FILES/simple.plist")', CLOSE)

# Pools, documents and IDs
case("pool-default", "GetPool (PlistNew)", "PlistListDocuments \"mtc-none\"")
case("pool-set", 'set old to SetPool "mtc-a"', 'set p to PlistNew {a:1}', "GetPool p", "PlistCount (item 1 of (PlistListDocuments))", "SetPool old", 'DeletePool "mtc-a"')
case("pool-in-pool", 'set p to PlistNew {a:1} in pool "mtc-b"', "GetPool p", 'PlistListDocuments "mtc-b"', CLOSE, 'PlistListDocuments "mtc-b"')
case("pool-open-in-pool", f'set p to PlistOpen {F("simple.plist")} in pool "mtc-c"', "GetPool p", f'PlistDocument {F("simple.plist")} in pool "mtc-c"', f'PlistDocument {F("simple.plist")}', CLOSE)
case("pool-delete", 'set p to PlistNew {a:1} in pool "mtc-d"', 'DeletePool "mtc-d"', "PlistGet p")
case("pool-delete-missing", 'DeletePool "mtc-never"')
case("pool-delete-default", 'SetPool "mtc-e"', "set p to PlistNew", "DeletePool", 'SetPool ""', "PlistGet p")
case("pool-set-returns-previous", 'SetPool "mtc-f"', 'SetPool "mtc-g"', 'SetPool ""')
case("pool-list-new-documents", 'set p to PlistNew {a:1} in pool "mtc-h"', 'set r to PlistNew {"b"} in pool "mtc-h"', 'set docs to PlistListDocuments "mtc-h"', "count docs", 'DeletePool "mtc-h"')
case("pool-list-opened", f'set p to PlistOpen {F("simple.plist")} in pool "mtc-i"', 'PlistListDocuments "mtc-i"', CLOSE)
case("pool-get-child", 'set p to PlistNew {a:{b:1}} in pool "mtc-j"', 'GetPool (PlistChild p key "a")', CLOSE)
case("docid", N, 'PlistSetDocID p to "mine"', 'PlistEqual p to (PlistGetDocByID "mine")', 'PlistSetDocID p to "other"', CLOSE)
case("docid-missing", 'PlistGetDocByID "mtc-no-such-id"')
case("docid-after-close", N, 'PlistSetDocID p to "closed"', CLOSE, 'PlistGetDocByID "closed"')
case("docid-duplicate", N, 'set r to PlistNew {b:1}', 'PlistSetDocID p to "dup"', 'PlistSetDocID r to "dup"', 'PlistCount (PlistGetDocByID "dup")', CLOSE, "PlistClose r")
case("docid-in-pool", 'set p to PlistNew {a:1} in pool "mtc-k"', 'PlistSetDocID p to "pooled"', 'PlistGetDocByID "pooled"', 'PlistCount (PlistGetDocByID "pooled" in pool "mtc-k")', CLOSE)
case("docid-child", N, 'PlistSetDocID (PlistChild p key "d") to "child"', CLOSE)
case("hidden-retain", N, "PlistRetain p", CLOSE, "PlistGet p", CLOSE)

# JSON
case("json-simple", N, "PlistToJSON p", CLOSE)
case("json-formatted", N, "PlistToJSON p with formatting", CLOSE)
case("json-types", OPEN(), "PlistToJSON p", CLOSE)
case("json-types-formatted", OPEN(), "PlistToJSON p with formatting", CLOSE)
case("json-child", N, 'PlistToJSON (PlistChild p key "l")', CLOSE)
case("json-string", N, 'PlistToJSON (PlistChild p key "a")', CLOSE)
REPLACER = q('function(key, value) { return typeof value === "number" ? value * 10 : value; }')
case("json-replacer", N, f"PlistToJSON p replacer {REPLACER}", CLOSE)
case("json-replacer-invalid", N, 'PlistToJSON p replacer "not javascript ("', CLOSE)
case("json-unicode", 'set p to PlistNew {t:"café ☃ \\"q\\" /", u:"line" & return & "two"}', "PlistToJSON p", CLOSE)
case("json-big-numbers", OPEN("big.plist"), "PlistToJSON p", CLOSE)
case("javascript", N, "PlistToJavaScript p", CLOSE)
for name, text in [
    ("object", '{"a": 1, "b": [true, false, null], "c": {"d": 2.5}, "e": "text"}'), ("array", '[1, "two", 3.5]'),
    ("number", "42"), ("string", '"just text"'), ("integers-and-reals", '{"i": 3, "r": 3.0, "e": 1e3, "big": 12345678901234567890}'),
    ("unicode", '{"t": "caf\\u00e9 \\u2603"}'), ("invalid", "{not json}"), ("empty", ""), ("empty-object", "{}"),
]:
    case(f"fromjson-{name}", f"set p to PlistFromJSON {q(text)}", "PlistType p", "PlistGetXML p", CLOSE)
case("fromjson-in-pool", f'set p to PlistFromJSON {q("{}")} in pool "mtc-l"', "GetPool p", CLOSE)

# Closed documents and bad references
case("closed-get", N, CLOSE, "PlistGet p")
case("closed-child", N, 'set c to PlistChild p key "d"', CLOSE, "PlistGet c")
case("closed-twice", N, CLOSE, CLOSE)
case("not-a-reference", 'PlistGet "text"')
case("close-child", N, 'PlistClose (PlistChild p key "d")', "PlistGet p", CLOSE)

# filter text … into a CFRef (Text Additions' filter text never worked in SatimageOSAX, so these are MTC_OSAX's)
PAIRS = '"a=1" & linefeed & "b=2" & linefeed & "a=3"'
FILTER = r'filter text "^(\\w+)=(.*)$" in (' + PAIRS + r') key "\\1"'
case("filter-into", 'set p to PlistNew {z:0}', FILTER + r' using "\\2" into p', "PlistGetXML p", CLOSE)
case("filter-into-list", 'set p to PlistNew {a:"old"}', FILTER + r' using "\\2" as list into p', "PlistGetXML p", CLOSE)
case("filter-into-child", 'set p to PlistNew {d:{z:0}}', FILTER + r' using "\\2" into (PlistChild p key "d")', "PlistGetXML p", CLOSE)
case("filter-into-array", 'set p to PlistNew {1, 2}', FILTER + " into p", CLOSE)
case("filter-into-closed", 'set p to PlistNew', CLOSE, FILTER + " into p")

# Cases that leave SatimageOSAX unable to handle property list commands (every later one fails with -10004 until
# it's relaunched) go last.
BREAKS_SATIMAGE = {"child-using-trailing-slash"}
cases = [c for c in cases if c["name"] not in BREAKS_SATIMAGE] + [c for c in cases if c["name"] in BREAKS_SATIMAGE]

MTC_OSAX_FIXES = {
    "child-using-trailing-slash": "Satimage returned nothing, and then failed every property list command (-10004)",
    "get-big-numbers": "Satimage returned 0 for an integer beyond 32 bits",
    "open-big-numbers": "Satimage returned 0 for an integer beyond 32 bits",
    "remove-then-use-removed": "Satimage returned nothing for a removed element's reference",
    "save-string-path": "Satimage: error -1 for a POSIX path string",
    "json-types": "Satimage returned nothing when the plist had a date or data",
    "json-types-formatted": "Satimage returned nothing when the plist had a date or data",
    "fromjson-object": "Satimage made a plist it couldn't use from JSON with null",
    "set-key-list-missing-value-kept": "Satimage ignored the missing value without suppressing, instead of storing it",
    **{c["name"]: "Satimage ignored without typed in PlistNew" for c in cases if c["name"].startswith("new-untyped-")},
    **{c["name"]: "filter text never worked in Satimage (-1708)" for c in cases if c["name"].startswith("filter-")},
}
assert MTC_OSAX_FIXES.keys() <= names
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
if MTC_OSAX_FIXES:
    os.makedirs("../PropertyListsFixes", exist_ok=True)
    json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../PropertyListsFixes/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
