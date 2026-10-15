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
