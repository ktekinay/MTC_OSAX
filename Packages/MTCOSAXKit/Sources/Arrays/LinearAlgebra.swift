import Foundation

/// Small dense linear algebra for the polynomial commands: Gaussian elimination, least squares by a singular value
/// decomposition (one-sided Jacobi, of the triangle from a QR decomposition when there are more rows than columns),
/// and a polynomial's roots as GSL finds them.
enum LinearAlgebra {
	/// x with `matrix` x = `right`, by Gaussian elimination with partial pivoting; nil if it's singular.
	static func solve(_ matrix: [[Double]], _ right: [Double]) -> [Double]? {
		var a = matrix
		var b = right
		let n = b.count
		for column in 0 ..< n {
			let pivot = (column ..< n).max { abs(a[$0][column]) < abs(a[$1][column]) }!
			guard a[pivot][column] != 0 else {
				return nil
			}
			a.swapAt(column, pivot)
			b.swapAt(column, pivot)
			for row in column + 1 ..< n {
				let factor = a[row][column] / a[column][column]
				for k in column ..< n {
					a[row][k] -= factor * a[column][k]
				}
				b[row] -= factor * b[column]
			}
		}
		var x = [Double](repeating: 0, count: n)
		for row in (0 ..< n).reversed() {
			var sum = b[row]
			for k in row + 1 ..< n {
				sum -= a[row][k] * x[k]
			}
			x[row] = sum / a[row][row]
		}
		return x
	}

	/// The singular value decomposition A = U Σ Vᵀ of an m × n matrix (given by rows, m ≥ n), by one-sided Jacobi
	/// rotations: U's columns, the singular values, V's columns.
	static func singularValues(_ rows: [[Double]]) -> (u: [[Double]], sigma: [Double], v: [[Double]]) {
		let n = rows.first?.count ?? 0
		let m = rows.count
		var u = (0 ..< n).map { column in rows.map { $0[column] } }
		var v = (0 ..< n).map { column in (0 ..< n).map { $0 == column ? 1.0 : 0.0 } }
		for _ in 0 ..< 60 {
			var rotated = false
			for p in 0 ..< n {
				for q in p + 1 ..< n {
					var alpha = 0.0, beta = 0.0, gamma = 0.0
					for i in 0 ..< m {
						alpha += u[p][i] * u[p][i]
						beta += u[q][i] * u[q][i]
						gamma += u[p][i] * u[q][i]
					}
					guard gamma != 0, abs(gamma) > Double.ulpOfOne * (alpha * beta).squareRoot() else {
						continue
					}
					rotated = true
					let zeta = (beta - alpha) / (2 * gamma)
					let t = (zeta < 0 ? -1.0 : 1.0) / (abs(zeta) + (1 + zeta * zeta).squareRoot())
					let c = 1 / (1 + t * t).squareRoot()
					let s = c * t
					for i in 0 ..< m {
						let (up, uq) = (u[p][i], u[q][i])
						u[p][i] = c * up - s * uq
						u[q][i] = s * up + c * uq
					}
					for i in 0 ..< n {
						let (vp, vq) = (v[p][i], v[q][i])
						v[p][i] = c * vp - s * vq
						v[q][i] = s * vp + c * vq
					}
				}
			}
			if !rotated {
				break
			}
		}
		let sigma = u.map { column in column.reduce(0) { $0 + $1 * $1 }.squareRoot() }
		for j in 0 ..< n where sigma[j] > 0 {
			u[j] = u[j].map { $0 / sigma[j] }
		}
		return (u, sigma, v)
	}

