# Generates cases.json for XMLOpen of http URLs. SatimageOSAX couldn't open any URL (error 4, "document is empty",
# even for public ones), so these are recorded from MTC_OSAX, following the dictionary. Recording and replaying
# need the test server (serve.py here; the replay tests start the same server in Swift); $HTTP is its address and
# $FILES the XML fixtures' Input folder. Run: python3 generate.py
import json

cases = []
def case(name, *lines):
    cases.append({"name": name, "script": "\n".join(lines)})

CLOSE = "XMLClose d"
case("get", 'set d to XMLOpen "$HTTP/files/simple.xml"', "XMLTagName (XMLRoot d)", "XMLURL d", "XMLURL d with parent", CLOSE)
case("get-base", 'set d to XMLOpen "$HTTP/files/simple.xml"', "XMLBase d", 'XMLAbsoluteURL "other.xml" from d', CLOSE)
case("get-latin1", 'set d to XMLOpen "$HTTP/files/latin1.xml"', "XMLGetText (XMLRoot d)", CLOSE)
case("get-html", 'set d to XMLOpen "$HTTP/files/page.html" with html4', "XMLNodeInfo d", CLOSE)
case("get-invalid", 'XMLOpen "$HTTP/files/invalid.xml"')
case("get-missing", 'XMLOpen "$HTTP/files/nope.xml"')
case("get-query", 'set d to XMLOpen "$HTTP/echo?a=1"', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("get-query-parameter", 'set d to XMLOpen "$HTTP/echo" query "b=2&c=3"', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("get-query-both", 'set d to XMLOpen "$HTTP/echo?a=1" query "b=2"', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("get-headers", 'set d to XMLOpen "$HTTP/echo" header {|X-Test|:"hello", |X-Other|:"2"}', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("post", 'set d to XMLOpen "$HTTP/echo" query "b=2&c=3" with POST', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("post-no-query", 'set d to XMLOpen "$HTTP/echo" with POST', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("post-headers", 'set d to XMLOpen "$HTTP/echo" query "x=1" header {|X-Test|:"hello"} with POST', "XMLDisplayXML (XMLRoot d)", CLOSE)
case("unreachable", 'XMLOpen "http://127.0.0.1:1/nothing.xml"')

json.dump(cases, open("cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases), "MTC_OSAX cases")
