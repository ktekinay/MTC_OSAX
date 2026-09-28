import Foundation
import Network

/// The test server the XMLNetwork fixtures were recorded with (`Fixtures/XMLNetwork/serve.py`), in Swift:
///   GET /files/<name>           a file from `folder`
///   GET or POST /echo?<query>   `<request method="…" query="…" body="…"><header name="x-…">value</header>…</request>`
///   anything else               404 with an HTML body
final class NetworkFixtureServer: @unchecked Sendable {
	private let listener: NWListener
	private let folder: URL
	private let queue = DispatchQueue(label: "NetworkFixtureServer")
	private(set) var port: UInt16 = 0

	init(folder: URL) throws {
		self.folder = folder
		listener = try NWListener(using: .tcp, on: .any)
		let ready = DispatchSemaphore(value: 0)
		listener.stateUpdateHandler = { state in
			if case .ready = state { ready.signal() }
		}
		listener.newConnectionHandler = { [weak self] connection in
			self?.serve(connection)
		}
		listener.start(queue: queue)
		_ = ready.wait(timeout: .now() + 5)
		port = listener.port?.rawValue ?? 0
	}

	deinit {
		listener.cancel()
	}

	var address: String {
		"http://127.0.0.1:\(port)"
	}

	private func serve(_ connection: NWConnection) {
		connection.start(queue: queue)
		receive(connection, Data())
	}

	private func receive(_ connection: NWConnection, _ received: Data) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			guard let self else { return }
			var buffer = received
			if let data { buffer.append(data) }
			if let request = Request(buffer) {
				self.respond(connection, to: request)
			} else if complete || error != nil {
				connection.cancel()
			} else {
				self.receive(connection, buffer)
			}
		}
	}

	private func respond(_ connection: NWConnection, to request: Request) {
		let (status, body, type) = response(request)
		var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\n"
		head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
		connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
	}

	private func response(_ request: Request) -> (Int, Data, String) {
		let notFound = (404, Data("<html><body>Not found</body></html>".utf8), "text/html")
		if request.path.hasPrefix("/files/") {
			let file = folder.appendingPathComponent(String(request.path.dropFirst("/files/".count)))
			guard let data = try? Data(contentsOf: file) else { return notFound }
			return (200, data, "application/xml")
		}
		guard request.path == "/echo" else { return notFound }
		let headers = request.headers.filter { $0.key.hasPrefix("x-") }.sorted { $0.key < $1.key }
			.map { "<header name=\(Self.attribute($0.key))>\(Self.escape($0.value))</header>" }.joined()
		let text = "<request method=\(Self.attribute(request.method)) query=\(Self.attribute(request.query)) body=\(Self.attribute(request.body))>\(headers)</request>"
		return (200, Data(text.utf8), "application/xml")
	}

	private static func escape(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
	}

	/// An attribute value as Python's `quoteattr` writes it.
	private static func attribute(_ text: String) -> String {
		let escaped = escape(text).replacingOccurrences(of: "\n", with: "&#10;").replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\t", with: "&#9;")
		if escaped.contains("\"") {
			return escaped.contains("'") ? "\"" + escaped.replacingOccurrences(of: "\"", with: "&quot;") + "\"" : "'" + escaped + "'"
		}
		return "\"" + escaped + "\""
	}

	private struct Request {
		var method = ""
		var path = ""
		var query = ""
		var headers: [String: String] = [:]
		var body = ""

		/// Nil until the whole request (headers and body) has arrived.
		init?(_ data: Data) {
			guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
			let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
			let parts = head[0].split(separator: " ")
			guard parts.count >= 2 else { return nil }
			method = String(parts[0])
			let target = String(parts[1])
			if let question = target.firstIndex(of: "?") {
				path = String(target[..<question])
				query = String(target[target.index(after: question)...])
			} else {
				path = target
			}
			for line in head.dropFirst() {
				guard let colon = line.firstIndex(of: ":") else { continue }
				headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			}
			let length = Int(headers["content-length"] ?? "0") ?? 0
			let bodyData = data[end.upperBound...]
			guard bodyData.count >= length else { return nil }
			body = String(decoding: bodyData.prefix(length), as: UTF8.self)
		}
	}
}
