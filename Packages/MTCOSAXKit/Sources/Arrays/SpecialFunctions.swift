import Foundation

/// The elliptic integrals and Lambert's W that `evalformula` takes from GSL, computed as GSL does (its
/// `gsl_sf_ellint_*` by Carlson's symmetric forms, and `gsl_sf_lambert_*`), so results match SatimageOSAX's,
/// recorded in `Fixtures/Arrays`. Outside an integral's domain the result is NaN (GSL's domain error); outside
/// Lambert's W's, -1 (the value GSL gives with its domain error, as SatimageOSAX returned).
enum SpecialFunctions {
	private static let epsilon = Double.ulpOfOne
	private static let squareRootEpsilon = 1.4901161193847656e-08
	private static let errorTolerance = 0.001

	// MARK: Carlson's forms

	static func carlsonRF(_ x: Double, _ y: Double, _ z: Double) -> Double {
		let lowLimit = 5 * Double.leastNormalMagnitude
		let highLimit = 0.2 * Double.greatestFiniteMagnitude
		guard x >= 0, y >= 0, z >= 0, x + y >= lowLimit, x + z >= lowLimit, y + z >= lowLimit, max(x, y, z) < highLimit else {
			return .nan
		}
		var (xn, yn, zn) = (x, y, z)
		var mu = 0.0, xDeviation = 0.0, yDeviation = 0.0, zDeviation = 0.0
		for _ in 0 ..< 10000 {
			mu = (xn + yn + zn) / 3
			xDeviation = 2 - (mu + xn) / mu
			yDeviation = 2 - (mu + yn) / mu
			zDeviation = 2 - (mu + zn) / mu
			if max(abs(xDeviation), abs(yDeviation), abs(zDeviation)) < errorTolerance {
				break
			}
			let (xRoot, yRoot, zRoot) = (sqrt(xn), sqrt(yn), sqrt(zn))
			let lambda = xRoot * (yRoot + zRoot) + yRoot * zRoot
			xn = (xn + lambda) * 0.25
			yn = (yn + lambda) * 0.25
			zn = (zn + lambda) * 0.25
		}
		let e2 = xDeviation * yDeviation - zDeviation * zDeviation
		let e3 = xDeviation * yDeviation * zDeviation
		let s = 1 + (1.0 / 24 * e2 - 0.1 - 3.0 / 44 * e3) * e2 + 1.0 / 14 * e3
		return s / sqrt(mu)
	}

	static func carlsonRD(_ x: Double, _ y: Double, _ z: Double) -> Double {
		let lowLimit = 2 / pow(Double.greatestFiniteMagnitude, 2.0 / 3)
		let highLimit = pow(0.1 * errorTolerance / Double.leastNormalMagnitude, 2.0 / 3)
		guard min(x, y) >= 0, min(x + y, z) >= lowLimit, max(x, y, z) < highLimit else {
			return .nan
		}
		var (xn, yn, zn) = (x, y, z)
		var sigma = 0.0, power4 = 1.0
		var mu = 0.0, xDeviation = 0.0, yDeviation = 0.0, zDeviation = 0.0
		for _ in 0 ..< 10000 {
			mu = (xn + yn + 3 * zn) * 0.2
			xDeviation = (mu - xn) / mu
			yDeviation = (mu - yn) / mu
			zDeviation = (mu - zn) / mu
			if max(abs(xDeviation), abs(yDeviation), abs(zDeviation)) < errorTolerance {
				break
			}
			let (xRoot, yRoot, zRoot) = (sqrt(xn), sqrt(yn), sqrt(zn))
			let lambda = xRoot * (yRoot + zRoot) + yRoot * zRoot
			sigma += power4 / (zRoot * (zn + lambda))
			power4 *= 0.25
			xn = (xn + lambda) * 0.25
			yn = (yn + lambda) * 0.25
			zn = (zn + lambda) * 0.25
		}
		let ea = xDeviation * yDeviation
		let eb = zDeviation * zDeviation
		let ec = ea - eb
		let ed = ea - 6 * eb
		let ef = ed + ec + ec
		let s1 = ed * (-3.0 / 14 + 0.25 * 9.0 / 22 * ed - 1.5 * 3.0 / 26 * zDeviation * ef)
		let s2 = zDeviation * (1.0 / 6 * ef + zDeviation * (-9.0 / 22 * ec + zDeviation * 3.0 / 26 * ea))
		return 3 * sigma + power4 * (1 + s1 + s2) / (mu * sqrt(mu))
	}