	/// R of A = Q R (A by rows, m ≥ n; R n × n, upper triangular, by rows) and the first n numbers of Qᵀ y, by
	/// Householder reflections. ‖A x - y‖ is least where ‖R x - (Qᵀ y)‖ is, and R has A's singular values and right
	/// singular vectors, so a decomposition of R costs n³ for each sweep rather than m·n² (10,000 points of degree
	/// 100 took 3.5 s, and take 0.12).
	static func triangular(_ rows: [[Double]], _ y: [Double]) -> (r: [[Double]], qty: [Double]) {
		let m = rows.count
		let n = rows.first?.count ?? 0
		// A by columns, each m long, then y.
		var a = [Double](repeating: 0, count: (n + 1) * m)
		for (i, row) in rows.enumerated() {
			for (j, value) in row.enumerated() {
				a[j * m + i] = value
			}
		}
		for i in 0 ..< m {
			a[n * m + i] = y[i]
		}
		a.withUnsafeMutableBufferPointer { a in
			for k in 0 ..< n {
				let column = k * m
				// The column from the diagonal down, divided by its largest number so that its squares can't overflow
				// (a reflection is the same for any multiple of it).
				var scale = 0.0
				for i in k ..< m {
					scale = max(scale, abs(a[column + i]))
				}
				guard scale > 0, scale.isFinite else {
					continue
				}
				var sum = 0.0
				for i in k ..< m {
					a[column + i] /= scale
					sum += a[column + i] * a[column + i]
				}
				let norm = sum.squareRoot()
				let diagonal = a[column + k]
				let alpha = diagonal > 0 ? -norm : norm
				// The reflection's vector v, in place of the column; vᵀv without summing again.
				a[column + k] = diagonal - alpha
				let vv = 2 * norm * (norm + abs(diagonal))
				for j in k + 1 ... n {
					let other = j * m
					var dot = 0.0
					for i in k ..< m {
						dot += a[column + i] * a[other + i]
					}
					let factor = 2 * dot / vv
					for i in k ..< m {
						a[other + i] -= factor * a[column + i]
					}
				}
				a[column + k] = alpha * scale
			}
		}
		let r = (0 ..< n).map { i in (0 ..< n).map { j in j >= i ? a[j * m + i] : 0 } }
		return (r, (0 ..< n).map { a[n * m + $0] })
	}

	/// The x of least ‖A x - y‖, and of those the smallest (A by rows, any shape or rank); nil if A is empty.
	static func pseudoSolve(_ rows: [[Double]], _ y: [Double]) -> [Double]? {
		guard let n = rows.first?.count, n > 0 else {
			return nil
		}
		let m = rows.count
		// For more rows than columns, R and Qᵀ y in their place.
		let (matrix, right) = m > n ? triangular(rows, y) : (rows, y)
		// For fewer rows than columns, decompose Aᵀ = U Σ Vᵀ, so A = V Σ Uᵀ.
		let transposed = m < n
		let (u, sigma, v) = singularValues(transposed ? (0 ..< n).map { column in matrix.map { $0[column] } } : matrix)
		let tolerance = Double(max(m, n)) * Double.ulpOfOne * (sigma.max() ?? 0)
		var x = [Double](repeating: 0, count: n)
		for j in sigma.indices where sigma[j] > tolerance {
			// Along the j-th singular vectors: (left · y) / σ times right.
			let (left, rightVector) = transposed ? (v[j], u[j]) : (u[j], v[j])
			let coefficient = zip(left, right).reduce(0.0) { $0 + $1.0 * $1.1 } / sigma[j]
			for i in 0 ..< n {
				x[i] += coefficient * rightVector[i]
			}
		}
		return x
	}

