// Runs AppleScript test cases against an app and records the Apple events each case sends
// and the replies it gets, as fixture files the tests replay later.
//
//   fixture-recorder --app SatimageOSAX --cases Tests/Fixtures/Text/cases.json [--only name] [--var NAME=value …]
//
// cases.json is an array of {"name": "...", "script": "..."}. Each script runs with
// `use application "<app>"` prepended, and `$NAME` replaced by each --var value. Fixtures are written
// next to cases.json as <name>.json, with the variables' values so replays can substitute their own.
//
// Must run from iTerm (Scripts/iterm-run.sh): processes started from VS Code can't send Apple events.

import AppleEventCore
import Carbon
import Foundation
import OSAKit

struct Case: Decodable {
	var name: String
	var script: String
}

// The send proc below is a C callback, so it records into a global.
nonisolated(unsafe) var capturedExchanges: [Fixture.Exchange] = []

let recordingSendProc: OSASendUPP = { event, reply, sendMode, _, timeout, _, _, _ in
	guard let event, let reply else {
		return OSErr(paramErr)
	}
	let status = AESendMessage(event, reply, sendMode, Int(timeout))
	// Skip events the script sends itself (Standard Additions such as `current date`, AppleScript internals).
	var eventClass = DescType()
	var size = 0
	AEGetAttributePtr(event, AEKeyword(keyEventClassAttr), DescType(typeType), nil, &eventClass, MemoryLayout<DescType>.size, &size)
	if ["syso", "ascr", "misc"].contains(eventClass.fourCharString) {
		return OSErr(status)
	}
	var eventCopy = AEDesc()
	var replyCopy = AEDesc()
	AEDuplicateDesc(event, &eventCopy)
	AEDuplicateDesc(reply, &replyCopy)
	let eventDescriptor = NSAppleEventDescriptor(aeDescNoCopy: &eventCopy)
	let replyDescriptor = NSAppleEventDescriptor(aeDescNoCopy: &replyCopy)
	capturedExchanges.append(Fixture.Exchange(
		event: DescriptorSnapshot(eventDescriptor),
		reply: Fixture.Reply(AppleEventReply(replyEvent: replyDescriptor))
	))
	return OSErr(status)
}

/// Compiles and runs a script with the recording send proc installed. Returns the error number, or nil on success.
func run(_ source: String, language: OSALanguageInstance) -> (error: Int?, compileFailed: Bool) {
	let component = language.componentInstance
	var sourceDescriptor = AEDesc()
	let bytes = Array(source.utf8)
	AECreateDesc(DescType(typeUTF8Text), bytes, bytes.count, &sourceDescriptor)
	defer { AEDisposeDesc(&sourceDescriptor) }

	var scriptID = OSAID(kOSANullScript)
	let compileStatus = OSACompile(component, &sourceDescriptor, Int32(kOSAModeNull), &scriptID)
	guard compileStatus == noErr else {
		return (Int(compileStatus), true)
	}
	defer { OSADispose(component, scriptID) }

	var resultID = OSAID(kOSANullScript)
	let status = OSAExecute(component, scriptID, OSAID(kOSANullScript), Int32(kOSAModeNull), &resultID)
	if resultID != kOSANullScript {
		OSADispose(component, resultID)
	}
	return (status == noErr ? nil : Int(status), false)
}

/// The error text of the last script error, for compile failures.
func lastErrorMessage(language: OSALanguageInstance) -> String {
	let component = language.componentInstance
	var message = AEDesc()
	guard OSAScriptError(component, OSType(kOSAErrorMessage), DescType(typeUnicodeText), &message) == noErr else {
		return "unknown error"
	}
	return NSAppleEventDescriptor(aeDescNoCopy: &message).stringValue ?? "unknown error"
}

func fail(_ message: String) -> Never {
	FileHandle.standardError.write(Data((message + "\n").utf8))
	exit(1)
}

// MARK: - Main

var arguments = CommandLine.arguments.dropFirst()
var appName: String?
var casesPath: String?
var onlyName: String?
var variables: [String: String] = [:]
while let argument = arguments.popFirst() {
	switch argument {
	case "--app": appName = arguments.popFirst()
	case "--cases": casesPath = arguments.popFirst()
	case "--only": onlyName = arguments.popFirst()
	case "--var":
		guard let pair = arguments.popFirst(), let equals = pair.firstIndex(of: "=") else {
			fail("--var needs NAME=value")
		}
		variables[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
	default: fail("Unknown argument \(argument)")
	}
}
guard let appName, let casesPath else {
	fail("usage: fixture-recorder --app <name> --cases <cases.json> [--only <name>]")
}

let casesURL = URL(fileURLWithPath: casesPath)
let cases: [Case]
do {
	cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: casesURL))
} catch {
	fail("Can't read \(casesPath): \(error)")
}

// Fixture files are named after cases, and the disk is usually case-insensitive.
var seenNames: [String: String] = [:]
for testCase in cases {
	// A name is a file name next to cases.json, not a path, nor cases.json itself.
	if let problem = Fixture.problem(withCaseName: testCase.name, casesFile: casesURL) {
		fail(problem)
	}
	if let other = seenNames[testCase.name.lowercased()] {
		fail("Cases \"\(other)\" and \"\(testCase.name)\" would write the same file on a case-insensitive disk.")
	}
	seenNames[testCase.name.lowercased()] = testCase.name
}

let language = OSALanguageInstance(language: OSALanguage(forName: "AppleScript")!)
let refCon = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
OSASetSendProc(language.componentInstance, recordingSendProc, refCon)

var failures = 0
for testCase in cases where onlyName == nil || testCase.name == onlyName {
	capturedExchanges = []
	var script = testCase.script
	var used: [String: String] = [:]
	// Longest names first, so $TMP doesn't replace the start of $TMPDIR.
	for (variable, value) in variables.sorted(by: { $0.key.count > $1.key.count }) where script.contains("$" + variable) {
		// Variables are used inside strings ("$TMP/a.txt").
		script = script.replacingOccurrences(of: "$" + variable, with: Fixture.appleScriptStringContents(value))
		used[variable] = value
	}
	let source = "use application \"\(Fixture.appleScriptStringContents(appName))\"\n" + script
	let outcome = run(source, language: language)

	if outcome.compileFailed {
		print("✗ \(testCase.name): doesn't compile: \(lastErrorMessage(language: language))")
		failures += 1
		continue
	}
	if capturedExchanges.isEmpty {
		print("✗ \(testCase.name): script sent no Apple events")
		failures += 1
		continue
	}

	let fixture = Fixture(
		name: testCase.name,
		script: testCase.script,
		recordedFrom: appName,
		recordedAt: Date(),
		variables: used.isEmpty ? nil : used,
		timeZone: TimeZone.current.identifier,
		exchanges: capturedExchanges
	)
	let url = casesURL.deletingLastPathComponent().appendingPathComponent("\(testCase.name).json")
	do {
		try fixture.write(to: url)
	} catch {
		print("✗ \(testCase.name): can't write \(url.lastPathComponent): \(error)")
		failures += 1
		continue
	}
	let replies = capturedExchanges.map(\.reply.summary).joined(separator: "; ")
	print("✓ \(testCase.name): \(replies)")
}

if failures > 0 {
	exit(1)
}
