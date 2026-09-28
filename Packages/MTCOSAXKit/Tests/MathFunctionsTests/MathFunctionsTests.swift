import AppleEventCore
import Foundation
import Testing
@testable import MathFunctions

private func send(_ code: String, _ direct: (any AppleEventEncodable)?) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(MathFunctions.commands())
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	if let direct {
		event.setParam(direct.appleEventDescriptor, forKeyword: keyDirectObject)
	}
	return dispatcher.dispatch(event)
}

struct MathFunctionsCommandTests {
	@Test func everyCommandIsRegistered() {
		#expect(MathFunctions.commands().count == 27)
	}

	@Test(arguments: [
		("MATHABS ", -3.0, 3.0), ("MATHSQR ", -3, 9), ("MATHSQRT", 9, 3), ("MATHCEIL", 2.1, 3), ("MATHFLOO", -2.1, -3),
		("MATHTRUN", -2.7, -2), ("MATHEXP ", 0, 1), ("MATHLN  ", 1, 0), ("MATHLOG ", 100, 2), ("MATHSINE", 0, 0),
		("MATHCOSI", 0, 1), ("MATHTANG", 0, 0), ("MATHASIN", 1, Double.pi / 2), ("MATHACOS", 1, 0), ("MATHATAN", 1, Double.pi / 4),
		("MATHSINH", 0, 0), ("MATHCOSH", 0, 1), ("MATHTANH", 0, 0), ("MATHASIH", 0, 0), ("MATHACOH", 1, 0), ("MATHATAH", 0, 0),
		("MATHERF ", 0, 0), ("MATHERFC", 0, 1), ("MATHGAMM", 5, 24), ("MATHLGAM", 1, 0),
	])
	func values(code: String, input: Double, expected: Double) {
		#expect(send(code, input).result?.doubleValue == expected)
	}

	@Test func integersBecomeReals() {
		#expect(send("MATHABS ", -7).result?.descriptorType == typeIEEE64BitFloatingPoint)
	}

	@Test func nonFiniteResults() {
		#expect(send("MATHSQRT", -1).error == .parameterError)
		#expect(send("MATHEXP ", 710).error == .parameterError)
		#expect(send("MATHGAMM", 0).error == .parameterError)
		let list = send("MATHLN  ", [1, 0])
		#expect(list.result?.atIndex(2)?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		let array = send("MATHSQRT", ArrayOfReal([-1, 4]))
		#expect(ArrayOfReal.values(of: array.result!)!.first!.isNaN)
	}

	@Test func inputs() {
		#expect(send("MATHABS ", "-2.5").result?.doubleValue == 2.5)
		#expect(send("MATHABS ", NSAppleEventDescriptor(boolean: true)).error == .coercionFailed)
		#expect(send("MATHABS ", nil).error == .missingParameter)
		#expect(send("MATHABS ", [Int]()).result?.numberOfItems == 0)
	}

	@Test func pairs() {
		#expect(send("MATHATA2", [1, 1]).result?.doubleValue == Double.pi / 4)
		#expect(send("MATHHYPO", [3, 4]).result?.doubleValue == 5)
		#expect(send("MATHHYPO", ["3", "4"]).result?.doubleValue == 5)
		#expect(send("MATHHYPO", [3]).error == .parameterError)
		#expect(send("MATHHYPO", [3, 4, 5]).error == .parameterError)
		#expect(send("MATHHYPO", 3).error == .parameterError)
		#expect(send("MATHHYPO", ArrayOfReal([3, 4])).error == .parameterError)
	}
}
