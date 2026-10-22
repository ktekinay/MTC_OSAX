# Linear Algebra and FFT Plan

Branch: `feature/linear_algebra_fft`

Goal: implement two of Satimage's suites from "May Do Later" in [PLAN.md](PLAN.md), which work on the Arrays suite's
`matrix` and `array of real`: **Linear algebra** (8 commands and the `Lapack result` record; the hidden
`currentEndianess` is left out) and **FFT and convolution** (6 commands). As before: match SatimageOSAX where it works,
follow the dictionary where it doesn't. SatimageOSAX runs only under Rosetta, so its behavior is recorded now.

## What a probe of SatimageOSAX found (2026-10-22)

About 130 cases (not kept; the fixtures come in step 2). Matrices are as in the Arrays suite: `{class:matrix, ncols,
nrows, array of real}`, the rows one after another.

**Throughout:**

- **Complex values are a list of two**, real part then imaginary part: two matrices, two arrays, or two numbers. A
  list of exactly two numbers is a complex number, not a vector of two: `multmatrix {1, 2} with {3, 4}` is
  (1 + 2i)(3 + 4i) = `{-5, 10}`, while the same as arrays is the scalar product 11. So a vector of two must be an
  array, and `solve linear system A RHS {1, 2}` is error 1004 (a complex number isn't a right-hand side of two).
  Lists of other lengths are vectors.
- **Errors:** 1018 for a matrix that isn't square (`compute eigenvalues`, `solve linear system`); 1030 for a singular
  matrix (`invertmatrix`) or one that isn't positive definite (`invertmatrix`, `compute determinant`); 1004 for a
  right-hand side of the wrong size or kind; `solve linear system` gives LAPACK's own number for a singular matrix or
  one that isn't positive (2: the second pivot, or minor, failed); -1 for some others (`invertmatrix` or
  `LUdecomposition` of a matrix that isn't square, `pivot` past the end); -50 for sizes that don't fit.

**Linear algebra:**

- **`transpose`** works; for a complex matrix it gives the adjoint (conjugate transpose) unless `adjoint false`. An
  array is -1700, a list -50.
- **`multmatrix`** works for matrix × matrix, matrix × array, array × matrix, array · array (a real), and a number or
  a complex number times a matrix; complex matrices too. Sizes that don't fit are -50.
- **`invertmatrix`** returns the inverse matrix (not the record with `ipiv` and the determinant the dictionary
  describes). **With `positive true` it's wrong:** the lower triangle is left as the input's (LAPACK's `potri` fills
  only the upper one).
- **`solve linear system`** works with an array, a list (of other than two numbers) or a matrix (its columns) as the
  right-hand side, for real and complex matrices, with `symmetry` and `positive`.
- **`compute eigenvalues`** works for real matrices, general (the eigenvalues as `{real parts, imaginary parts}`,
  always) and symmetric (one array, ascending), for complex Hermitian matrices, with `eigenvects` (the vectors as the
  columns of a matrix, or of two for complex ones), `Vtype` (0 right, 1 left, 2 both, as `right eigenvectors` and
  `left eigenvectors`), `irange`, `erange`, `conquer`, and the generalized problem (`RHS`, `Itype`). `symmetry true`
  reads the upper triangle. **A complex matrix that isn't Hermitian is error -10.**
- **`LUdecomposition`** works for a real matrix: `{uppermatrix, lowermatrix, determinant, permutation vector}`, the
  vector LAPACK's 1-based row interchanges. **With `positive true` (Cholesky) it returns nothing at all, and for a
  complex matrix `lowermatrix` is all zeros.**
- **`pivot`** applies the interchanges in order to `to`'s rows (P × M, as LAPACK's `laswp`); an array is a column.
  Without `to` it's -1701, though the dictionary marks it optional.
- **`compute determinant`** works: real, complex (`{re, im}`), and `positive true` (by Cholesky: 5.000000000000001
  for a matrix whose determinant is 5).

**FFT and convolution:**

- **`fft1d`** works for any length (6, 7, 12, …): forward with e^(−2πi jk/n), normalized by 1/√n both ways (unitary),
  the result always `{real parts, imaginary parts}`; a complex input is a list of two arrays. With `lot`, it
  transforms `lot` vectors of `vector size` numbers, `vector step` apart (default 1), each starting `vector offset`
  after the one before, in place in an array of the input's length; `lot` without `vector offset` is -1701, and
  without `lot`, `vector size` is ignored. Empty is -1; parts of different lengths, or too few numbers for the lot, -50.
- **`fft2d`** works the same way on a matrix (normalized by 1/√(rows × columns)), giving two matrices.
- **`filterarray`** works: the convolution's valid part, ns − nf + 1 numbers (`correlation true`: Σ s(i+j)f(j)); a
  filter longer than the signal is -50.
- **`convolve` and `correlate` don't work:** every call is error -1753 ("Script error") from SatimageOSAX itself.
- **`interpolate`** works: a natural cubic spline (or `linear true`) through `{xs, ys}` (sorted by x first), at `at`
  (a number gives a number). Outside the xs it gives the end values. `boundary conditions {dy1, dyn}` are the end
  slopes (a clamped spline). With `period P` the spline is clamped with both end slopes the chord across the seam,
  (y₁ − yₙ)/(x₁ + P − xₙ); the linear one interpolates across the seam (past the last x it wraps), the spline doesn't
  (it still gives the end value). Data that already closes the period (xₙ = x₁ + P) makes every value NaN (0/0), as
  does a repeated x. Different lengths are -1; no `{xs, ys}` -1701.

