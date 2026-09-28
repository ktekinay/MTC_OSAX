import AppleEventCore
import Foundation
import Testing
@testable import Numerics

struct NumbersTests {
	@Test func decodesNumbersListsAndArrays() throws {
		#expect(try Numbers(NSAppleEventDescriptor(int32: 3)) == .number(3))
		#expect(try Numbers(NSAppleEventDescriptor(double: 2.5)) == .number(2.5))
		#expect(try Numbers(NSAppleEventDescriptor(string: "-2.5")) == .number(-2.5))
		#expect(try Numbers([1, 2].appleEventDescriptor) == .list([.number(1), .number(2)]))
		#expect(try Numbers([[1], [2]].appleEventDescriptor) == .list([.list([.number(1)]), .list([.number(2)])]))
		#expect(try Numbers(ArrayOfReal([1, 2]).appleEventDescriptor) == .array([1, 2]))
	}

	@Test func rejectsOtherValues() {
		#expect(throws: OSAXError.coercionFailed) { try Numbers(NSAppleEventDescriptor(boolean: true)) }
		#expect(throws: OSAXError.coercionFailed) { try Numbers(NSAppleEventDescriptor(string: "abc")) }
		#expect(throws: OSAXError.coercionFailed) { try Numbers(.missingValue) }
		#expect(throws: OSAXError.coercionFailed) { try Numbers(NSAppleEventDescriptor(date: Date())) }
		#expect(throws: OSAXError.missingParameter) { try Numbers(NSAppleEventDescriptor.record()) }
	}

	@Test func mapKeepsTheShape() throws {
		#expect(try Numbers.number(4).map(sqrt).doubleValue == 2)
		#expect(throws: OSAXError.parameterError) { try Numbers.number(-1).map(sqrt) }
		let list = try Numbers.list([.number(4), .number(-1), .list([.number(9)])]).map(sqrt)
		#expect(list.atIndex(1)?.doubleValue == 2)
		#expect(list.atIndex(2)?.typeCodeValue == FourCharCode(fourCharString: "msng"))
		#expect(list.atIndex(3)?.atIndex(1)?.doubleValue == 3)
		let array = try ArrayOfReal(appleEventDescriptor: Numbers.array([4, -1]).map(sqrt))
		#expect(array.values[0] == 2 && array.values[1].isNaN)
	}
}
