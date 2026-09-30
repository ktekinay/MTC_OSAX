import AppleEventCore
import Foundation
import Testing
@testable import FileAdditions

@MainActor
struct AbsoluteURLTests {
	private let absoluteURL = "SATIaURL"

	private func absolute(_ parameters: [String: any AppleEventEncodable]) -> String? {
		send(absoluteURL, parameters).result?.stringValue
	}

	@Test func documentationExamples() {
		let library = URL(fileURLWithPath: "/Library", isDirectory: true)
		#expect(absolute(["----": library]) == "file:///Library/")
		#expect(absolute(["----": "Application%20Support", "from": library]) == "file:///Library/Application%20Support")
		#expect(absolute(["----": "Application%20Support", "from": library, "rtyp": typeObject("psxP")]) == "/Library/Application Support")
		#expect(absolute(["----": "/Library/Application Support"]) == "file:///Library/Application%20Support")
		#expect(absolute(["----": "en/smile/index.html#top", "from": "http://www.satimage-software.com"]) == "http://www.satimage-software.com/en/smile/index.html#top")
	}

	@Test func relativeResolution() {
		let base = "http://h.com/a/b/c.html"
		#expect(absolute(["----": "../x/y.html?q=1", "from": base]) == "http://h.com/a/x/y.html?q=1")
		#expect(absolute(["----": "/x.html", "from": base]) == "http://h.com/x.html")
		#expect(absolute(["----": "//x.com/y", "from": base]) == "http://x.com/y")
		#expect(absolute(["----": "#top", "from": base]) == "http://h.com/a/b/c.html#top")
		#expect(absolute(["----": "https://x.com/y", "from": base]) == "https://x.com/y")
		#expect(absolute(["----": "http://h.com/a/./b/../c.html"]) == "http://h.com/a/c.html")
		#expect(absolute(["----": "b.html", "from": "http://h.com/a/", "rtyp": typeObject("psxP")]) == "/a/b.html")
		// A file URL naming another computer isn't a file here (an alias to the local /x was made).
		for form in ["alis", "furl"] {
			#expect(send("SATIaURL", ["----": "file://otherhost/x", "rtyp": type(form)]).error?.number == -1700, "\(form)")
		}
	}

	@Test func paths() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.folder("sub")
		#expect(absolute(["----": folder.path("sub")]) == "file://\(folder.path("sub"))") // The disk isn't checked.
		#expect(absolute(["----": folder.path("sub") + "/"]) == "file://\(folder.path("sub"))/")
		#expect(absolute(["----": folder.url.appendingPathComponent("sub")]) == "file://\(folder.path("sub"))/")
		#expect(absolute(["----": folder.path("a b.txt"), "rtyp": typeObject("FTPc")])?.hasSuffix("/a%20b.txt") == true)
		#expect(absolute(["----": "~/x"]) == URL(fileURLWithPath: NSHomeDirectory() + "/x").absoluteString)
		#expect(texts(send(absoluteURL, ["----": ["a.txt", "sub/"], "from": folder.url])) == ["file://\(folder.path("a.txt"))", "file://\(folder.path("sub"))/"])
	}

	@Test func aliasesAndFileURLs() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.file("sub/d.md")
		let alias = send(absoluteURL, ["----": "d.md", "from": folder.url.appendingPathComponent("sub"), "rtyp": type("alis")])
		#expect(alias.result?.descriptorType == typeAlias)
		#expect(send(absoluteURL, ["----": "nope.md", "from": folder.url, "rtyp": type("alis")]).error == OSAXError(-43))
		#expect(send(absoluteURL, ["----": "d.md", "from": folder.url, "rtyp": type("file")]).result?.descriptorType == typeFileURL)
		// A web page isn't a file (this used to be a file URL holding http://).
		#expect(send(absoluteURL, ["----": "b", "from": "http://x.com/a/", "rtyp": type("file")]).error?.number == -1700)
	}

	@Test func errors() {
		#expect(send(absoluteURL, ["----": ""]).error == OSAXError(111))
		#expect(send(absoluteURL, ["----": "a/b.html"]).error == .coercionFailed)
		#expect(send(absoluteURL, [:]).error == .missingParameter)
	}
}

@MainActor
struct RelativeURLTests {
	private func relative(_ target: String, _ base: String) -> String? {
		send("SATIrURL", ["----": target, "from": base]).result?.stringValue
	}

