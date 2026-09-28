import AppleEventCore
import Darwin
import Foundation
import Numerics

/// Satimage's "Mathematical Functions" suite (event class `MATH`).
/// Behavior recorded from SatimageOSAX in `Fixtures/MathFunctions`; where Satimage was broken, MTC_OSAX follows the
/// dictionary (listed in Implemented/PLAN-MathAndLists.md).
///
/// Each function takes a number, a list of numbers (possibly nested) or an `array of real`, and answers in the same
/// shape with reals. A single result that isn't a finite number is error -50; in a list it's `missing value`, and in
/// an array NaN.
public enum MathFunctions {
	public static func commands() -> [CommandDefinition] {
		let functions: [(String, String, (Double) -> Double)] = [
			("abs", "MATHABS ", { Swift.abs($0) }),
			("acos", "MATHACOS", Darwin.acos),
			("acosh", "MATHACOH", Darwin.acosh),
			("asin", "MATHASIN", Darwin.asin),
			("asinh", "MATHASIH", Darwin.asinh),
			("atan", "MATHATAN", Darwin.atan),
			("atanh", "MATHATAH", Darwin.atanh),
			("ceil", "MATHCEIL", Darwin.ceil),
			("cosh", "MATHCOSH", Darwin.cosh),
			("cos", "MATHCOSI", Darwin.cos),
			("erf", "MATHERF ", Darwin.erf),
			("erfc", "MATHERFC", Darwin.erfc),
			("exp", "MATHEXP ", Darwin.exp),
			("floor", "MATHFLOO", Darwin.floor),
			("gamma", "MATHGAMM", Darwin.tgamma),
			("lgamma", "MATHLGAM", Darwin.lgamma),
			("ln", "MATHLN  ", Darwin.log),
			("log10", "MATHLOG ", Darwin.log10),
			("sin", "MATHSINE", Darwin.sin),
			("sinh", "MATHSINH", Darwin.sinh),
			("sqr", "MATHSQR ", { $0 * $0 }),
			("sqrt", "MATHSQRT", Darwin.sqrt),
			("tan", "MATHTANG", Darwin.tan),
			("tanh", "MATHTANH", Darwin.tanh),
			("trunc", "MATHTRUN", Darwin.trunc),
		]
		return functions.map { name, code, function in
			CommandDefinition(name, code: code) { request in
				try Numbers(request.requiredDirectParameter(as: AnyDescriptor.self).descriptor).map(function)
			}
		} + [
			CommandDefinition("atan2", code: "MATHATA2") { try pair($0) { y, x in Darwin.atan2(y, x) } },
			CommandDefinition("hypot", code: "MATHHYPO") { try pair($0, Darwin.hypot) },
		]
	}

	/// `atan2` and `hypot`: a list of exactly two numbers (not an array), else error -50.
	static func pair(_ request: AppleEventRequest, _ function: (Double, Double) -> Double) throws -> Double {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		guard descriptor.descriptorType == typeAEList, descriptor.numberOfItems == 2,
		      let first = descriptor.atIndex(1), let second = descriptor.atIndex(2),
		      first.descriptorType != typeAEList, second.descriptorType != typeAEList
		else {
			throw OSAXError.parameterError
		}
		let result = function(try Numbers.number(first), try Numbers.number(second))
		guard result.isFinite else {
			throw OSAXError.parameterError
		}
		return result
	}
}
