# Writes the documents in Input/ that the XML cases open. Run: python3 make_inputs.py
import os
os.makedirs("Input", exist_ok=True)
def write(name, text, encoding="utf-8"):
    with open(os.path.join("Input", name), "wb") as f:
        f.write(text.encode(encoding))

# Like the KML files the "KML To Excel" script reads.
write("places.kml", """<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
	<name>Places</name>
	<Placemark>
		<name>Home</name>
		<description>Where I live</description>
		<styleUrl>#icon</styleUrl>
		<Point>
			<coordinates>-73.9857,40.7484,0</coordinates>
		</Point>
	</Placemark>
	<Placemark>
		<name>Work</name>
		<description><![CDATA[The <b>office</b>]]></description>
		<styleUrl>#icon</styleUrl>
		<Point>
			<coordinates>-74.0060,40.7128,0</coordinates>
		</Point>
	</Placemark>
</Document>
</kml>
""")

# Every kind of node.
write("simple.xml", """<?xml version="1.0" encoding="UTF-8"?>
<!-- a comment before the root -->
<?app setting="1"?>
<library xmlns:dc="http://purl.org/dc/elements/1.1/" version="2">
	<book id="b1" lang="en">
		<title>Moby-Dick</title>
		<dc:creator>Herman Melville</dc:creator>
		<year>1851</year>
		<price currency="USD">9.99</price>
	</book>
	<book id="b2" lang="fr">
		<title>Les Misérables</title>
		<dc:creator>Victor Hugo</dc:creator>
		<year>1862</year>
		<!-- no price -->
	</book>
	<note>Mixed <em>content</em> with &amp; entities &lt;here&gt; and a <![CDATA[<cdata> section]]>.</note>
	<empty/>
	<spaces>   padded   </spaces>
</library>
""")

# A default namespace and prefixes.
write("namespaces.xml", """<?xml version="1.0"?>
<root xmlns="urn:default" xmlns:a="urn:a" xmlns:b="urn:b">
	<a:item b:attr="1">first</a:item>
	<item>second</item>
	<b:item xmlns:c="urn:c"><c:inner>third</c:inner></b:item>
</root>
""")

# A DTD with an entity and IDs, valid.
write("dtd.xml", """<?xml version="1.0"?>
<!DOCTYPE people [
	<!ELEMENT people (person*)>
	<!ELEMENT person (#PCDATA)>
	<!ATTLIST person id ID #REQUIRED>
	<!ENTITY company "Example Corp">
]>
<people>
	<person id="p1">Ann of &company;</person>
	<person id="p2">Bob</person>
</people>
""")

# Not well-formed.
write("invalid.xml", """<?xml version="1.0"?>
<root>
	<open>
</root>
""")

# Latin-1.
write("latin1.xml", '<?xml version="1.0" encoding="ISO-8859-1"?>\n<root>café crème</root>\n', "latin-1")

# HTML.
write("page.html", """<html><head><title>Page</title></head>
<body><p class="intro">Hello <b>world</b><br>
<p>Second paragraph &nbsp; &copy; 2026</body></html>
""")

# XInclude.
write("include-part.xml", '<?xml version="1.0"?>\n<part>included text</part>\n')
write("include.xml", """<?xml version="1.0"?>
<doc xmlns:xi="http://www.w3.org/2001/XInclude">
	<xi:include href="include-part.xml"/>
</doc>
""")

# xml:base and relative references.
write("base.xml", """<?xml version="1.0"?>
<root xml:base="http://example.com/dir/">
	<child xml:base="sub/"><leaf href="file.html"/></child>
</root>
""")
print(sorted(os.listdir("Input")))
