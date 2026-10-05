# Generates cases-validation.json for the XML Validation suite (stage 3 of Implemented/PLAN-XML.md), recorded from SatimageOSAX
# into this folder like generate.py's. Warm SatimageOSAX up with an XMLOpen first. Run: python3 generate_validation.py
import glob, json, os

existing = set()
for path in glob.glob("cases*.json") + glob.glob("../XMLFixes/cases*.json"):
    if os.path.basename(path) != "cases-validation.json":
        existing |= {c["name"].lower() for c in json.load(open(path))}
cases, names = [], set()
def case(name, *lines):
    name = "valid-" + name
    assert name.lower() not in names and name.lower() not in existing, name
    names.add(name.lower())
    cases.append({"name": name, "script": "\n".join(lines)})

F = lambda name: f'(POSIX file "$FILES/{name}")'
OPEN = lambda name, var="d", options="": f"set {var} to XMLOpen {F(name)}{options}"
ROOT = "set r to XMLRoot d"
CLOSE = "XMLClose d"
# Commands expected to fail are wrapped, so the case goes on; XMLError shows the messages.
def T(*lines):
    return "try\n" + "\n".join(lines) + "\nend try"

# XMLValidate
case("validate-internal", OPEN("dtd.xml"), T("XMLValidate d"), "XMLError", CLOSE)
case("validate-internal-verbose", OPEN("dtd.xml"), T("XMLValidate d with verbose"), CLOSE)
case("validate-element", OPEN("dtd.xml"), ROOT, T("XMLValidate r"), T("XMLValidate (XMLChild r index 1)"), CLOSE)
case("validate-no-dtd", OPEN("no-dtd.xml"), T("XMLValidate d"), "XMLError", CLOSE)
case("validate-against-invalid", OPEN("no-dtd.xml"), T(f"XMLValidate d against {F('people.dtd')}"), "XMLError", CLOSE)
case("validate-against-valid", OPEN("external-dtd.xml"), T(f"XMLValidate d against {F('people.dtd')}"), CLOSE)
case("validate-against-path", OPEN("external-dtd.xml"), T('XMLValidate d against "$FILES/people.dtd"'), CLOSE)
case("validate-against-missing", OPEN("external-dtd.xml"), T(f"XMLValidate d against {F('nope.dtd')}"), "XMLError", CLOSE)
case("validate-against-bad", OPEN("external-dtd.xml"), T(f"XMLValidate d against {F('bad.dtd')}"), "XMLError", CLOSE)
case("validate-external", OPEN("external-dtd.xml"), T("XMLValidate d"), CLOSE)
case("validate-external-loaded", OPEN("external-dtd.xml", options=" with load external DTD"), T("XMLValidate d"), CLOSE)
case("validate-modified", OPEN("dtd.xml"), ROOT, 'XMLNewChild "<bogus/>" at r', T("XMLValidate d"), "XMLError", T("XMLValidate d with verbose"), CLOSE)
case("validate-failure-level", OPEN("dtd.xml"), ROOT, 'XMLNewChild "<bogus/>" at r', T("XMLValidate d failure level 1"), T("XMLValidate d failure level 3"), CLOSE)
case("validate-string", 'set d to XMLOpen from string "<!DOCTYPE a [<!ELEMENT a (b)><!ELEMENT b EMPTY>]><a><c/></a>"', T("XMLValidate d"), "XMLError", CLOSE)