	static func carlsonRC(_ x: Double, _ y: Double) -> Double {
		let lowLimit = 5 * Double.leastNormalMagnitude
		let highLimit = 0.2 * Double.greatestFiniteMagnitude
		guard x >= 0, y >= 0, x + y >= lowLimit, max(x, y) < highLimit else {
			return .nan
		}
		var (xn, yn) = (x, y)
		var mu = 0.0, sn = 0.0
		for _ in 0 ..< 10000 {
			mu = (xn + yn + yn) / 3
			sn = (yn + mu) / mu - 2
			if abs(sn) < errorTolerance {
				break
			}
			let lambda = 2 * sqrt(xn) * sqrt(yn) + yn
			xn = (xn + lambda) * 0.25
			yn = (yn + lambda) * 0.25
		}
		let s = sn * sn * (0.3 + sn * (1.0 / 7 + sn * (0.375 + sn * 9.0 / 22)))
		return (1 + s) / sqrt(mu)
	}

	static func carlsonRJ(_ x: Double, _ y: Double, _ z: Double, _ p: Double) -> Double {
		let lowLimit = pow(5 * Double.leastNormalMagnitude, 1.0 / 3)
		let highLimit = 0.3 * pow(0.2 * Double.greatestFiniteMagnitude, 1.0 / 3)
		guard x >= 0, y >= 0, z >= 0, x + y >= lowLimit, x + z >= lowLimit, y + z >= lowLimit, p >= lowLimit,
		      max(x, y, z, p) < highLimit
		else {
			return .nan
		}
		var (xn, yn, zn, pn) = (x, y, z, p)
		var sigma = 0.0, power4 = 1.0
		var mu = 0.0, xDeviation = 0.0, yDeviation = 0.0, zDeviation = 0.0, pDeviation = 0.0
		for _ in 0 ..< 10000 {
			mu = (xn + yn + zn + pn + pn) * 0.2
			xDeviation = (mu - xn) / mu
			yDeviation = (mu - yn) / mu
			zDeviation = (mu - zn) / mu
			pDeviation = (mu - pn) / mu
			if max(abs(xDeviation), abs(yDeviation), abs(zDeviation), abs(pDeviation)) < errorTolerance {
				break
			}
			let (xRoot, yRoot, zRoot) = (sqrt(xn), sqrt(yn), sqrt(zn))
			let lambda = xRoot * (yRoot + zRoot) + yRoot * zRoot
			var alpha = pn * (xRoot + yRoot + zRoot) + xRoot * yRoot * zRoot
			alpha = alpha * alpha
			let beta = pn * (pn + lambda) * (pn + lambda)
			let rc = carlsonRC(alpha, beta)
			guard !rc.isNaN else {
				return .nan
			}
			sigma += power4 * rc
			power4 *= 0.25
			xn = (xn + lambda) * 0.25
			yn = (yn + lambda) * 0.25
			zn = (zn + lambda) * 0.25
			pn = (pn + lambda) * 0.25
		}
		let (c1, c2, c3, c4) = (3.0 / 14, 1.0 / 3, 3.0 / 22, 3.0 / 26)
		let ea = xDeviation * (yDeviation + zDeviation) + yDeviation * zDeviation
		let eb = xDeviation * yDeviation * zDeviation
		let ec = pDeviation * pDeviation
		let e2 = ea - 3 * ec
		let e3 = eb + 2 * pDeviation * (ea - ec)
		let s1 = 1 + e2 * (-c1 + 0.75 * c3 * e2 - 1.5 * c4 * e3)
		let s2 = eb * (0.5 * c2 + pDeviation * (-c3 - c3 + pDeviation * c4))
		let s3 = pDeviation * ea * (c2 - pDeviation * c3) - c2 * pDeviation * ec
		return 3 * sigma + power4 * (s1 + s2 + s3) / (mu * sqrt(mu))
	}

	// MARK: Elliptic integrals (Legendre's forms, of the modulus k)

	/// K(k): `gsl_sf_ellint_Kcomp`.
	static func completeK(_ k: Double) -> Double {
		let y = 1 - k * k
		guard k * k < 1 else {
			return .nan
		}
		if k * k >= 1 - squareRootEpsilon {
			// Abramowitz and Stegun 17.3.34
			let ta = 1.38629436112 + y * (0.09666344259 + y * 0.03590092383)
			let tb = -log(y) * (0.5 + y * (0.12498593597 + y * 0.06880248576))
			return ta + tb
		}
		return carlsonRF(0, y, 1)
	}

	/// E(k): `gsl_sf_ellint_Ecomp`.
	static func completeE(_ k: Double) -> Double {
		let y = 1 - k * k
		guard k * k < 1 else {
			return .nan
		}
		if k * k >= 1 - squareRootEpsilon {
			// Abramowitz and Stegun 17.3.36
			let ta = 1 + y * (0.44325141463 + y * (0.06260601220 + 0.04757383546 * y))
			let tb = -y * log(y) * (0.24998368310 + y * (0.09200180037 + 0.04069697526 * y))
			return ta + tb
		}
		return carlsonRF(0, y, 1) - k * k / 3 * carlsonRD(0, y, 1)
	}

	/// Π(k, n), with GSL's sign for n (1 + n sin²t): `gsl_sf_ellint_Pcomp`.
	static func completeP(_ k: Double, _ n: Double) -> Double {
		guard k * k < 1 else {
			return .nan
		}
		let y = 1 - k * k
		return carlsonRF(0, y, 1) - n / 3 * carlsonRJ(0, y, 1, 1 + n)
	}