## Commands

In this order, each group with its tests:

1. **Shared:** reading real and complex matrices and vectors (lists as arrays, a list of two as complex), the
   `Lapack result` record, and LAPACK through Accelerate.
2. **`transpose`, `multmatrix`, `pivot`, `compute determinant`, `LUdecomposition`, `invertmatrix`, `solve linear
   system`.**
3. **`compute eigenvalues`**, with all its parameters.
4. **`fft1d`, `fft2d`.**
5. **`filterarray`, `convolve`, `correlate`.**
6. **`interpolate`.**

## Decisions

Proposed, for your review:

1. **LAPACK from Accelerate**, the library SatimageOSAX used (its errors are LAPACK's info numbers), so results
   should match to the last digits or nearly. Accelerate's current LAPACK interface needs a C define
   (`ACCELERATE_NEW_LAPACK`), so the calls go through a small C target, as the other C libraries do. Matrices are
   transposed to LAPACK's column order and back.
2. **FFT:** Accelerate's vDSP for the lengths it does (n = f × 2^k, f one of 1, 3, 5, 15), and Bluestein's algorithm
   (a chirp through a power-of-two FFT) for the others, so every length is n log n as the dictionary says. Fixtures
   compare within a tolerance, since the order of the arithmetic differs.
3. **Satimage's bugs, fixed per the dictionary** (recorded from MTC_OSAX in a `…Fixes` folder, and in the README):
   - `LUdecomposition … positive true`: `{uppermatrix: U, determinant}`, with A = UᵀU (Uᴴ U for complex).
   - The complex `lowermatrix`: L, its diagonal 1.
   - `invertmatrix … positive true`: the whole inverse, both triangles.
   - `compute eigenvalues` of a complex matrix that isn't Hermitian: its eigenvalues (and vectors), as for a real one.
   - `convolve` and `correlate`, from their descriptions: convolve Σ f(i−j)g(j), circular by default (period
     max(n, m), the shorter padded with zeros), otherwise the full linear convolution of 2·max(n, m) − 1 numbers;
     correlate Σ (f(i+j) − ⟨f⟩)(g(j) − ⟨g⟩), circular by default (n numbers) or not (2n − 1, the origin at n),
     normalized by default so that `correlate x to x` is 1 at the origin.
   - `pivot` without `to`: the permutation matrix P (so that `pivot v to M` is P × M), rather than -1701.
4. **A list of two numbers stays a complex number**, as recorded, rather than becoming a vector of two: scripts that
   pass complex scalars that way keep working. The README says to pass a vector of two as an array.
5. **`interpolate`'s `period`:** the end slopes as Satimage computes them; data that closes the period uses the slope
   across the seam from the points either side of it (what the chord gives when it's defined) rather than NaN; and
   the spline, like the linear interpolation, wraps past the last x (Satimage gave the end value, though its own
   linear interpolation wraps). A repeated x stays NaN, as recorded.
6. **Lists for arrays and matrices' numbers**, as the other Arrays commands take them; an array where a matrix is
   needed stays -1700, as recorded for `transpose`.
7. **Limits**, as for the Arrays commands: inputs and results at most 100,000,000 numbers, and the O(n³) commands
   (inverse, solve, LU, determinant, eigenvalues) limited in size so that none takes more than a few seconds,
   the sizes set by timing them once they're written (likely a few thousand rows, fewer for eigenvectors).
8. **Error numbers as recorded** (1018, 1030, 1004, LAPACK's info, -1, -50), and `invertmatrix`'s result a matrix,
   as recorded, not the record its description mentions.
9. **Release:** in the README's 1.1 release notes, unless 1.1 has been released by then.

## Testing

- **SatimageOSAX fixtures** in `Fixtures/LinearAlgebra` and `Fixtures/FFT` from a `generate.py` each: every command
  and parameter, real and complex, the shapes each takes, and the errors. Reals within a tolerance where the
  arithmetic's order differs (the fits' precedent).
- **Where Satimage is broken** (decision 3, and `period` per decision 5): cases in `Fixtures/LinearAlgebraFixes` and
  `Fixtures/FFTFixes`, recorded from MTC_OSAX, in the README's differences and this plan.
- **Unit tests** by property, on random matrices and signals as well as small known ones: A × A⁻¹ = I; PA = LU and
  A = UᵀU; A x = b; A v = λ v (and left vectors); the determinant as the product of the eigenvalues; the inverse FFT
  of the FFT is the input, and Parseval's identity holds (it's unitary); the FFT against a direct O(n²) sum for every
  length from 1 to 64; convolution and correlation against their direct sums; the spline exact for cubics with exact
  end slopes, and through every point; the limits, and errors.
- **End to end:** `Scripts/e2e/linear-algebra.applescript` and `fft.applescript` with `parity.sh` against
  SatimageOSAX, and `…-fixes` scripts for what MTC_OSAX does differently.

## Steps

1. Copy the two suites into `MTC_OSAX.sdef` verbatim (without `currentEndianess`), with placeholder handlers; the SDEF
   consistency tests pass.
2. Record the fixtures from SatimageOSAX.
3. Implement in the order above, each group with its tests, committed as it's done.
4. Fixes for what Satimage gets wrong, recorded from MTC_OSAX.
5. README (out of "Not implemented", the differences, the release notes), PLAN.md, e2e scripts; full test suite.

## Results
