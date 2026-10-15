# Arrays Plan

Branch: `feature/arrays`

Goal: implement the rest of Satimage's **Arrays** suite (in "May Do Later" in [PLAN.md](PLAN.md)): 26 commands, and the `matrix`, `polynomial`, `statsrecord` and `fitrecord` types. The `array of real` type, `createarray` and `randomarray` came with the Math and Lists work ([PLAN-MathAndLists.md](Implemented/PLAN-MathAndLists.md)). As before: match SatimageOSAX where it works, follow the dictionary where it doesn't. The "Linear algebra" and "FFT and convolution" suites share the suite code but stay in "May Do Later".

**Hidden and obsolete commands are left out** (decided 2026-10-15, for this and later suites): `listvariables`, `smootharray`, `find peaks` and `arrays auto filling`, which Satimage's dictionary marks `hidden="yes"`, and `extractitem` ("obsolete: use extractarray instead"). The README lists them under "Not implemented". Without `arrays auto filling`, lists of unequal length are always an error, as they are by default in SatimageOSAX.

## What a first probe of SatimageOSAX found (2026-10-15)

39 cases, one or two for each command, the hidden ones too (not kept; the fixtures come in step 2):

- **Every command works but one.** `removemissingvalue {1, missing value, 2}` gives -1708; it gets implemented from the dictionary.
- **Scripts convert arrays with `extractarray`:** `extractarray anArray for -1 as list of real` returns a list of reals (`as list of integer` rounds halves to even: 0.5 is 0, 1.5 is 2; `as real` returns one number), and `extractarray aList for -1` an array. `anArray as list of real` and `{1, 2, 3} as array of real` themselves can't work: coercions run in the script's own process (see the Math and Lists plan). The README says so under "Other differences", since the dictionary shows the coercions.
- **Results keep the kind they're given:** `addlist` of lists returns a list, of an array an array, of a matrix a matrix (`{class:matrix, ncols, nrows, array of real}`, the numbers as an `array of real`). Lists of unequal length are -50 (the hidden `arrays auto filling`'s default, 0).
- **`polynomial`** is stored as an `array of real` is ("Not a record", `buod`, little-endian doubles), with the type `Poly`: `composepolynomial` returns one, `pade approximant` a list of two.
- **Missing values:** division by zero in a list gives `missing value` (NaN in an array); `replacemissingvalue` replaces both.
- **`statlist`** divides the variance by n (population variance: `{1, 2, 3, 4, 10}` gives 10), and returns a count of missing values (`msng`) that the dictionary doesn't list; `with kurtosis` adds skewness, kurtosis (not excess: 2.788) and median.
- **Others as documented:** `extractarray`/`changearray`/`insertarray` with blocks and steps (the dictionary's examples come out as shown), `histogram … samples 3` gives the interval centers and counts, `filter` a 3×3 convolution, `evalformula` with a record, a list or a list of formulas, `roots of` with complex roots as pairs, `fitpolynomial` with its formula text.

## Commands

1. **Making and reading arrays:** `creatematrix` ("1", "x", "y", "d"; `as matrix`), `extractarray` (`at` an index or a list, `for`, `step`, `blocksize`, `as array of real`/`list of real`/`list of integer`/`real`), `changearray`, `insertarray`, `reversearray`, `maskarray` (items, or a matrix's rows), `replacemissingvalue`, `removemissingvalue`.
2. **Arithmetic:** `addlist`, `sublist`, `multlist`, `divlist`, on numbers, lists, arrays and matrices in any pairing, and polynomials; lists of unequal length are -50.
3. **Statistics and filters:** `runningsum`, `statlist`, `histogram` (with and without `samples`, `minimum`, `maximum`), `resamplematrix` (blocks regular or irregular; mean, minimum, maximum, stdev, missing value, sum, median, dispersion), `filter`.
4. **`evalformula`:** a parser for the dictionary's language (operators by its precedence, `;` and returns between expressions, `//` comments, a list of formulas, variables from a list or a record, numbers, lists, arrays and matrices, `as matrix`), and its functions: algebra, transcendental, Bessel (libm's `j0` … `yn`), the GSL ones (`EllipticE`, `EllipticK`, `IncEllipticE`, `IncEllipticF`, `EllipticP`, `IncEllipticP` by Carlson's forms; `lambertW0`, `lambertWm1`), and the array functions (`norm`, `norm2`, `sum`, `runsum`, `diff`, `int`, `count`, `rest`, `butlast`, `concat`).
5. **Polynomials and fitting:** `evalpolynomial` (at a number or an array), `roots of` (eigenvalues of the companion matrix, with Accelerate's LAPACK; complex roots with `complex`), `composepolynomial`, `pade approximant`, `fitpolynomial` (least squares, with `constraints` and `number formatting`), `fitrational`.
6. **Binary files:** `read binary` and `write binary` (real, small real, integer, small integer, byte; `skip`, `step`, `blocksize`, `length`, `starting at`, `big endian`, `signed`), with the same path handling and file rules as the file commands.

Arrays stay numbers throughout: no descriptor for each number (a hundred million of them took 15 GB before), and Accelerate (vDSP) where it's simpler or faster for large arrays.

## Testing

- **SatimageOSAX fixtures** in `Fixtures/Arrays`, from `generate.py` (as the Math and Lists fixtures were): every command and parameter at typical values, edges (empty, one item, NaN, infinities, missing values, huge), every pairing of numbers, lists, arrays and matrices, and errors. `evalformula` gets every operator and function, with a few hundred random inputs for the numeric functions; `read binary`/`write binary` work in `$TMP` copies.
- **Where Satimage is broken,** the case moves to `Fixtures/ArraysFixes`, recorded from MTC_OSAX, and goes in this plan, the README's differences and the release notes.
- **Unit tests** for each command, and for the parts that stand alone: the formula parser, the special functions against published values, fitting (residuals and constraints met), root finding (each root a root), and arrays checked directly as `sortlist`'s results are.
- **End to end:** `Scripts/e2e/arrays.applescript` (and `arrays-fixes`) through the real app, with `parity.sh` against SatimageOSAX.
- Numeric results that can differ in the last digits (Satimage's Intel math library, LAPACK) are compared within a tolerance, and the README says so, as it does for the math functions.

## Steps

1. Copy the suite's commands and types into `MTC_OSAX.sdef` verbatim, with placeholder handlers; SDEF consistency tests pass.
2. Record the fixtures from SatimageOSAX; settle the behaviors they show.
3. Implement in the order above, each group with its tests, committed as it's done.
4. Fixes for anything Satimage gets wrong, recorded from MTC_OSAX.
5. README (move Arrays out of "Not implemented", the differences, the 1.1 release notes), PLAN.md, e2e scripts; full test suite.

## Decisions

1. Hidden and obsolete commands are left out and listed in the README (2026-10-15); see above.
2. This is part of 1.1, with the faster `sortlist`; its changes go in the README's 1.1 release notes (2026-10-15).

## Results

- [x] All 26 commands, and the `matrix`, `polynomial`, `statsrecord` and `fitrecord` types, in the dictionary; the SDEF consistency tests pass. `byte` is in MTC_OSAX's Types suite for `as byte`: Satimage defined it in its hidden Applescript types suite, and without it `as byte` didn't compile (found recording a fix from a script; the fixtures had sent the type code).
- [x] 629 fixtures recorded from SatimageOSAX in `Fixtures/Arrays` (with `Files` for the binary files; 667 with `createarray`'s and `randomarray`'s): every command and parameter, edges and errors, and 110 cases probed for `evalformula`'s language. All replay; reals within 16 units in the last place or 16 units of 1 (math libraries differ), fits within 1e-12.
- [x] 23 cases where MTC_OSAX follows the dictionary, recorded from MTC_OSAX in `Fixtures/ArraysFixes` (below), in the README's Fixes.
- [x] Unit tests for each part (`Tests/ArraysTests`), `Scripts/e2e/arrays.applescript` (the same output from both apps through `parity.sh`) and `arrays-fixes.applescript`.

What the recordings showed, and how MTC_OSAX matches it:

- **Precision of reading:** an `array of real` can also hold 4-byte reals (the tag `gnis`), which SatimageOSAX's `read binary` returned; `ArrayOfReal` reads both, and polynomials (`Poly`) are the same data with another type. Fixtures keep both as numbers.
- **`evalformula`'s language**, probed: the usual precedence (the dictionary lists `^` last), `^` left to right, unary `-` `+` `!` only where an expression starts and applying to the power that follows (`-2^2` is -4, `1+-2` a syntax error), strtod's numbers, `pi`, names without regard to case, a list of one number as a number, and Satimage's own error numbers.
- **Its special functions** are GSL's (Carlson's elliptic integrals with the angle's periods, Lambert's W returning -1 outside its domain), written as GSL computes them.
- **`roots of`** is Numerical Recipes' zrhqr without its sort: EISPACK's balanc and hqr on the companion matrix with the coefficients across the first row, in hqr's order, with each pair's + imaginary part first. GSL's solver (tried first) found the same roots in another order.
- **`fitrational`** is Numerical Recipes' ratlsq on the points: five rounds of least squares toward the smallest largest error, weighting each point by its last error; the fit error is the largest error. This reproduces Satimage's coefficients to ten places.
- **Statistics:** the variance divides by n, the kurtosis isn't less 3, the median is the upper one (over every item, sorted with NaN last), a matrix's running sum goes column by column.

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `removemissingvalue` | -1708 | Removes what `replacemissingvalue` replaces |
| `extractarray … as list of integer` beyond 32 bits | Wrapped (1.0E+10 became 1410065408) | -1700 |
| `divlist` of a polynomial by a number | -50 | Scales it |
| `histogram … minimum` | Also counted numbers up to an interval below the minimum | Only from the minimum |
| `filter … reduced false` | Border values in the wrong places | As if the matrix had zeros around it |
| `filter` of a matrix too small to reduce | -108 | -50 |
| `resamplematrix … blocksize` of 0 | No result | -50 |
| `composepolynomial` of the empty polynomial | No result | The empty polynomial |
| `evalformula "sqr(x)"` | Error 5 | Works |
| `evalformula` comment with a space, or after an expression | Error 16 | Works |
| `evalformula "int(f,x)"` | ∫x df | ∫f dx, as the dictionary says |
| `fitpolynomial` error of an exact fit | 3.8e-8 | About 1e-15 |
| `read binary`/`write binary` with a path as text | Error 1 | A path, as for the file commands |
| `write binary … as text` | Accepted | -50 |
| `read binary` of integers | 4-byte reals (16,777,217 became 16,777,216) | 8-byte reals |

## Audit (2026-10-15)

An audit of the suite for code quality, security and speed, with each case reproduced through the dispatcher, found
inputs that crashed or hung MTC_OSAX (its commands run on the main thread, one at a time, so a hang stops them all):

- [x] `histogram` with `minimum`/`maximum` too far apart for a real (or so close the interval width is 0) crashed
  converting NaN to an integer.
- [x] `evalformula` with a few thousand nested parentheses (or a sum of 100,000 terms, or 100,000 `!`) ran out of
  stack. Formulas may nest at most 512 levels (-50); operators of one precedence are kept in one node, so a long sum
  no longer nests.
- [x] `roots of` a polynomial with an infinite coefficient looped forever balancing the matrix: -50 for a coefficient
  that isn't finite, -1 if the matrix can't be built.
- [x] `read binary` of a file over 4 GB with overlapping blocks overflowed and crashed; it had no limit on its result
  (a 20 KB file gave 600 MB).
- [x] `write binary` to a named pipe waited forever for a reader.
- [x] Limits, as for `createarray`: `read binary` returns at most 100,000,000 numbers; `creatematrix "d"` with a
  list of diagonal numbers at most 10,000 of them (a 100,000 list tried 80 GB); `creatematrix`'s axes are checked
  before they're made. The slow algorithms get limits that keep them to seconds: `roots of` degree 1,000,
  `pade approximant` 1,000 and 1,000, `fitpolynomial` degree 100, `fitrational` 100 and 100, `composepolynomial`'s
  result degree 100,000, and multiplying polynomials 10,000,000,000 products of coefficients; and the fits'
  points × coefficients at most 100,000,000.
- [x] Lists nested more than 512 levels are -50 in `addlist` and the others, `replacemissingvalue` and
  `evalformula`'s variables, as they already were elsewhere.
- [x] `read binary` and `write binary` take only regular files: -50 for a device, pipe or socket (Foundation's
  refusal said "Permission denied").

Speed (measured on the commands through the dispatcher):

- [x] `runningsum` of 10,000,000: 456 ms (a closure capturing its sum) to about 15.
- [x] The median (`statlist … with kurtosis`, `resamplematrix`) by selection instead of sorting: 938 ms to about 160.
- [x] Lists read with one look at the list (`RawList.forEachItem`) and made with `AEPutPtr` instead of a descriptor
  per number: `extractarray … as list of real` of 1,000,000 282 ms to 100, `addlist` of a list and a number 456 to
  197 (of two lists 604 to 288), `replacemissingvalue` of a list 353 to 188, `evalformula` with a list 378 to 143,
  `statlist` of a list 132 to 98. (One `AEGetNthPtr` of any type for each item would be quicker still, but for an
  item that is itself a list it copies the whole list.)
- [x] `write binary` straight into its buffer: 120 ms to about 50.
- [x] `read binary` reads only the bytes its blocks cover, instead of mapping the file: a few milliseconds slower for
  10,000,000 reals (19 to 25), but a mapped file cut short while it's read can crash the process (SIGBUS).

Everything else measured the same before and after (a benchmark of every command through the dispatcher, at
1,000,000 to 10,000,000 numbers). Still slow, and left as they are: `resamplematrix` with blocks of one (an array
for each block, about 100 ns a number), `histogram` without `samples` of many distinct numbers (a dictionary,
165 ns), and `fitpolynomial` at high degrees (2 s for degree 60 of 10,000 points; LAPACK would be faster but give
other last digits than the fixtures).

Code quality: one polynomial multiply and add (they were in `Arithmetic` and `Polynomials`), one reading of
`extractarray`'s and `changearray`'s blocks, the size limit's message made in one place, one test for `missing value`,
the same fast list reading in `Values` and `Arithmetic`, no needless `indirect`, a matrix read once (`runningsum`,
`evalformula`'s variables), a list's item types checked without a descriptor for each (`maskarray`), a number format
checked once per fit.