	@Test func http() {
		#expect(relative("http://h.com/a/b/c.html", "http://h.com/a/d/e.html") == "../b/c.html")
		#expect(relative("http://h.com/a/b.html", "http://h.com/a/") == "b.html")
		#expect(relative("http://h.com/a/b/c/d.html", "http://h.com/a/") == "b/c/d.html")
		#expect(relative("http://h.com/x.html", "http://h.com/a/b/") == "../../x.html")
		#expect(relative("http://h.com/a/b.html", "http://h.com/a/b.html") == "")
		#expect(relative("http://h.com/a/", "http://h.com/a/b.html") == ".")
		#expect(relative("http://h.com/a/b.html?q=1#top", "http://h.com/a/") == "b.html?q=1#top")
		#expect(relative("http://h.com/a/b.html", "http://h.com/a") == "a/b.html")
		#expect(relative("http://h.com/a/b%20c.html", "http://h.com/a/") == "b%20c.html")
		#expect(relative("http://x.com/a", "http://h.com/a/") == "http://x.com/a")
		#expect(relative("https://h.com/a/b.html", "http://h.com/a/") == "https://h.com/a/b.html")
	}

	@Test func files() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.file("a.txt")
		try folder.file("sub/deep/d.md")
		let sub = folder.url.appendingPathComponent("sub")
		#expect(send("SATIrURL", ["----": folder.url.appendingPathComponent("sub/deep/d.md"), "from": sub]).result?.stringValue == "deep/d.md")
		#expect(send("SATIrURL", ["----": folder.url.appendingPathComponent("a.txt"), "from": sub.appendingPathComponent("deep")]).result?.stringValue == "../../a.txt")
		#expect(send("SATIrURL", ["----": sub, "from": sub]).result?.stringValue == "")
		#expect(relative(folder.path("sub/c.txt"), folder.url.path + "/") == "sub/c.txt")
	}

	@Test func missingParameters() {
		#expect(send("SATIrURL", ["----": "http://h.com/a"]).error == .missingParameter)
		#expect(send("SATIrURL", [:]).error == .missingParameter)
	}
}

@MainActor
struct URLInfoTests {
	private let urlInfo = "SATIIURL"

	private func fields(_ reply: AppleEventReply) -> [(String, NSAppleEventDescriptor)] {
		guard let record = reply.result else {
			return []
		}
		return (0 ..< record.numberOfItems).map { (record.keywordForDescriptor(at: $0 + 1).fourCharString, record.atIndex($0 + 1)!) }
	}

	private func keys(_ reply: AppleEventReply) -> [String] {
		fields(reply).map(\.0)
	}

	private func value(_ reply: AppleEventReply, _ key: String) -> NSAppleEventDescriptor? {
		fields(reply).first { $0.0 == key }?.1
	}

	@Test func remoteURL() {
		let reply = send(urlInfo, ["----": "http://user:pw@www.example.com:8080/dir/file.html;p=1?q=2&r=3#frag"])
		#expect(keys(reply) == ["pusc", "HOST", "RAun", "RApw", "psxP", "FTPc", "Upar", "Quer", "Ufra", "pnam", "nmxt", "utid", "asty", "asct", "asdr", "ispk", "alis"])
		#expect(value(reply, "HOST")?.stringValue == "www.example.com")
		#expect(value(reply, "RAun")?.stringValue == "user")
		#expect(value(reply, "psxP")?.stringValue == "/dir/file.html")
		#expect(value(reply, "Upar")?.stringValue == "p=1")
		#expect(value(reply, "utid")?.stringValue == "public.html")
	}

	@Test func remoteURLParts() {
		let escaped = send(urlInfo, ["----": "http://www.example.com/a%20b/c%C3%A9.html"])
		#expect(value(escaped, "psxP")?.stringValue == "/a b/cé.html")
		#expect(value(escaped, "FTPc")?.stringValue == "/a%20b/c%C3%A9.html")
		#expect(value(escaped, "pnam")?.stringValue == "cé.html")
		let folder = send(urlInfo, ["----": "ftp://ftp.example.com/pub/"])
		#expect(value(folder, "pnam")?.stringValue == "pub")
		#expect(value(folder, "asdr")?.booleanValue == true)
		#expect(keys(send(urlInfo, ["----": "mailto:a@b.com"])) == ["pusc", "pnam", "nmxt", "asty", "asct", "asdr", "ispk", "alis"])
		#expect(keys(send(urlInfo, ["----": "dir/file.html"])).first == "psxP")
		#expect(value(send(urlInfo, ["----": "http://x.com/file.xyzq"]), "utid")?.stringValue == "dyn.age81u8p4se")
		#expect(value(send(urlInfo, ["----": "http://x.com"]), "psxP")?.stringValue == "")
	}