	/// Least squares meeting the constraints (each {a₀, …, aₙ₋₁, b}: Σ aᵢxᵢ = b), by solving in their null space.
	static func leastSquares(_ rows: [[Double]], _ y: [Double], constraints: [[Double]]) -> [Double]? {
		guard !constraints.isEmpty, let n = rows.first?.count else {
			return pseudoSolve(rows, y)
		}
		let a = constraints.map { Array($0.prefix(n)) }
		let b = constraints.map { $0[n] }
		// A particular solution, and the directions that keep the constraints: V's columns past A's rank.
		guard let particular = pseudoSolve(a, b) else {
			return nil
		}
		// Square: padded with zeros, or for more constraints than unknowns, R (the same null space).
		let square = a.count > n ? triangular(a, b).r : a + Array(repeating: [Double](repeating: 0, count: n), count: n - a.count)
		let (_, sigma, v) = singularValues(square)
		let tolerance = Double(n) * Double.ulpOfOne * (sigma.max() ?? 0)
		let free = sigma.indices.filter { sigma[$0] <= tolerance }.map { v[$0] }
		guard !free.isEmpty else {
			return particular
		}
		let residual = zip(rows, y).map { row, value in value - zip(row, particular).reduce(0.0) { $0 + $1.0 * $1.1 } }
		let reduced = rows.map { row in free.map { direction in zip(row, direction).reduce(0.0) { $0 + $1.0 * $1.1 } } }
		guard let z = pseudoSolve(reduced, residual) else {
			return nil
		}
		return (0 ..< n).map { i in particular[i] + zip(free, z).reduce(0.0) { $0 + $1.0[i] * $1.1 } }
	}
}

/// A polynomial's roots as SatimageOSAX found them: the eigenvalues of its companion matrix (the coefficients across
/// the first row), balanced, by the QR algorithm (EISPACK's balanc and hqr, as in Numerical Recipes' zrhqr), in the
/// order hqr stores them. This order, and the imaginary parts' signs (+ before - in a pair, the other way round from
/// hqr's), are what the recorded fixtures show; GSL's solver, tried first, ordered them differently.
enum RootFinder {
	struct Root: Equatable {
		var real: Double
		var imaginary: Double
	}