# XMLSchema
case("schema-with", OPEN("external-dtd.xml"), T(f"XMLSchema d with respect to {F('people.xsd')}"), CLOSE)
case("schema-invalid", OPEN("no-dtd.xml"), T(f"XMLSchema d with respect to {F('people.xsd')}"), "XMLError", CLOSE)
case("schema-location", OPEN("schema-located.xml"), T("XMLSchema d"), CLOSE)
case("schema-location-invalid", OPEN("schema-located-invalid.xml"), T("XMLSchema d"), "XMLError", CLOSE)
case("schema-no-location", OPEN("simple.xml"), T("XMLSchema d"), "XMLError", CLOSE)
case("schema-path", OPEN("external-dtd.xml"), T('XMLSchema d with respect to "$FILES/people.xsd"'), CLOSE)
case("schema-url-text", OPEN("external-dtd.xml"), T('XMLSchema d with respect to "file://$FILES/people.xsd"'), CLOSE)
case("schema-reference", OPEN("external-dtd.xml"), OPEN("people.xsd", var="s"), T("XMLSchema d with respect to s"), "XMLClose s", CLOSE)
case("schema-text", OPEN("no-dtd.xml"), T('XMLSchema d with respect to "<xs:schema xmlns:xs=\\"http://www.w3.org/2001/XMLSchema\\"><xs:element name=\\"people\\"/></xs:schema>"'), CLOSE)
case("schema-element", OPEN("external-dtd.xml"), ROOT, T(f"XMLSchema r with respect to {F('people.xsd')}"), CLOSE)
case("schema-only", T(f"XMLSchema with respect to {F('people.xsd')}"), T(f"XMLSchema with respect to {F('bad.xsd')}"), "XMLError")
case("schema-missing", OPEN("external-dtd.xml"), T(f"XMLSchema d with respect to {F('nope.xsd')}"), "XMLError", CLOSE)
case("schema-none", T("XMLSchema"))

# XMLRelaxNG
case("relaxng-valid", OPEN("external-dtd.xml"), T(f"XMLRelaxNG d with respect to {F('people.rng')}"), CLOSE)
case("relaxng-invalid", OPEN("no-dtd.xml"), T(f"XMLRelaxNG d with respect to {F('people.rng')}"), "XMLError", CLOSE)
case("relaxng-path", OPEN("external-dtd.xml"), T('XMLRelaxNG d with respect to "$FILES/people.rng"'), CLOSE)
case("relaxng-reference", OPEN("external-dtd.xml"), OPEN("people.rng", var="s"), T("XMLRelaxNG d with respect to s"), "XMLClose s", CLOSE)
case("relaxng-text", OPEN("external-dtd.xml"), T('XMLRelaxNG d with respect to "<element name=\\"people\\" xmlns=\\"http://relaxng.org/ns/structure/1.0\\"><zeroOrMore><element name=\\"person\\"><attribute name=\\"id\\"/><text/></element></zeroOrMore></element>"'), CLOSE)
case("relaxng-element", OPEN("external-dtd.xml"), ROOT, T(f"XMLRelaxNG r with respect to {F('people.rng')}"), CLOSE)
case("relaxng-only", T(f"XMLRelaxNG with respect to {F('people.rng')}"), T(f"XMLRelaxNG with respect to {F('bad.rng')}"), "XMLError")
case("relaxng-missing", OPEN("external-dtd.xml"), T(f"XMLRelaxNG d with respect to {F('nope.rng')}"), CLOSE)
case("relaxng-none", OPEN("external-dtd.xml"), T("XMLRelaxNG d"), CLOSE)

# XMLCheckDTD
case("check-dtd-file", T(f"XMLCheckDTD {F('people.dtd')}"), T(f"XMLCheckDTD {F('bad.dtd')}"), "XMLError")
case("check-dtd-path", T('XMLCheckDTD "$FILES/people.dtd"'), T('XMLCheckDTD "file://$FILES/people.dtd"'))
case("check-dtd-text", T('XMLCheckDTD "<!ELEMENT a (b)><!ELEMENT b EMPTY>"'), T('XMLCheckDTD "<!ELEMENT a (b>"'), "XMLError")
case("check-dtd-missing", T(f"XMLCheckDTD {F('nope.dtd')}"), "XMLError")

# XMLGetByID, XMLGetxmlID
case("by-id-xml-id", OPEN("xmlid.xml"), T('XMLGetText (XMLGetByID d xmlid "s1")'), T('XMLGetText (XMLGetByID d xmlid "s3")'),
     T('XMLGetByID d xmlid {"s1", "s2"}'), T('XMLGetByID d xmlid "zz"'), T('XMLGetByID d xmlid {"s1", "zz"}'), CLOSE)