	/// The angle reduced to [-π/2, π/2], and how many π were taken off (each adds twice the complete integral).
	private static func reduced(_ phi: Double) -> (phi: Double, periods: Double) {
		let periods = floor(phi / .pi + 0.5)
		return (phi - periods * .pi, periods)
	}

	/// F(φ, k): `gsl_sf_ellint_F`.
	static func incompleteF(_ phi: Double, _ k: Double) -> Double {
		let (angle, periods) = reduced(phi)
		let sine = sin(angle)
		let sine2 = sine * sine
		var result = sine * carlsonRF(1 - sine2, 1 - k * k * sine2, 1)
		if periods != 0 {
			result += 2 * periods * completeK(k)
		}
		return result
	}

	/// E(φ, k): `gsl_sf_ellint_E`.
	static func incompleteE(_ phi: Double, _ k: Double) -> Double {
		let (angle, periods) = reduced(phi)
		let sine = sin(angle)
		let sine2 = sine * sine
		let x = 1 - sine2
		let y = 1 - k * k * sine2
		if x < epsilon {
			let complete = completeE(k)
			return 2 * periods * complete + (sine < 0 ? -1 : 1) * complete
		}
		var result = sine * carlsonRF(x, y, 1) - k * k / 3 * (sine2 * sine) * carlsonRD(x, y, 1)
		if periods != 0 {
			result += 2 * periods * completeE(k)
		}
		return result
	}

	/// Π(φ, k, n): `gsl_sf_ellint_P`.
	static func incompleteP(_ phi: Double, _ k: Double, _ n: Double) -> Double {
		let (angle, periods) = reduced(phi)
		let sine = sin(angle)
		let sine2 = sine * sine
		let x = 1 - sine2
		let y = 1 - k * k * sine2
		var result = sine * carlsonRF(x, y, 1) - n / 3 * (sine2 * sine) * carlsonRJ(x, y, 1, 1 + n * sine2)
		if periods != 0 {
			result += 2 * periods * completeP(k, n)
		}
		return result
	}

	// MARK: Lambert's W

	/// Halley's iteration from `w` (Newton's for w > 0): `halley_iteration` in GSL.
	private static func halley(_ x: Double, _ start: Double, iterations: Int) -> Double {
		var w = start
		for _ in 0 ..< iterations {
			let e = exp(w)
			let p = w + 1
			var t = w * e - x
			if w > 0 {
				t = (t / p) / e
			} else {
				t /= e * p - 0.5 * (p + 1) * t / p
			}
			w -= t
			let tolerance = 10 * epsilon * max(abs(w), 1 / (abs(p) * e))
			if abs(t) < tolerance {
				return w
			}
		}
		return w
	}

	/// The series about the branch point (-1/e), in r = ±√(x + 1/e).
	private static func series(_ r: Double) -> Double {
		let c = [
			-1.0, 2.331643981597124203363536062168, -1.812187885639363490240191647568, 1.936631114492359755363277457668,
			-2.353551201881614516821543561516, 3.066858901050631912893148922704, -4.175335600258177138854984177460,
			5.858023729874774148815053846119, -8.401032217523977370984161688514, 12.250753501314460424,
			-18.100697012472442755, 27.029044799010561650,
		]
		let t8 = c[8] + r * (c[9] + r * (c[10] + r * c[11]))
		let t5 = c[5] + r * (c[6] + r * (c[7] + r * t8))
		let t1 = c[1] + r * (c[2] + r * (c[3] + r * (c[4] + r * t5)))
		return c[0] + r * t1
	}

	/// W₀(x): `gsl_sf_lambert_W0`.
	static func lambertW0(_ x: Double) -> Double {
		let q = x + 1 / M_E
		if x == 0 {
			return 0
		}
		if q <= 0 {
			return -1
		}
		if q < 1e-3 {
			return series(sqrt(q))
		}
		var w: Double
		if x < 1 {
			let p = sqrt(2 * M_E * q)
			w = -1 + p * (1 + p * (-1.0 / 3 + p * 11.0 / 72))
		} else {
			w = log(x)
			if x > 3 {
				w -= log(w)
			}
		}
		return halley(x, w, iterations: 100)
	}

	/// W₋₁(x): `gsl_sf_lambert_Wm1` (W₀ for x > 0).
	static func lambertWm1(_ x: Double) -> Double {
		if x > 0 {
			return lambertW0(x)
		}
		if x == 0 {
			return 0
		}
		let q = x + 1 / M_E
		if q < 0 {
			return -1
		}
		var w: Double
		if x < -1e-6 {
			w = series(-sqrt(q))
			if q < 3e-3 {
				return w
			}
		} else {
			let l1 = log(-x)
			let l2 = log(-l1)
			w = l1 - l2 + l2 / l1
		}
		return halley(x, w, iterations: 32)
	}
}