	/// The roots of a polynomial (coefficients, constant term first, the last not zero); nil if QR doesn't converge,
	/// or if a coefficient divided by the last one isn't finite (balancing an infinity never ended).
	static func roots(_ coefficients: [Double]) -> [Root]? {
		let n = coefficients.count - 1
		// 1-based, as in EISPACK: row 1 is -aₙ₋ₖ/aₙ, with ones below the diagonal.
		var a = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n + 1)
		for k in 1 ... n {
			a[1][k] = -coefficients[n - k] / coefficients[n]
			guard a[1][k].isFinite else {
				return nil
			}
			if k != n {
				a[k + 1][k] = 1
			}
		}
		balance(&a, n)
		guard let (real, imaginary) = hqr(&a, n) else {
			return nil
		}
		return (1 ... n).map { Root(real: real[$0], imaginary: -imaginary[$0]) }
	}

	/// balanc: scales rows and columns by powers of 2 until their norms are close.
	private static func balance(_ a: inout [[Double]], _ n: Int) {
		var done = false
		while !done {
			done = true
			for i in 1 ... n {
				var r = 0.0, c = 0.0
				for j in 1 ... n where j != i {
					c += abs(a[j][i])
					r += abs(a[i][j])
				}
				guard c != 0, r != 0 else {
					continue
				}
				var g = r / 2
				var f = 1.0
				let s = c + r
				while c < g {
					f *= 2
					c *= 4
				}
				g = r * 2
				while c > g {
					f /= 2
					c /= 4
				}
				if (c + r) / f < 0.95 * s {
					done = false
					g = 1 / f
					for j in 1 ... n {
						a[i][j] *= g
					}
					for j in 1 ... n {
						a[j][i] *= f
					}
				}
			}
		}
	}

	/// hqr: the eigenvalues of an upper Hessenberg matrix, each stored at the position it's found for.
	private static func hqr(_ a: inout [[Double]], _ n: Int) -> (real: [Double], imaginary: [Double])? {
		var wr = [Double](repeating: 0, count: n + 1)
		var wi = [Double](repeating: 0, count: n + 1)
		var norm = 0.0
		for i in 1 ... n {
			for j in max(i - 1, 1) ... n {
				norm += abs(a[i][j])
			}
		}
		var nn = n
		var t = 0.0
		var p = 0.0, q = 0.0, r = 0.0, x = 0.0, y = 0.0, z = 0.0, w = 0.0
		while nn >= 1 {
			var iterations = 0
			var l = 0
			repeat {
				l = nn
				while l >= 2 {
					var s = abs(a[l - 1][l - 1]) + abs(a[l][l])
					if s == 0 {
						s = norm
					}
					if abs(a[l][l - 1]) + s == s {
						a[l][l - 1] = 0
						break
					}
					l -= 1
				}
				x = a[nn][nn]
				if l == nn {
					wr[nn] = x + t
					wi[nn] = 0
					nn -= 1
				} else {
					y = a[nn - 1][nn - 1]
					w = a[nn][nn - 1] * a[nn - 1][nn]
					if l == nn - 1 {
						p = 0.5 * (y - x)
						q = p * p + w
						z = abs(q).squareRoot()
						x += t
						if q >= 0 {
							z = p + (p >= 0 ? abs(z) : -abs(z))
							wr[nn - 1] = x + z
							wr[nn] = z != 0 ? x - w / z : x + z
							wi[nn - 1] = 0
							wi[nn] = 0
						} else {
							wr[nn - 1] = x + p
							wr[nn] = x + p
							wi[nn] = z
							wi[nn - 1] = -z
						}
						nn -= 2
					} else {
						guard iterations < 30 else {
							return nil
						}
						if iterations == 10 || iterations == 20 {
							// An exceptional shift.
							t += x
							for i in 1 ... nn {
								a[i][i] -= x
							}
							let s = abs(a[nn][nn - 1]) + abs(a[nn - 1][nn - 2])
							x = 0.75 * s
							y = x
							w = -0.4375 * s * s
						}
						iterations += 1
						var m = nn - 2
						while m >= l {
							z = a[m][m]
							r = x - z
							var s = y - z
							p = (r * s - w) / a[m + 1][m] + a[m][m + 1]
							q = a[m + 1][m + 1] - z - r - s
							r = a[m + 2][m + 1]
							s = abs(p) + abs(q) + abs(r)
							p /= s
							q /= s
							r /= s
							if m == l {
								break
							}
							let u = abs(a[m][m - 1]) * (abs(q) + abs(r))
							let v = abs(p) * (abs(a[m - 1][m - 1]) + abs(z) + abs(a[m + 1][m + 1]))
							if u + v == v {
								break
							}
							m -= 1
						}
						if m + 2 <= nn {
							for i in m + 2 ... nn {
								a[i][i - 2] = 0
								if i != m + 2 {
									a[i][i - 3] = 0
								}
							}
						}
						// A double QR step.
						for k in m ... nn - 1 {
							if k != m {
								p = a[k][k - 1]
								q = a[k + 1][k - 1]
								r = k != nn - 1 ? a[k + 2][k - 1] : 0
								x = abs(p) + abs(q) + abs(r)
								if x != 0 {
									p /= x
									q /= x
									r /= x
								}
							}
							let root = (p * p + q * q + r * r).squareRoot()
							let s = p >= 0 ? root : -root
							guard s != 0 else {
								continue
							}
							if k == m {
								if l != m {
									a[k][k - 1] = -a[k][k - 1]
								}
							} else {
								a[k][k - 1] = -s * x
							}
							p += s
							x = p / s
							y = q / s
							z = r / s
							q /= p
							r /= p
							for j in k ... nn {
								p = a[k][j] + q * a[k + 1][j]
								if k != nn - 1 {
									p += r * a[k + 2][j]
									a[k + 2][j] -= p * z
								}
								a[k + 1][j] -= p * y
								a[k][j] -= p * x
							}
							for i in l ... min(nn, k + 3) {
								p = x * a[i][k] + y * a[i][k + 1]
								if k != nn - 1 {
									p += z * a[i][k + 2]
									a[i][k + 2] -= p * r
								}
								a[i][k + 1] -= p * q
								a[i][k] -= p
							}
						}
					}
				}
			} while l < nn - 1
		}
		return (wr, wi)
	}
}