case("by-id-from-element", OPEN("xmlid.xml"), ROOT, T('XMLGetText (XMLGetByID (XMLChild r index 3) xmlid "s2")'), CLOSE)
case("by-id-dtd", OPEN("dtd.xml"), T('XMLGetText (XMLGetByID d xmlid "p2")'), CLOSE)
case("by-id-dtd-validated", OPEN("dtd.xml", options=" with validate"), T('XMLGetText (XMLGetByID d xmlid "p2")'), CLOSE)
case("by-id-none", OPEN("simple.xml"), T('XMLGetByID d xmlid "b1"'), CLOSE)
case("xml-id", OPEN("xmlid.xml"), ROOT, T("XMLGetxmlID (XMLChild r index 1)"), T("XMLGetxmlID (XMLChild r index 3)"), T("XMLGetxmlID r"),
     T("XMLGetxmlID d"), T("XMLGetxmlID (XMLChild (XMLChild r index 1) index 1)"), CLOSE)
case("xml-id-dtd", OPEN("dtd.xml"), ROOT, T("XMLGetxmlID (XMLChild r index 1)"), CLOSE)
case("xml-id-dtd-validated", OPEN("dtd.xml", options=" with validate"), ROOT, T("XMLGetxmlID (XMLChild r index 2)"), CLOSE)
case("xml-id-list", OPEN("xmlid.xml"), ROOT, T("XMLGetxmlID {XMLChild r index 1, XMLChild r index 2}"), CLOSE)

# XMLValidName, XMLValidNCName
for command in ("XMLValidName", "XMLValidNCName"):
    case(command[3:].lower(), *[T(f"{command} {value}") for value in
         ['"abc"', '"a:b"', '"1abc"', '"_x-1.y"', '""', '"a b"', '"é"', '{"a", "1", "a:b"}', '{}', "12"]])

case("names-lists", T('XMLValidName {"a", "b"}'), T('XMLValidNCName {"a", "b"}'), T('XMLValidName {"a:b", "c"}'))
case("validate-element-no-ids", 'set d to XMLOpen from string "<!DOCTYPE a [<!ELEMENT a (b*)><!ELEMENT b EMPTY><!ATTLIST b n CDATA #IMPLIED>]><a><b n=\\"1\\"/><b/></a>"', ROOT,
     T("XMLValidate r"), T("XMLValidate (XMLChild r index 1)"), 'XMLNewChild "<c/>" at (XMLChild r index 1)', T("XMLValidate (XMLChild r index 1)"), "XMLError", T("XMLValidate r"), CLOSE)

case("error-after-success", OPEN("no-dtd.xml"), T("XMLValidate d"), T(f"XMLSchema d with respect to {F('people.xsd')}"),
     OPEN("external-dtd.xml", var="e"), T("XMLValidate e"), "XMLError", T(f"XMLSchema d with respect to {F('people.xsd')}"),
     T(f"XMLRelaxNG e with respect to {F('people.rng')}"), "XMLError", "XMLClose e", CLOSE)

# Hidden: XMLDu
case("du", OPEN("simple.xml"), ROOT, T("XMLDu r"), T("XMLDu d"), T("XMLDu (XMLChild r index 1)"), CLOSE)
case("du-small", 'set d to XMLOpen from string "<a x=\\"1\\"><b>t</b><b/><!--c--><c><d/></c></a>"', ROOT, T("XMLDu r"), T("XMLDu d"), CLOSE)

# Satimage's XMLError text after a command that succeeded was stale (see stage 1's error-none), so cases only
# read it after failures; error-after-success checks it after successes.
MTC_OSAX_FIXES = {
    "valid-validate-element": "Satimage: XMLValidate of an element with ID attributes was error 513 (ID already defined)",
    "valid-error-after-success": "Satimage: XMLError after a validation that succeeded gave stale text, prefixed with the command's name",
    "valid-validname": "Satimage: XMLValidName gave error 1821 for an invalid name instead of false",
    # Not a Satimage bug: macOS's libxml2 adds a second message for a schema that can't be loaded.
    "valid-schema-missing": "libxml2 version: XMLError also says it failed to locate the main schema resource",
    "valid-validncname": "Satimage: XMLValidNCName gave error 1821 for an invalid name instead of false",
}
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases-validation.json", "w"), indent=1, ensure_ascii=False)
if MTC_OSAX_FIXES:
    json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../XMLFixes/cases-validation.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