	@Test func localFile() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		let file = try folder.file("a b.txt", "hello")
		let reply = send(urlInfo, ["----": file])
		#expect(keys(reply) == ["pnam", "ascd", "asmo", "ptsz", "asdr", "alis", "ispk", "pvis", "hidx", "nmxt", "dnam", "asda", "kind", "asty", "asct", "utid", "aslk", "bzst", "assv", "aslv", "pusc", "psxP", "FTPc"])
		#expect(value(reply, "pnam")?.stringValue == "a b.txt")
		#expect(value(reply, "ptsz")?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		#expect(value(reply, "utid")?.stringValue == "public.plain-text")
		#expect(value(reply, "FTPc")?.stringValue?.hasSuffix("/a%20b.txt") == true)
		#expect(value(reply, "asty")?.data == Data(count: 4))
		let sized = send(urlInfo, ["----": file.path, "ptsz": true])
		#expect(value(sized, "ptsz")?.descriptorType == FourCharCode(fourCharString: "comp"))
		#expect(value(sized, "ptsz")?.data == withUnsafeBytes(of: Int64(5).littleEndian) { Data($0) })
		#expect(send(urlInfo, ["----": folder.path("nope.txt")]).error == OSAXError(-43))
	}

	@Test func localFolderAndPackage() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.file("sub/a.txt", "abc")
		try folder.file("sub/.b", "de")
		try folder.file("pkg.app/Contents/Info.plist")
		let sub = send(urlInfo, ["----": folder.url.appendingPathComponent("sub"), "ptsz": true])
		#expect(keys(sub) == ["pnam", "ascd", "asmo", "ptsz", "asdr", "alis", "ispk", "pvis", "hidx", "nmxt", "dnam", "asda", "kind", "asfw", "asty", "asct", "pusc", "psxP", "FTPc"])
		#expect(value(sub, "ptsz")?.data == withUnsafeBytes(of: Int64(5).littleEndian) { Data($0) })
		#expect(value(sub, "psxP")?.stringValue == folder.path("sub"))
		#expect(value(sub, "FTPc")?.stringValue?.hasSuffix("/sub/") == true)
		let package = send(urlInfo, ["----": folder.path("pkg.app")])
		#expect(keys(package).contains("bnid"))
		#expect(value(package, "ispk")?.booleanValue == true)
		#expect(value(package, "asty")?.stringValue == "APPL")
	}

	@Test func symbolicLinkAndHFSPath() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.file("a.txt")
		try FileManager.default.createSymbolicLink(atPath: folder.path("link"), withDestinationPath: "a.txt")
		let link = send(urlInfo, ["----": folder.path("link")])
		#expect(value(link, "pnam")?.stringValue == "a.txt")
		#expect(value(link, "psxP")?.stringValue == folder.path("link"))
		let hfs = NSAppleEventDescriptor(fileURL: folder.url.appendingPathComponent("a.txt")).coerce(toDescriptorType: typeUnicodeText)!.stringValue!
		#expect(value(send(urlInfo, ["----": hfs]), "pnam")?.stringValue == "a.txt")
	}

	@Test func errors() {
		#expect(send(urlInfo, ["----": "not a url"]).error == .coercionFailed)
		#expect(send(urlInfo, [:]).error == .missingParameter)
		#expect(keys(send(urlInfo, ["----": ""])) == ["pnam", "nmxt", "asty", "asct", "asdr", "ispk", "alis"])
	}
}

@MainActor
struct AliasDescriptionTests {
	private let aliasDescription = "SATIALIS"

	@Test func resolvesAliasFilesAndLinks() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		let target = try folder.file("target.txt")
		let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile)
		try URL.writeBookmarkData(bookmark, to: folder.url.appendingPathComponent("alias"))
		#expect(send(aliasDescription, ["----": folder.path("alias")]).result?.stringValue == target.path)
		try FileManager.default.createSymbolicLink(atPath: folder.path("link"), withDestinationPath: "target.txt")
		#expect(send(aliasDescription, ["----": folder.path("link")]).result?.stringValue == target.path)
	}

	@Test func otherItems() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.file("a.txt")
		#expect(send(aliasDescription, ["----": folder.path("a.txt")]).result?.stringValue == folder.path("a.txt"))
		#expect(send(aliasDescription, ["----": folder.url]).result?.stringValue == folder.url.path + "/")
		#expect(send(aliasDescription, ["----": folder.path("nope")]).result?.stringValue == folder.path("nope"))
		#expect(send(aliasDescription, [:]).error == .missingParameter)
	}
}
