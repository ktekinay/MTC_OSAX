import CLibXML
import CommonCrypto
import CryptoKit
import Foundation

extension XPath {
	/// The functions XMLXPath adds to XPath 1.0, in the namespaces its dictionary names (a script declares prefixes
	/// for them): XPath 2.0's compare, upper-case, lower-case, ends-with and base-uri; EXSLT's math, sets, strings
	/// and dates-and-times functions, and md5, sha1, sha224 and sha256 (base64, as SatimageOSAX gave them); and
	/// SatimageOSAX's parent-uri and relative-uri.
	nonisolated enum Functions {
		static let xpath2 = "http://www.w3.org/2005/xpath-functions"
		static let crypto = "http://exslt.org/crypto"
		static let strings = "http://exslt.org/strings"
		static let satimage = "http://satimage.fr/software/xpath-functions"

		static func register(_ context: xmlXPathContextPtr) {
			// EXSLT's registration also declares a prefix; these are ones no script uses.
			withXMLString("mtc-exslt-math") { _ = exsltMathXpathCtxtRegister(context, $0) }
			withXMLString("mtc-exslt-sets") { _ = exsltSetsXpathCtxtRegister(context, $0) }
			withXMLString("mtc-exslt-strings") { _ = exsltStrXpathCtxtRegister(context, $0) }
			withXMLString("mtc-exslt-dates") { _ = exsltDateXpathCtxtRegister(context, $0) }
			let functions: [(String, String, xmlXPathFunction)] = [
				(xpath2, "compare", compare), (xpath2, "upper-case", upperCase), (xpath2, "lower-case", lowerCase),
				(xpath2, "ends-with", endsWith), (xpath2, "base-uri", baseURI),
				(crypto, "md5", md5), (crypto, "sha1", sha1), (crypto, "sha224", sha224), (crypto, "sha256", sha256),
				// Listed in the dictionary, but missing from SatimageOSAX's XPath (EXSLT has it only in XSLT).
				(strings, "replace", replace),
				(satimage, "parent-uri", parentURI), (satimage, "relative-uri", relativeURI),
			]
			for (uri, name, function) in functions {
				withXMLString(name) { n in withXMLString(uri) { _ = xmlXPathRegisterFuncNS(context, n, $0, function) } }
			}
		}

		// MARK: Arguments and results

		/// The arguments as strings (node sets as their string values), or nil after reporting a wrong number.
		private static func arguments(_ context: xmlXPathParserContextPtr?, _ count: Int32, _ allowed: ClosedRange<Int32>) -> [String]? {
			guard let context else { return nil }
			guard allowed.contains(count) else {
				xmlXPathErr(context, Int32(XPATH_INVALID_ARITY.rawValue))
				return nil
			}
			var values: [String] = []
			for _ in 0 ..< count {
				values.insert(Parsing.string(xmlXPathPopString(context)) ?? "", at: 0)
			}
			return context.pointee.error == 0 ? values : nil
		}

		private static func push(_ context: xmlXPathParserContextPtr?, _ string: String) {
			withXMLString(string) { _ = valuePush(context, xmlXPathNewString($0)) }
		}

		// MARK: XPath 2.0

		private static let compare: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 2 ... 2) else { return }
			let (a, b) = (values[0].unicodeScalars.map(\.value), values[1].unicodeScalars.map(\.value))
			_ = valuePush(context, xmlXPathNewFloat(a == b ? 0 : a.lexicographicallyPrecedes(b) ? -1 : 1))
		}

		private static let upperCase: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 1 ... 1) else { return }
			push(context, values[0].uppercased())
		}

		private static let lowerCase: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 1 ... 1) else { return }
			push(context, values[0].lowercased())
		}

		private static let endsWith: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 2 ... 2) else { return }
			_ = valuePush(context, xmlXPathNewBoolean(values[0].hasSuffix(values[1]) ? 1 : 0))
		}

		/// The base URI of the first node of its argument, or of the context node.
		private static let baseURI: xmlXPathFunction = { context, count in
			guard let context else { return }
			guard count <= 1 else {
				xmlXPathErr(context, Int32(XPATH_INVALID_ARITY.rawValue))
				return
			}
			var node = context.pointee.context.pointee.node
			if count == 1 {
				guard let set = xmlXPathPopNodeSet(context) else {
					xmlXPathErr(context, Int32(XPATH_INVALID_TYPE.rawValue))
					return
				}
				node = XPath.nodes(set).first
				xmlXPathFreeNodeSet(set)
			}
			guard let node else {
				push(context, "")
				return
			}
			push(context, Parsing.string(xmlNodeGetBase(node.pointee.doc, node)) ?? "")
		}

		// MARK: Digests

		private static func digest(_ context: xmlXPathParserContextPtr?, _ count: Int32, length: Int32,
		                           _ hash: (UnsafeRawPointer?, CC_LONG, UnsafeMutablePointer<UInt8>?) -> UnsafeMutablePointer<UInt8>?)
		{
			guard let values = arguments(context, count, 1 ... 1) else { return }
			let data = Data(values[0].utf8)
			var result = [UInt8](repeating: 0, count: Int(length))
			data.withUnsafeBytes { _ = hash($0.baseAddress, CC_LONG(data.count), &result) }
			push(context, Data(result).base64EncodedString())
		}

		// MD5 from CryptoKit: CommonCrypto's is deprecated (the same bytes; it's for Satimage's crypto:md5).
		private static let md5: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 1 ... 1) else { return }
			push(context, Data(Insecure.MD5.hash(data: Data(values[0].utf8))).base64EncodedString())
		}
		private static let sha1: xmlXPathFunction = { digest($0, $1, length: CC_SHA1_DIGEST_LENGTH, CC_SHA1) }
		private static let sha224: xmlXPathFunction = { digest($0, $1, length: CC_SHA224_DIGEST_LENGTH, CC_SHA224) }
		private static let sha256: xmlXPathFunction = { digest($0, $1, length: CC_SHA256_DIGEST_LENGTH, CC_SHA256) }

		// MARK: Strings

		/// `replace(string, search, replacement)`: every occurrence of `search` replaced.
		private static let replace: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 3 ... 3) else { return }
			push(context, values[1].isEmpty ? values[0] : values[0].replacingOccurrences(of: values[1], with: values[2]))
		}

		// MARK: URIs

		/// The URI up to its last `/`.
		private static let parentURI: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 1 ... 1) else { return }
			let uri = values[0]
			push(context, uri.lastIndex(of: "/").map { String(uri[...$0]) } ?? uri)
		}

		/// The first URI relative to the second.
		private static let relativeURI: xmlXPathFunction = { context, count in
			guard let values = arguments(context, count, 2 ... 2) else { return }
			let relative = withXMLString(values[0]) { uri in withXMLString(values[1]) { Parsing.string(xmlBuildRelativeURI(uri, $0)) } }
			push(context, relative ?? values[0])
		}
	}
}
