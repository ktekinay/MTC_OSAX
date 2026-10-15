# Generates cases.json for createarray and randomarray (from Satimage's Arrays suite), recorded from SatimageOSAX.
# randomarray without a seed can't be replayed; those cases only check sizes, through mark_random.py. Run: python3 generate.py
import json, os

cases, names = [], set()
def case(name, script, random=False):
    assert name.lower() not in names, name
    names.add(name.lower())
    cases.append({"name": name, "script": script} | ({"random": True} if random else {}))

for n in (1, 2, 3, 10):
    case(f"createarray-{n}", f"createarray {n}")
for name, script in [
    ("createarray-range", "createarray 5 range {2, 3}"),
    ("createarray-range-one", "createarray 1 range {2, 3}"),
    ("createarray-range-reversed", "createarray 3 range {3, 1}"),
    ("createarray-range-equal", "createarray 3 range {2, 2}"),
    ("createarray-range-negative", "createarray 4 range {-1.5, 1.5}"),
    ("createarray-range-fraction", "createarray 7 range {0.1, 0.7}"),
    ("createarray-range-thirds", "createarray 4 range {0, 1}"),
    ("createarray-range-large", "createarray 11 range {-1.0E+10, 1.0E+10}"),
    ("createarray-range-text", 'createarray 3 range {"1", "2"}'),
    ("createarray-range-one-item", "createarray 3 range {1}"),
    ("createarray-range-three-items", "createarray 3 range {1, 2, 3}"),
    ("createarray-range-number", "createarray 3 range 1"),
    ("createarray-real-size", "createarray 2.7"),
    ("createarray-real-size-half", "createarray 2.5"),
    ("createarray-real-size-low", "createarray 2.2"),
    ("createarray-text-size", 'createarray "3"'),
    ("createarray-zero", "createarray 0"),
    ("createarray-negative", "createarray -2"),
    ("createarray-no-parameter", "createarray"),
    ("createarray-list", "createarray {3}"),
    ("randomarray-seed", "randomarray 3 seed 12345"),
    ("randomarray-seed-repeats", "randomarray 3 seed 12345\nrandomarray 3 seed 12345"),
    ("randomarray-seed-range", "randomarray 4 range {10, 20} seed 1"),
    ("randomarray-seed-zero", "randomarray 5 seed 0"),
    ("randomarray-seed-negative", "randomarray 5 seed -7"),
    ("randomarray-seed-large", "randomarray 3 seed 4000000000\nrandomarray 3 seed 4000000000"),
    ("randomarray-seed-long", "randomarray 700 seed 42"),
    ("randomarray-seed-range-reversed", "randomarray 3 range {1, 0} seed 3"),
    ("randomarray-seed-real", "randomarray 3 seed 2.6"),
    ("randomarray-zero", "randomarray 0"),
    ("randomarray-negative", "randomarray -1"),
    ("randomarray-no-parameter", "randomarray"),
    ("randomarray-range-bad", "randomarray 3 range {1} seed 1"),
]:
    case(name, script)
case("randomarray-unseeded", "randomarray 5", random=True)
case("randomarray-unseeded-range", "randomarray 5 range {100, 101}", random=True)

# The rest of the suite (PLAN-Arrays.md), but for its hidden commands and the obsolete extractitem.
A5 = "(createarray 5)"                                  # {0, 1, 2, 3, 4}
A12 = "(createarray 12)"
R = lambda n, seed=1, lo=-10, hi=10: f"(randomarray {n} range {{{lo}, {hi}}} seed {seed})"
NANS = "(divlist {1, 0, -1, 0} with {1, 0, 1, 0})"      # a list with missing values for 0/0
NAN_ARRAY = "(divlist (createarray 4) with (createarray 4))"  # an array starting with NaN (0/0)
def mat(ncols, nrows, values):
    return f"{{class:matrix, ncols:{ncols}, nrows:{nrows}, array of real:{{{', '.join(map(str, values))}}}}}"
M23 = mat(2, 3, [1, 2, 3, 4, 5, 6])                    # 3 rows of 2
M33 = mat(3, 3, range(1, 10))
M44 = mat(4, 4, range(1, 17))

# creatematrix
for kind in ("1", "x", "y", "d"):
    case(f"creatematrix-{kind}", f'creatematrix "{kind}" ncols 3 nrows 2')
    case(f"creatematrix-{kind}-as-matrix", f'creatematrix "{kind}" ncols 3 nrows 2 as matrix')
for name, script in [
    ("creatematrix-x-range", 'creatematrix "x" ncols 3 nrows 2 range {-1, 1}'),
    ("creatematrix-y-range", 'creatematrix "y" ncols 2 nrows 3 range {-1, 1} as matrix'),
    ("creatematrix-x-list", 'creatematrix "x" ncols {5, 7, 9} nrows 2 as matrix'),
    ("creatematrix-y-list", 'creatematrix "y" ncols 2 nrows {5, 7} as matrix'),
    ("creatematrix-x-array", 'creatematrix "x" ncols (createarray 3 range {-1, 1}) nrows 2 as matrix'),
    ("creatematrix-x-one-column", 'creatematrix "x" ncols 1 nrows 3 range {2, 5}'),
    ("creatematrix-d-diagonal", 'creatematrix "d" diagonal {1, 2, 3} as matrix'),
    ("creatematrix-d-diagonal-array", 'creatematrix "d" diagonal (createarray 2 range {5, 6})'),
    ("creatematrix-d-diagonal-number", 'creatematrix "d" diagonal 2.5 ncols 3 nrows 3 as matrix'),
    ("creatematrix-d-identity", 'creatematrix "d" ncols 3 nrows 3 as matrix'),
    ("creatematrix-d-not-square", 'creatematrix "d" ncols 3 nrows 2 as matrix'),
    ("creatematrix-uppercase", 'creatematrix "X" ncols 2 nrows 2'),
    ("creatematrix-unknown", 'creatematrix "z" ncols 2 nrows 2'),
    ("creatematrix-no-ncols", 'creatematrix "1" nrows 2'),
    ("creatematrix-zero", 'creatematrix "1" ncols 0 nrows 2'),
    ("creatematrix-negative", 'creatematrix "1" ncols -1 nrows 2'),
    ("creatematrix-real-size", 'creatematrix "1" ncols 2.5 nrows 2'),
    ("creatematrix-as-array", 'creatematrix "x" ncols 2 nrows 2 as array of real'),
    ("creatematrix-as-list", 'creatematrix "x" ncols 2 nrows 2 as list'),
    ("creatematrix-no-parameter", "creatematrix"),
]:
    case(name, script)

# extractarray
for name, script in [
    ("extractarray-default", f"extractarray {A5}"),
    ("extractarray-at", f"extractarray {A5} at 3"),
    ("extractarray-at-for", f"extractarray {A5} at 2 for 3"),
    ("extractarray-all", f"extractarray {A5} for -1"),
    ("extractarray-at-all", f"extractarray {A5} at 3 for -1"),
    ("extractarray-for-minus-two", f"extractarray {A5} at 2 for -2"),
    ("extractarray-doc", "extractarray (createarray 50) for 3 at 1 step 10 blocksize 2"),
    ("extractarray-step", f"extractarray {A12} for 3 step 4"),
    ("extractarray-blocksize", f"extractarray {A12} for 2 blocksize 3"),
    ("extractarray-blocks-all", f"extractarray {A12} for -1 step 5 blocksize 2"),
    ("extractarray-blocks-partial", f"extractarray {A12} at 10 for 2 step 2 blocksize 2"),
    ("extractarray-blocksize-over-step", f"extractarray {A12} for 2 step 2 blocksize 3"),
    ("extractarray-indexes", f"extractarray {A5} at {{1, 3, 5}}"),
    ("extractarray-indexes-reversed", f"extractarray {A5} at {{5, 1}}"),
    ("extractarray-indexes-repeated", f"extractarray {A5} at {{2, 2}}"),
    ("extractarray-indexes-with-for", f"extractarray {A5} at {{1, 2}} for 3 step 2"),
    ("extractarray-indexes-empty", f"extractarray {A5} at {{}}"),
    ("extractarray-indexes-out", f"extractarray {A5} at {{1, 9}}"),
    ("extractarray-at-zero", f"extractarray {A5} at 0"),
    ("extractarray-at-negative", f"extractarray {A5} at -1"),
    ("extractarray-at-beyond", f"extractarray {A5} at 6"),
    ("extractarray-for-beyond", f"extractarray {A5} at 4 for 5"),
    ("extractarray-at-real", f"extractarray {A5} at 2.5"),
    ("extractarray-for-zero", f"extractarray {A5} for 0"),
    ("extractarray-as-real", f"extractarray {A5} at 2 as real"),
    ("extractarray-as-real-several", f"extractarray {A5} for 2 as real"),
    ("extractarray-as-small-real", f"extractarray {A5} at 2 as small real"),
    ("extractarray-as-list-of-real", f"extractarray {A5} for -1 as list of real"),
    ("extractarray-as-list-of-integer", "extractarray (createarray 7 range {-1.5, 1.5}) for -1 as list of integer"),
    ("extractarray-as-list-of-integer-halves", "extractarray (createarray 6 range {0.5, 5.5}) for -1 as list of integer"),
    ("extractarray-as-list-of-integer-huge", "extractarray (createarray 2 range {1.0E+10, -1.0E+10}) for -1 as list of integer"),
    ("extractarray-as-list", f"extractarray {A5} for -1 as list"),
    ("extractarray-as-array", f"extractarray {A5} for -1 as array of real"),
    ("extractarray-as-integer", f"extractarray {A5} at 2 as integer"),
    ("extractarray-nan-as-list", f"extractarray {NAN_ARRAY} for -1 as list of real"),
    ("extractarray-nan-as-integers", f"extractarray {NAN_ARRAY} for -1 as list of integer"),
    ("extractarray-list", "extractarray {1, 2.5, 3} for -1"),
    ("extractarray-list-as-list", "extractarray {1, 2.5, 3} at 2 for -1 as list of real"),
    ("extractarray-list-text", 'extractarray {"1", "2.5"} for -1 as list of real'),
    ("extractarray-list-missing", "extractarray {1, missing value, 3} for -1 as list of real"),
    ("extractarray-list-nested", "extractarray {1, {2, 3}} for -1"),
    ("extractarray-empty-list", "extractarray {} for -1"),
    ("extractarray-number", "extractarray 7 for -1"),
    ("extractarray-matrix", f"extractarray {M23} at 3 for 2"),
    ("extractarray-text", 'extractarray "abc"'),
    ("extractarray-no-parameter", "extractarray"),
]:
    case(name, script)

# changearray
for name, script in [
    ("changearray-doc", "changearray (createarray 50) at 1 step 10 blocksize 2 into (createarray 6 range {-99, -99})"),
    ("changearray-one", f"changearray {A5} at 3 into {{9}}"),
    ("changearray-default-at", f"changearray {A5} into {{7, 8}}"),
    ("changearray-several", f"changearray {A5} at 2 into {{7, 8, 9}}"),
    ("changearray-indexes", f"changearray {A5} at {{1, 4}} into {{7, 8}}"),
    ("changearray-indexes-short", f"changearray {A5} at {{1, 4}} into {{7}}"),
    ("changearray-indexes-long", f"changearray {A5} at {{1}} into {{7, 8}}"),
    ("changearray-step", f"changearray {A12} at 2 step 3 into {{-1, -2, -3}}"),
    ("changearray-blocks", f"changearray {A12} step 4 blocksize 2 into {{-1, -2, -3, -4}}"),
    ("changearray-blocks-not-multiple", f"changearray {A12} step 4 blocksize 2 into {{-1, -2, -3}}"),
    ("changearray-past-end", f"changearray {A5} at 4 into {{7, 8, 9}}"),
    ("changearray-at-zero", f"changearray {A5} at 0 into {{7}}"),
    ("changearray-at-beyond", f"changearray {A5} at 6 into {{7}}"),
    ("changearray-into-array", f"changearray {A5} at 2 into (createarray 2 range {{9, 8}})"),
    ("changearray-into-number", f"changearray {A5} at 2 into 9"),
    ("changearray-list", "changearray {1, 2, 3} at 2 into {9}"),
    ("changearray-matrix", f"changearray {M23} at 2 into {{9}}"),
    ("changearray-no-into", f"changearray {A5} at 2"),
]:
    case(name, script)

# insertarray
for name, script in [
    ("insertarray-doc", "insertarray (createarray 10 range {-10, -1}) blocksize 2 into (createarray 30) step 5 at 1 for 3"),
    ("insertarray-default", f"insertarray {{7, 8}} into {A5}"),
    ("insertarray-at-zero", f"insertarray {{7, 8}} into {A5} at 0"),
    ("insertarray-at", f"insertarray {{7, 8}} into {A5} at 2"),
    ("insertarray-at-end", f"insertarray {{7}} into {A5} at 5"),
    ("insertarray-at-minus-one", f"insertarray {{7}} into {A5} at -1"),
    ("insertarray-at-beyond", f"insertarray {{7}} into {A5} at 9"),
    ("insertarray-indexes", f"insertarray {{7, 8}} into {A5} at {{0, 3}}"),
    ("insertarray-indexes-same", f"insertarray {{7, 8}} into {A5} at {{2, 2}}"),
    ("insertarray-indexes-mismatch", f"insertarray {{7, 8}} into {A5} at {{1}}"),
    ("insertarray-for", f"insertarray {{7, 8, 9}} into {A12} at 0 for 3 step 2"),
    ("insertarray-for-blocks", f"insertarray {{7, 8, 9, 10}} into {A12} at 1 for 2 step 3 blocksize 2"),
    ("insertarray-for-too-many", f"insertarray {{7, 8}} into {A5} at 0 for 3"),
    ("insertarray-step-past-end", f"insertarray {{7, 8, 9}} into {A5} at 2 for 3 step 2"),
    ("insertarray-number", f"insertarray 7 into {A5} at 1"),
    ("insertarray-array", f"insertarray (createarray 2 range {{8, 9}}) into {{1, 2}}"),
    ("insertarray-into-list", "insertarray {7} into {1, 2, 3} at 1"),
    ("insertarray-no-into", "insertarray {7}"),
]:
    case(name, script)

# reversearray
for name, script in [
    ("reversearray-list", "reversearray {1, 2, 3}"),
    ("reversearray-array", f"reversearray {A5}"),
    ("reversearray-one", "reversearray {7}"),
    ("reversearray-number", "reversearray 7"),
    ("reversearray-empty", "reversearray {}"),
    ("reversearray-missing", "reversearray {1, missing value, 3}"),
    ("reversearray-matrix", f"reversearray {M23}"),
    ("reversearray-text", 'reversearray {"1", "2"}'),
]:
    case(name, script)

# maskarray
for name, script in [
    ("maskarray-array", f"maskarray {A5} with {{1, 0, 1, 0, 1}}"),
    ("maskarray-list", "maskarray {5, 6, 7} with {0, 1, 1}"),
    ("maskarray-mask-array", f"maskarray {A5} with (createarray 5 range {{1, 0}})"),
    ("maskarray-mask-values", f"maskarray {A5} with {{2, -1, 0.5, 0, 0}}"),
    ("maskarray-mask-nan", f"maskarray {{1, 2, 3, 4}} with {NAN_ARRAY}"),
    ("maskarray-mask-short", f"maskarray {A5} with {{1, 0}}"),
    ("maskarray-mask-long", "maskarray {1, 2} with {1, 0, 1}"),
    ("maskarray-none", f"maskarray {A5} with {{0, 0, 0, 0, 0}}"),
    ("maskarray-matrix", f"maskarray {M23} with {{1, 0, 1}}"),
    ("maskarray-matrix-wrong", f"maskarray {M23} with {{1, 0}}"),
    ("maskarray-several", f"maskarray {{{A5}, {{5, 6, 7, 8, 9}}}} with {{1, 1, 0, 0, 1}}"),
    ("maskarray-no-with", f"maskarray {A5}"),
]:
    case(name, script)

# replacemissingvalue, removemissingvalue
for name, script in [
    ("replacemissingvalue-list", f"replacemissingvalue {NANS} with 999"),
    ("replacemissingvalue-array", f"replacemissingvalue {NAN_ARRAY} with -1"),
    ("replacemissingvalue-literal", "replacemissingvalue {1, missing value, 3} with 0"),
    ("replacemissingvalue-none", "replacemissingvalue {1, 2} with 0"),
    ("replacemissingvalue-text-with", f'replacemissingvalue {NANS} with "999"'),
    ("replacemissingvalue-several", f"replacemissingvalue {{{NAN_ARRAY}, {{missing value, 2}}}} with 5"),
    ("replacemissingvalue-with-nan", f"replacemissingvalue {{1, missing value}} with (divlist 0 with 0)"),
    ("replacemissingvalue-no-with", f"replacemissingvalue {NANS}"),
    ("removemissingvalue-list", "removemissingvalue {1, missing value, 2}"),
    ("removemissingvalue-array", f"removemissingvalue {NAN_ARRAY}"),
    ("removemissingvalue-none", "removemissingvalue {1, 2}"),
]:
    case(name, script)

# addlist, sublist, multlist, divlist
operands = [
    ("number-number", "2", "3"),
    ("number-list", "2", "{1, 2, 3}"),
    ("list-number", "{1, 2, 3}", "2"),
    ("list-list", "{1, 2, 3}", "{10, 20, 30}"),
    ("array-array", A5, "(createarray 5 range {10, 14})"),
    ("array-list", A5, "{1, 1, 1, 1, 1}"),
    ("list-array", "{1, 1, 1, 1, 1}", A5),
    ("number-array", "2", A5),
    ("array-number", A5, "2"),
    ("matrix-number", M23, "2"),
    ("number-matrix", "2", M23),
    ("matrix-matrix", M23, M23),
    ("matrix-array", M23, "(createarray 6)"),
    ("matrix-list", M23, "{1, 2, 3, 4, 5, 6}"),
    ("mismatch", "{1, 2}", "{1, 2, 3}"),
    ("array-mismatch", A5, "(createarray 3)"),
    ("text", '{"1", "2"}', '"3"'),
    ("missing", "{1, missing value}", "{2, 3}"),
    ("nested", "{1, {2, 3}}", "{1, {2, 3}}"),
    ("empty", "{}", "{}"),
    ("one-item-list", "{5}", "{1, 2, 3}"),
    ("overflow", "{1.0E+308, 1}", "{1.0E+308, 1}"),
]
for command, symbol in (("addlist", "+"), ("sublist", "-"), ("multlist", "*"), ("divlist", "/")):
    for label, left, right in operands:
        case(f"{command}-{label}", f"{command} {left} with {right}")
    case(f"{command}-no-with", f"{command} {{1, 2}}")
for name, script in [
    ("divlist-zero", "divlist {1, -1, 0} with 0"),
    ("divlist-zero-array", f"divlist {A5} with 0"),
    ("divlist-zero-number", "divlist 1 with 0"),
    ("divlist-doc", "divlist 1 with {-2, -1, 0, 1, 2}"),
    ("addlist-polynomials", "addlist (composepolynomial {1, 1} with {0, 2}) with {1, 2, 3}"),
    ("multlist-polynomials", "multlist (composepolynomial {1, 1} with {0, 2}) with 3"),
    ("multlist-polynomial-polynomial", "set p to composepolynomial {1, 1} with {0, 2}\nmultlist p with p"),
    ("multlist-polynomial-list", "set p to composepolynomial {1, 1} with {0, 2}\nmultlist p with {1, 2, 3}"),
    ("addlist-polynomial-polynomial", "set p to composepolynomial {1, 1} with {0, 2}\nset q to composepolynomial {0, 0, 1} with {1, 1}\naddlist p with q"),
    ("sublist-list-polynomial", "set p to composepolynomial {1, 1} with {0, 2}\nsublist {5} with p"),
    ("divlist-polynomial-number", "set p to composepolynomial {1, 1} with {0, 2}\ndivlist p with 2"),
    ("addlist-polynomial-array", "set p to composepolynomial {1, 1} with {0, 2}\naddlist p with (createarray 3)"),
    ("addlist-polynomial-number", "set p to composepolynomial {1, 1} with {0, 2}\naddlist p with 10"),
    ("addlist-list-array-different", "addlist {1, 2} with (createarray 3)"),
    ("addlist-matrix-different-shape", "addlist {class:matrix, ncols:2, nrows:1, array of real:{1, 2}} with {class:matrix, ncols:1, nrows:2, array of real:{1, 2}}"),
    ("addlist-list-nested-array", "addlist {1, (createarray 2)} with {1, {2, 3}}"),
    ("addlist-integers", "addlist {1, 2} with {3, 4}"),
    ("addlist-boolean", "addlist {true} with {1}"),
]:
    case(name, script)

# runningsum
for name, script in [
    ("runningsum-list", "runningsum {1, 2, 3, 4}"),
    ("runningsum-array", f"runningsum {A5}"),
    ("runningsum-one", "runningsum {7}"),
    ("runningsum-number", "runningsum 7"),
    ("runningsum-empty", "runningsum {}"),
    ("runningsum-missing", "runningsum {1, missing value, 3}"),
    ("runningsum-matrix", f"runningsum {M23}"),
]:
    case(name, script)

# statlist
for name, script in [
    ("statlist-list", "statlist {1, 2, 3, 4, 10}"),
    ("statlist-kurtosis", "statlist {1, 2, 3, 4, 10} with kurtosis"),
    ("statlist-kurtosis-false", "statlist {1, 2, 3, 4, 10} without kurtosis"),
    ("statlist-even-median", "statlist {4, 1, 3, 2} with kurtosis"),
    ("statlist-array", f"statlist {R(100)} with kurtosis"),
    ("statlist-one", "statlist {5} with kurtosis"),
    ("statlist-constant", "statlist {2, 2, 2} with kurtosis"),
    ("statlist-ties", "statlist {3, 1, 3, 1} with kurtosis"),
    ("statlist-missing", "statlist {1, missing value, 3, missing value} with kurtosis"),
    ("statlist-nan-array", f"statlist {NAN_ARRAY} with kurtosis"),
    ("statlist-all-missing", "statlist {missing value} with kurtosis"),
    ("statlist-empty", "statlist {}"),
    ("statlist-number", "statlist 5"),
    ("statlist-text", 'statlist {"1", "2"}'),
    ("statlist-matrix", f"statlist {M23}"),
    ("statlist-negative", "statlist {-5, -1, -3}"),
    ("statlist-infinite", "statlist {1, 1.0E+308, 1.0E+308}"),
]:
    case(name, script)

# histogram
for name, script in [
    ("histogram-raw", "histogram {1, 1, 2, 5}"),
    ("histogram-raw-array", f"histogram (createarray 4 range {{3, 0}})"),
    ("histogram-raw-reals", "histogram {0.5, 0.25, 0.5, 2}"),
    ("histogram-samples", "histogram (createarray 10) samples 3"),
    ("histogram-samples-one", "histogram (createarray 10) samples 1"),
    ("histogram-samples-random", f"histogram {R(200, 3, 0, 1)} samples 10"),
    ("histogram-minimum", "histogram (createarray 10) samples 2 minimum 4"),
    ("histogram-maximum", "histogram (createarray 10) samples 2 maximum 5"),
    ("histogram-range", "histogram (createarray 10) samples 4 minimum -2 maximum 12"),
    ("histogram-range-inside", "histogram (createarray 10) samples 2 minimum 3 maximum 6"),
    ("histogram-on-edges", "histogram {0, 1, 2, 3, 4} samples 2 minimum 0 maximum 4"),
    ("histogram-minimum-only", "histogram {1, 2} minimum 0"),
    ("histogram-samples-zero", "histogram {1, 2} samples 0"),
    ("histogram-equal-values", "histogram {2, 2, 2} samples 3"),
    ("histogram-missing", "histogram {1, missing value, 2, 2} samples 2"),
    ("histogram-empty", "histogram {} samples 2"),
    ("histogram-number", "histogram 5"),
]:
    case(name, script)

# resamplematrix
for wanted in ("mean", "minimum", "maximum", "stdev", "missing value", "sum", "median", "dispersion"):
    case(f"resamplematrix-{wanted.replace(' ', '-')}", f'resamplematrix {M44} blocksize {{2, 2}} wanted "{wanted}"')
for name, script in [
    ("resamplematrix-default", f"resamplematrix {M44} blocksize {{2, 2}}"),
    ("resamplematrix-rows", f"resamplematrix {M44} blocksize {{4, 1}}"),
    ("resamplematrix-columns", f"resamplematrix {M44} blocksize {{1, 4}}"),
    ("resamplematrix-uneven", f"resamplematrix {M33} blocksize {{2, 2}}"),
    ("resamplematrix-irregular", f"resamplematrix {M44} blocksize {{{{1, 3}}, {{2, 2}}}}"),
    ("resamplematrix-irregular-short", f"resamplematrix {M44} blocksize {{{{1, 1}}, 2}}"),
    ("resamplematrix-several", f'resamplematrix {M44} blocksize {{2, 2}} wanted {{"mean", "sum"}}'),
    ("resamplematrix-nan", f"resamplematrix {mat(2, 2, [1, 2, 3, 4])} blocksize {{2, 2}} wanted \"missing value\""),
    ("resamplematrix-unknown", f'resamplematrix {M44} blocksize {{2, 2}} wanted "mode"'),
    ("resamplematrix-blocksize-one", f"resamplematrix {M44} blocksize 2"),
    ("resamplematrix-blocksize-zero", f"resamplematrix {M44} blocksize {{0, 2}}"),
    ("resamplematrix-too-big", f"resamplematrix {M44} blocksize {{5, 5}}"),
    ("resamplematrix-array-data", "resamplematrix {class:matrix, ncols:2, nrows:2, array of real:(createarray 4)} blocksize {1, 2}"),
    ("resamplematrix-not-matrix", f"resamplematrix {A5} blocksize {{1, 1}}"),
    ("resamplematrix-wrong-size", f"resamplematrix {mat(2, 2, [1, 2, 3])} blocksize {{1, 1}}"),
]:
    case(name, script)

# filter
for name, script in [
    ("filter-identity", f"filter {M33} using {{0, 0, 0, 0, 1, 0, 0, 0, 0}}"),
    ("filter-blur", f"filter {M44} using {{1, 2, 1, 2, 4, 2, 1, 2, 1}}"),
    ("filter-edges", f"filter {M44} using {{0, 1, 0, 1, -4, 1, 0, 1, 0}}"),
    ("filter-not-reduced", f"filter {M33} using {{0, 0, 0, 0, 1, 0, 0, 0, 0}} reduced false"),
    ("filter-not-reduced-blur", f"filter {M44} using {{1, 1, 1, 1, 1, 1, 1, 1, 1}} reduced false"),
    ("filter-asymmetric", f"filter {M44} using {{1, 2, 3, 4, 5, 6, 7, 8, 9}}"),
    ("filter-array-kernel", f"filter {M33} using (createarray 9)"),
    ("filter-small", f"filter {mat(2, 2, [1, 2, 3, 4])} using {{1, 1, 1, 1, 1, 1, 1, 1, 1}}"),
    ("filter-short-kernel", f"filter {M33} using {{1, 2, 3}}"),
    ("filter-not-matrix", f"filter {A5} using {{0, 0, 0, 0, 1, 0, 0, 0, 0}}"),
]:
    case(name, script)

# evalformula
X = R(200, 7, -10, 10)
for name, formula, variables in [
    ("evalformula-number", "1+2*3", "{}"),
    ("evalformula-doc-atan2", "atan2(y,x)", "{y:1.7320508075688772, x:1}"),
    ("evalformula-list-variables", "a*x^2+y^2", '{"a", 2.4, "x", {1, 2, 3}, "y", (createarray 3)}'),
    ("evalformula-record-variables", "a*x^2+y^2", "{a:2.4, x:{1, 2, 3}, y:(createarray 3)}"),
    ("evalformula-array", "2*x+1", '{"x", createarray 3}'),
    ("evalformula-precedence", "1+2*3-4/2", "{}"),
    ("evalformula-unary-minus", "-x^2", "{x:3}"),
    ("evalformula-unary-minus-product", "-2*-3", "{}"),
    ("evalformula-power", "2^3^2", "{}"),
    ("evalformula-power-negative", "(-8)^(1/3)", "{}"),
    ("evalformula-parentheses", "(1+2)*3", "{}"),
    ("evalformula-comparisons", "(x<2)+(x<=2)*10+(x>2)*100+(x>=2)*1000+(x==2)*10000+(x!=2)*100000", "{x:{1, 2, 3}}"),
    ("evalformula-logic", "(x>1)&(x<3)|(x==0)", "{x:{0, 1, 2, 3}}"),
    ("evalformula-not", "!x", "{x:{0, 1, 2}}"),
    ("evalformula-not-comparison", "!(x>1)", "{x:{0, 2}}"),
    ("evalformula-numbers", "1e3+.5+2.5E-1", "{}"),
    ("evalformula-statements", "r=hypot(x,y);r*2", "{x:3, y:4}"),
    ("evalformula-statements-return", "r=x+1\nr*r", "{x:2}"),
    ("evalformula-comment", "x+1//a comment\n", "{x:2}"),
    ("evalformula-comment-line", "//first\nx*3", "{x:2}"),
    ("evalformula-spaces", " x  +   1 ", "{x:2}"),
    ("evalformula-matrix", "x*2", f"{{x:{M23}}}"),
    ("evalformula-text-number", "x+1", '{x:"2"}'),
    ("evalformula-missing", "x+1", "{x:{1, missing value}}"),
    ("evalformula-division-by-zero", "1/x", "{x:{1, 0, -1}}"),
    ("evalformula-division-by-zero-number", "1/0", "{}"),
    ("evalformula-nan", "sqrt(x)", "{x:{4, -1}}"),
    ("evalformula-mismatch", "x+y", "{x:{1, 2}, y:{1, 2, 3}}"),
    ("evalformula-number-array", "x+y", "{x:1, y:(createarray 3)}"),
    ("evalformula-unknown-variable", "x+z", "{x:1}"),
    ("evalformula-unknown-function", "foo(x)", "{x:1}"),
    ("evalformula-syntax-error", "x+*2", "{x:1}"),
    ("evalformula-unbalanced", "(x+1", "{x:1}"),
    ("evalformula-empty", "", "{}"),
    ("evalformula-pi", "pi", "{}"),
    ("evalformula-e", "e", "{}"),
    ("evalformula-case", "X+x", "{x:1}"),
    ("evalformula-reserved-name", "count+1", '{"count", 2}'),
    ("evalformula-variable-name-digits", "x1+x_2", '{"x1", 1, "x_2", 2}'),
    ("evalformula-assign-variable", "x=x+1;x", "{x:1}"),
    ("evalformula-odd-list", "x", '{"x"}'),
    ("evalformula-no-with", "1+1", None),
]:
    case(name, f"evalformula {json.dumps(formula)}" + ("" if variables is None else f" with {variables}"))
case("evalformula-formulas", 'evalformula {"x+1", "x*2"} with {x:{1, 2}}')
case("evalformula-formulas-numbers", 'evalformula {"x+1", "x*2"} with {x:1}')
case("evalformula-as-matrix", f'evalformula "x+1" with {{x:{M23}}} as matrix')
case("evalformula-as-matrix-two", f'evalformula "x+y" with {{x:{M23}, y:{M23}}} as matrix')
case("evalformula-as-matrix-no-matrix", 'evalformula "x+1" with {x:{1, 2}} as matrix')
case("evalformula-as-array", f'evalformula "x+1" with {{x:{M23}}} as array of real')
# Every function, at 200 random points from -10 to 10 (and a range of its own where it needs one).
for function, arguments in [
    ("cbrt", "x"), ("sqr", "x"), ("sqrt", "x"), ("hypot", "x,y"), ("pow", "x,y"), ("sign", "x"),
    ("abs", "x"), ("ceil", "x"), ("floor", "x"), ("trunc", "x"), ("max", "x,y"), ("min", "x,y"),
    ("mod", "x,y"), ("remainder", "x,y"), ("isnan", "sqrt(x)"), ("replacenan", "sqrt(x),y"),
    ("ln", "x"), ("log", "x"), ("log10", "x"), ("log1p", "x"), ("exp", "x"), ("expm1", "x"),
    ("cos", "x"), ("sin", "x"), ("tan", "x"), ("acos", "x/10"), ("asin", "x/10"), ("atan", "x"), ("atan2", "y,x"),
    ("cosh", "x"), ("sinh", "x"), ("tanh", "x"), ("acosh", "x"), ("asinh", "x"), ("atanh", "x/10"),
    ("erf", "x"), ("erfc", "x"), ("gamma", "x"), ("lgamma", "x"),
    ("j0", "x"), ("j1", "x"), ("jn", "3,x"), ("y0", "x"), ("y1", "x"), ("yn", "2,x"),
    ("EllipticE", "x/10"), ("EllipticK", "x/10"), ("IncEllipticE", "x,y/10"), ("IncEllipticF", "x,y/10"),
    ("EllipticP", "x/10,y/20"), ("IncEllipticP", "x,y/10,x/20"),
    ("lambertW0", "x"), ("lambertWm1", "-abs(x)/30"),
]:
    case(f"evalformula-fn-{function.lower()}", f'evalformula "{function}({arguments})" with {{x:{X}, y:{R(200, 8, -10, 10)}}}')
for name, formula in [
    ("evalformula-norm", "norm(x)"), ("evalformula-norm2", "norm2(x)"), ("evalformula-sum", "sum(x)"),
    ("evalformula-runsum", "runsum(x)"), ("evalformula-diff", "diff(x)"), ("evalformula-int", "int(x,y)"),
    ("evalformula-count", "count(x)"), ("evalformula-rest", "rest(x)"), ("evalformula-butlast", "butlast(x)"),
    ("evalformula-concat", "concat(x,y)"), ("evalformula-doc-norm", "norm(cos(x))/sqrt(count(x))"),
    ("evalformula-sum-number", "sum(2)"), ("evalformula-count-number", "count(2)"), ("evalformula-diff-one", "diff(z)"),
    ("evalformula-int-number", "int(2,y)"),
]:
    case(name, f'evalformula "{formula}" with {{x:{{1, 2, 4, 8}}, y:{{0, 1, 3, 6}}, z:{{5}}}}')

# More of evalformula's language and functions, from probing SatimageOSAX (precedence, unary operators, tokens,
# errors).
for name, script in [
    ("evalformula-probe-001", "evalformula \"2*3^2\" with {}"),
    ("evalformula-probe-002", "evalformula \"1+2^2\" with {}"),
    ("evalformula-probe-003", "evalformula \"2^2*3\" with {}"),
    ("evalformula-probe-004", "evalformula \"-2^2\" with {}"),
    ("evalformula-probe-005", "evalformula \"2^-1\" with {}"),
    ("evalformula-probe-006", "evalformula \"1+-2\" with {}"),
    ("evalformula-probe-007", "evalformula \"(-2)*3\" with {}"),
    ("evalformula-probe-008", "evalformula \"1<2+1\" with {}"),
    ("evalformula-probe-009", "evalformula \"!0+1\" with {}"),
    ("evalformula-probe-010", "evalformula \"1&0|1\" with {}"),
    ("evalformula-probe-011", "evalformula \"0|1&0\" with {}"),
    ("evalformula-probe-012", "evalformula \"2>1&3>4\" with {}"),
    ("evalformula-probe-013", "evalformula \"1==1+0\" with {}"),
    ("evalformula-probe-014", "evalformula \"2*-3\" with {}"),
    ("evalformula-probe-015", "evalformula \"-(2)\" with {}"),
    ("evalformula-probe-016", "evalformula \"- 2\" with {}"),
    ("evalformula-probe-017", "evalformula \"3-2-1\" with {}"),
    ("evalformula-probe-018", "evalformula \"8/2/2\" with {}"),
    ("evalformula-probe-019", "evalformula \"2^0.5\" with {}"),
    ("evalformula-probe-020", "evalformula \"!1==0\" with {}"),
    ("evalformula-probe-021", "evalformula \"int(f,x)\" with {f:{1, 1, 1}, x:{0, 1, 2}}"),
    ("evalformula-probe-022", "evalformula \"int(f,x)\" with {f:{0, 1, 2}, x:{1, 1, 1}}"),
    ("evalformula-probe-023", "evalformula \"int(x,x)\" with {x:{0, 1, 3}}"),
    ("evalformula-probe-024", "evalformula \"max(x)\" with {x:{3, 1, 2}}"),
    ("evalformula-probe-025", "evalformula \"min(x,2)\" with {x:{3, 1, 2}}"),
    ("evalformula-probe-026", "evalformula \"max(x,y)\" with {x:{3, 1}, y:{2, 5}}"),
    ("evalformula-probe-027", "evalformula \"sign(x)\" with {x:{-2, 0, 3}}"),
    ("evalformula-probe-028", "evalformula \"mod(x,3)\" with {x:{-7, 7, 7.5}}"),
    ("evalformula-probe-029", "evalformula \"remainder(x,3)\" with {x:{-7, 7, 8}}"),
    ("evalformula-probe-030", "evalformula \"isnan(x)\" with {x:{1, missing value}}"),
    ("evalformula-probe-031", "evalformula \"replacenan(x,9)\" with {x:{1, missing value}}"),
    ("evalformula-probe-032", "evalformula \"jn(2,x)\" with {x:{1, 2}}"),
    ("evalformula-probe-033", "evalformula \"yn(2,x)\" with {x:{1, 2}}"),
    ("evalformula-probe-034", "evalformula \"EllipticK(x)\" with {x:{0, 0.5}}"),
    ("evalformula-probe-035", "evalformula \"EllipticE(x)\" with {x:{0, 0.5}}"),
    ("evalformula-probe-036", "evalformula \"IncEllipticF(x,k)\" with {x:{0.5}, k:{0.5}}"),
    ("evalformula-probe-037", "evalformula \"EllipticP(n,k)\" with {n:{0.25}, k:{0.5}}"),
    ("evalformula-probe-038", "evalformula \"lambertW0(x)\" with {x:{1, -0.3}}"),
    ("evalformula-probe-039", "evalformula \"lambertWm1(x)\" with {x:{-0.3, -0.1}}"),
    ("evalformula-probe-040", "evalformula \"sum(x)\" with {x:{1, missing value, 2}}"),
    ("evalformula-probe-041", "evalformula \"count(x)\" with {x:{1, missing value, 2}}"),
    ("evalformula-probe-042", "evalformula \"x\" with {x:{}}"),
    ("evalformula-probe-043", "evalformula \"diff(x)\" with {x:3}"),
    ("evalformula-probe-044", "evalformula \"rest(x)\" with {x:3}"),
    ("evalformula-probe-045", "evalformula \"concat(x,2)\" with {x:{1}}"),
    ("evalformula-probe-046", "evalformula \"runsum(2)\" with {}"),
    ("evalformula-probe-047", "evalformula \"a=1\" with {}"),
    ("evalformula-probe-048", "evalformula \"x;\" with {x:1}"),
    ("evalformula-probe-049", "evalformula \"x\\n\\n\" with {x:1}"),
    ("evalformula-probe-050", "evalformula \"2x\" with {x:3}"),
    ("evalformula-probe-051", "evalformula \"x(2)\" with {x:3}"),
    ("evalformula-probe-052", "evalformula \"sin x\" with {x:3}"),
    ("evalformula-probe-053", "evalformula \"1.5e\" with {}"),
    ("evalformula-probe-054", "evalformula \"1..2\" with {}"),
    ("evalformula-probe-055", "evalformula \"$\" with {}"),
    ("evalformula-probe-056", "evalformula \"cos()\" with {}"),
    ("evalformula-probe-057", "evalformula \"atan2(1)\" with {}"),
    ("evalformula-probe-058", "evalformula \"hypot(1,2,3)\" with {}"),
    ("evalformula-probe-059", "evalformula \"x+1\" with {x:true}"),
    ("evalformula-probe-060", "evalformula \"x+1\" with {x:\"abc\"}"),
    ("evalformula-probe-061", "evalformula \"x+1\" with {x:{1, \"abc\"}}"),
    ("evalformula-probe-062", "evalformula \"-2+3\" with {}"),
    ("evalformula-probe-063", "evalformula \"-2*3+1\" with {}"),
    ("evalformula-probe-064", "evalformula \"-x+1\" with {x:{1, 2}}"),
    ("evalformula-probe-065", "evalformula \"!1+1\" with {}"),
    ("evalformula-probe-066", "evalformula \"!x==1\" with {x:{0, 1}}"),
    ("evalformula-probe-067", "evalformula \"-(2)^2\" with {}"),
    ("evalformula-probe-068", "evalformula \"1-(-2)\" with {}"),
    ("evalformula-probe-069", "evalformula \"x=-1\" with {}"),
    ("evalformula-probe-070", "evalformula \"abs(-2)\" with {}"),
    ("evalformula-probe-071", "evalformula \"max(-1,2)\" with {}"),
    ("evalformula-probe-072", "evalformula \"-2<1\" with {}"),
    ("evalformula-probe-073", "evalformula \"-1&0\" with {}"),
    ("evalformula-probe-074", "evalformula \"!-1\" with {}"),
    ("evalformula-probe-075", "evalformula \"-!1\" with {}"),
    ("evalformula-probe-076", "evalformula \"--2\" with {}"),
    ("evalformula-probe-077", "evalformula \"+2\" with {}"),
    ("evalformula-probe-078", "evalformula \"2^3^2^0\" with {}"),
    ("evalformula-probe-079", "evalformula \"1|0&0\" with {}"),
    ("evalformula-probe-080", "evalformula \"2>1>0\" with {}"),
    ("evalformula-probe-081", "evalformula \"x*(-1)\" with {x:2}"),
    ("evalformula-probe-082", "evalformula \"(x)\" with {x:2}"),
    ("evalformula-probe-083", "evalformula \"((x))+(1)\" with {x:2}"),
    ("evalformula-probe-084", "evalformula \"x;;y\" with {x:1, y:2}"),
    ("evalformula-probe-085", "evalformula \";x\" with {x:1}"),
    ("evalformula-probe-086", "evalformula \"x=1;\" with {}"),
    ("evalformula-probe-087", "evalformula \"1 2\" with {}"),
    ("evalformula-probe-088", "evalformula \"x y\" with {x:1, y:2}"),
    ("evalformula-probe-089", "evalformula \"1e+2\" with {}"),
    ("evalformula-probe-090", "evalformula \"1E2\" with {}"),
    ("evalformula-probe-091", "evalformula \"0x10\" with {}"),
    ("evalformula-probe-092", "evalformula \"1.\" with {}"),
    ("evalformula-probe-093", "evalformula \".\" with {}"),
    ("evalformula-probe-094", "evalformula \"sqrt(4\" with {}"),
    ("evalformula-probe-095", "evalformula \"sqrt 4)\" with {}"),
    ("evalformula-probe-096", "evalformula \")\" with {}"),
    ("evalformula-probe-097", "evalformula \"x=\" with {}"),
    ("evalformula-probe-098", "evalformula \"=1\" with {}"),
    ("evalformula-probe-099", "evalformula \"PI\" with {}"),
    ("evalformula-probe-100", "evalformula \"Pi*2\" with {}"),
    ("evalformula-probe-101", "evalformula \"pi=3;pi\" with {}"),
    ("evalformula-probe-102", "evalformula \"cos=1;cos\" with {}"),
    ("evalformula-probe-103", "evalformula \"COS(0)\" with {}"),
    ("evalformula-probe-104", "evalformula \"Sqrt(4)\" with {}"),
    ("evalformula-probe-105", "evalformula \"x#1\" with {x:1}"),
    ("evalformula-probe-106", "evalformula \"x//c\\ny\" with {x:1, y:2}"),
    ("evalformula-probe-107", "evalformula \"x // c\" with {x:1}"),
    ("evalformula-probe-108", "evalformula \"/*c*/x\" with {x:1}"),
    ("evalformula-probe-109", "evalformula \"x\\ry\" with {x:1, y:2}"),
    ("evalformula-probe-110", "evalformula \"x\\r\\ny\" with {x:1, y:2}"),
    ("evalformula-probe-111", "evalformula \"1/x\" with {x:0}"),
    ("evalformula-probe-112", "evalformula \"0/0\" with {}"),
    ("evalformula-probe-113", "evalformula \"x^0\" with {x:0}"),
]:
    case(name, script)

# evalpolynomial, roots of, composepolynomial, pade approximant
P = "(composepolynomial {1, 1} with {0, 2})"   # 1 + 2x, as a polynomial
for name, script in [
    ("evalpolynomial-number", "evalpolynomial {1, 2, 3} at 2"),
    ("evalpolynomial-array", f"evalpolynomial {{1, 2, 3}} at {A5}"),
    ("evalpolynomial-list", "evalpolynomial {1, 2, 3} at {0, 1, -1}"),
    ("evalpolynomial-polynomial", f"evalpolynomial {P} at 3"),
    ("evalpolynomial-array-coefficients", "evalpolynomial (createarray 3 range {1, 3}) at 2"),
    ("evalpolynomial-constant", "evalpolynomial {5} at 9"),
    ("evalpolynomial-empty", "evalpolynomial {} at 2"),
    ("evalpolynomial-number-coefficients", "evalpolynomial 5 at 2"),
    ("evalpolynomial-text", 'evalpolynomial {"1", "2"} at "3"'),
    ("evalpolynomial-no-at", "evalpolynomial {1, 2}"),
    ("evalpolynomial-doc", f"evalpolynomial {{1, 0.5, 0.25, -1}} at {R(20, 4, -2, 2)}"),
    ("roots-quadratic", "roots of {-2, 0, 1}"),
    ("roots-linear", "roots of {-3, 2}"),
    ("roots-constant", "roots of {5}"),
    ("roots-cubic", "roots of {-6, 11, -6, 1}"),
    ("roots-repeated", "roots of {1, -2, 1}"),
    ("roots-complex-false", "roots of {1, 0, 1}"),
    ("roots-complex", "roots of {1, 0, 1} with complex"),
    ("roots-mixed", "roots of {-1, 0, 0, 1} with complex"),
    ("roots-mixed-real-only", "roots of {-1, 0, 0, 1}"),
    ("roots-degree-five", "roots of {1, -3, 0.5, 2, -1, 0.25} with complex"),
    ("roots-leading-zero", "roots of {-2, 0, 1, 0}"),
    ("roots-zero-root", "roots of {0, -1, 1}"),
    ("roots-array", "roots of (createarray 3 range {-1, 1})"),
    ("roots-polynomial", f"roots of {P}"),
    ("roots-empty", "roots of {}"),
    ("roots-zero", "roots of {0, 0}"),
    ("composepolynomial-doc", "composepolynomial {1, 1} with {0, 2}"),
    ("composepolynomial-square", "composepolynomial {0, 0, 1} with {1, 1}"),
    ("composepolynomial-cubic", "composepolynomial {1, -2, 0, 3} with {2, 1, 1}"),
    ("composepolynomial-constant", "composepolynomial {5} with {1, 2}"),
    ("composepolynomial-with-constant", "composepolynomial {1, 2, 3} with {2}"),
    ("composepolynomial-arrays", "composepolynomial (createarray 3) with (createarray 2 range {1, 1})"),
    ("composepolynomial-empty", "composepolynomial {} with {1}"),
    ("composepolynomial-no-with", "composepolynomial {1, 2}"),
    ("pade-doc", "pade approximant {1, 1, 0.5, 0.16666666666666666} numerator 1 denominator 1"),
    ("pade-exp", "pade approximant {1, 1, 0.5, 0.16666666666666666, 0.041666666666666664} numerator 2 denominator 2"),
    ("pade-numerator-only", "pade approximant {1, 2, 3} numerator 2 denominator 0"),
    ("pade-denominator-only", "pade approximant {1, 1, 1} numerator 0 denominator 2"),
    ("pade-too-few", "pade approximant {1, 1} numerator 2 denominator 2"),
    ("pade-singular", "pade approximant {1, 0, 0, 0} numerator 1 denominator 2"),
    ("pade-synonym", "pade {1, 1, 0.5} numerator 1 denominator 1"),
    ("pade-no-degrees", "pade approximant {1, 1, 0.5}"),
]:
    case(name, script)

# fitpolynomial, fitrational
XS, YS = "{0, 1, 2, 3}", "{1, 3, 7, 13}"
NX, NY = R(30, 5, 0, 5), R(30, 6, -1, 1)
for name, script in [
    ("fitpolynomial-doc", f"fitpolynomial {{{XS}, {YS}}} degree 2 number formatting \"%.3g\""),
    ("fitpolynomial-exact", f"fitpolynomial {{{XS}, {YS}}} degree 2"),
    ("fitpolynomial-line", f"fitpolynomial {{{XS}, {YS}}} degree 1 number formatting \"%.4f\""),
    ("fitpolynomial-degree-zero", f"fitpolynomial {{{XS}, {YS}}} degree 0"),
    ("fitpolynomial-degree-too-high", f"fitpolynomial {{{XS}, {YS}}} degree 4"),
    ("fitpolynomial-degree-points", f"fitpolynomial {{{XS}, {YS}}} degree 3"),
    ("fitpolynomial-noisy", f"fitpolynomial {{{NX}, {NY}}} degree 3 number formatting \"%.6g\""),
    ("fitpolynomial-arrays", "fitpolynomial {createarray 5, createarray 5 range {1, 9}} degree 1"),
    ("fitpolynomial-constraint", f"fitpolynomial {{{NX}, {NY}}} degree 2 constraints {{{{1, 0, 0, 0}}}}"),
    ("fitpolynomial-constraints", f"fitpolynomial {{{NX}, {NY}}} degree 3 constraints {{{{1, 0, 0, 0, 1}}, {{1, 1, 1, 1, 0}}}}"),
    ("fitpolynomial-constraint-wrong-size", f"fitpolynomial {{{NX}, {NY}}} degree 2 constraints {{{{1, 0}}}}"),
    ("fitpolynomial-formatting-signs", "fitpolynomial {{0, 1, 2}, {-1, -3, -7}} degree 2 number formatting \"%g\""),
    ("fitpolynomial-formatting-plain", f"fitpolynomial {{{XS}, {YS}}} degree 2 number formatting \"\""),
    ("fitpolynomial-mismatch", "fitpolynomial {{0, 1, 2}, {1, 2}} degree 1"),
    ("fitpolynomial-one-array", "fitpolynomial {{0, 1, 2}} degree 1"),
    ("fitpolynomial-no-degree", f"fitpolynomial {{{XS}, {YS}}}"),
    ("fitpolynomial-missing", "fitpolynomial {{0, 1, 2, 3}, {1, missing value, 7, 13}} degree 1"),
    ("fitrational-exact", "fitrational {{0, 1, 2, 3, 4}, {1, 0.5, 0.333333333333, 0.25, 0.2}} numerator 0 denominator 1"),
    ("fitrational-noisy", f"fitrational {{{NX}, {NY}}} numerator 1 denominator 1 number formatting \"%.4g\""),
    ("fitrational-two-two", f"fitrational {{{NX}, {NY}}} numerator 2 denominator 2"),
    ("fitrational-polynomial", f"fitrational {{{XS}, {YS}}} numerator 2 denominator 0 number formatting \"%.3g\""),
    ("fitrational-too-few", "fitrational {{0, 1}, {1, 2}} numerator 2 denominator 2"),
    ("fitrational-no-degrees", f"fitrational {{{XS}, {YS}}}"),
]:
    case(name, script)

# read binary, write binary: recorded with Files/cases.json (below), which writes in $TMP.
files, file_names = [], set()
def file_case(name, script):
    assert name.lower() not in file_names, name
    file_names.add(name.lower())
    files.append({"name": name, "script": script})
F = 'POSIX file "$TMP/{0}.bin"'
for kind in ("real", "small real", "integer", "small integer", "byte"):
    label = kind.replace(" ", "-")
    path = F.format(label)
    file_case(f"binary-{label}", f'write binary {path} with data {{1, -2.5, 300, 70000}} as {kind}\nread binary {path} as {kind}')
    file_case(f"binary-{label}-big-endian", f'write binary {F.format(label + "-big")} with data {{1, -2, 3}} as {kind} with big endian\nread binary {F.format(label + "-big")} as {kind} with big endian\nread binary {F.format(label + "-big")} as {kind} without big endian')
for name, script in [
    ("binary-default-type", f'write binary {F.format("default")} with data {{1.5, 2.5}}\nread binary {F.format("default")} as real'),
    ("binary-append", f'write binary {F.format("append")} with data {{1, 2}} as small integer\nwrite binary {F.format("append")} with data {{3}} as small integer\nread binary {F.format("append")} as small integer'),
    ("binary-starting-at", f'write binary {F.format("start")} with data {{1, 2, 3}} as byte\nwrite binary {F.format("start")} with data {{9}} as byte starting at 1\nread binary {F.format("start")} as byte'),
    ("binary-starting-at-beyond", f'write binary {F.format("beyond")} with data {{1}} as byte\nwrite binary {F.format("beyond")} with data {{9}} as byte starting at 3\nread binary {F.format("beyond")} as byte'),
    ("binary-array", f'write binary {F.format("array")} with data (createarray 5) as integer\nread binary {F.format("array")} as integer'),
    ("binary-skip", f'write binary {F.format("skip")} with data {{1, 2, 3, 4}} as small integer\nread binary {F.format("skip")} as small integer skip 2'),
    ("binary-length", f'write binary {F.format("length")} with data {{1, 2, 3, 4}} as small integer\nread binary {F.format("length")} as small integer length 2'),
    ("binary-step", f'write binary {F.format("step")} with data {{1, 2, 3, 4, 5, 6}} as small integer\nread binary {F.format("step")} as small integer step 4'),
    ("binary-blocks", f'write binary {F.format("blocks")} with data {{1, 2, 3, 4, 5, 6, 7, 8}} as byte\nread binary {F.format("blocks")} as byte step 4 blocksize 2'),
    ("binary-blocks-length", f'write binary {F.format("blength")} with data {{1, 2, 3, 4, 5, 6, 7, 8}} as byte\nread binary {F.format("blength")} as byte step 3 blocksize 2 length 2'),
    ("binary-unsigned", f'write binary {F.format("unsigned")} with data {{-1, -2}} as small integer\nread binary {F.format("unsigned")} as small integer without signed\nread binary {F.format("unsigned")} as byte without signed\nread binary {F.format("unsigned")} as byte with signed'),
    ("binary-rounding", f'write binary {F.format("round")} with data {{1.5, 2.5, -1.5, 1.4}} as integer\nread binary {F.format("round")} as integer'),
    ("binary-out-of-range", f'write binary {F.format("range")} with data {{300, -129, 1.0E+10}} as byte\nread binary {F.format("range")} as byte'),
    ("binary-nan", f'write binary {F.format("nan")} with data (divlist {{0, 1}} with {{0, 1}}) as integer\nread binary {F.format("nan")} as integer'),
    ("binary-partial", f'write binary {F.format("partial")} with data {{1, 2, 3}} as byte\nread binary {F.format("partial")} as small integer'),
    ("binary-read-missing", 'read binary POSIX file "$TMP/no-such.bin" as real'),
    ("binary-read-empty", f'write binary {F.format("empty")} with data {{}} as real\nread binary {F.format("empty")} as real'),
    ("binary-no-as", f'write binary {F.format("noas")} with data {{1}}\nread binary {F.format("noas")}'),
    ("binary-bad-type", f'write binary {F.format("bad")} with data {{1}} as text'),
    ("binary-path-text", f'write binary "$TMP/text-path.bin" with data {{1, 2}} as byte\nread binary "$TMP/text-path.bin" as byte'),
    ("binary-no-data", f'write binary {F.format("nodata")}'),
]:
    file_case(name, script)

# Where SatimageOSAX is broken, MTC_OSAX follows the dictionary; these cases are recorded from MTC_OSAX into
# ../ArraysFixes instead.
MTC_OSAX_FIXES = {
    "randomarray-seed-large": "Satimage ignored a seed beyond the 32-bit range (the numbers weren't repeatable)",
    "removemissingvalue-list": "Satimage gave -1708 (not handled)",
    "removemissingvalue-array": "Satimage gave -1708 (not handled)",
    "removemissingvalue-none": "Satimage gave -1708 (not handled)",
    "extractarray-as-list-of-integer-huge": "Satimage wrapped a number beyond 32 bits (1.0E+10 became 1410065408); -1700, as AppleScript's as integer",
    "resamplematrix-blocksize-zero": "Satimage returned nothing; -50",
    "composepolynomial-empty": "Satimage returned nothing; the zero polynomial",
    "evalformula-fn-sqr": "Satimage didn't know sqr (error 5), which its dictionary lists",
    "evalformula-comment": "Satimage gave a syntax error (16) for a // comment after an expression",
    "divlist-polynomial-number": "Satimage refused to divide a polynomial by a number (-50), which its dictionary lists",
    "histogram-minimum": "Satimage also counted numbers up to an interval below the minimum in the first interval",
    "histogram-range-inside": "Satimage also counted numbers up to an interval below the minimum in the first interval",
    "filter-not-reduced": "Satimage put some border values in the wrong places (the identity filter changed the matrix)",
    "filter-not-reduced-blur": "Satimage put some border values in the wrong places",
    "filter-small": "Satimage gave -108 (out of memory) for a matrix too small to reduce; -50",
    "evalformula-int": "Satimage's int(f,x) computed the integral of x by f, not of f by x as its dictionary says",
    "evalformula-probe-021": "Satimage's int(f,x) computed the integral of x by f, not of f by x as its dictionary says",
    "evalformula-probe-022": "Satimage's int(f,x) computed the integral of x by f, not of f by x as its dictionary says",
    "evalformula-probe-107": "Satimage gave a syntax error (16) for a // comment with a space in it",
}
assert MTC_OSAX_FIXES.keys() <= names
os.makedirs("../ArraysFixes", exist_ok=True)
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../ArraysFixes/cases.json", "w"), indent=1, ensure_ascii=False)
FILE_FIXES = {
    "binary-path-text": "Satimage gave error 1 for a path as text; the file commands take one",
}
assert FILE_FIXES.keys() <= file_names
os.makedirs("Files", exist_ok=True)
os.makedirs("../ArraysFixes/Files", exist_ok=True)
json.dump([c for c in files if c["name"] not in FILE_FIXES], open("Files/cases.json", "w"), indent=1, ensure_ascii=False)
json.dump([c for c in files if c["name"] in FILE_FIXES], open("../ArraysFixes/Files/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes,", len(files) - len(FILE_FIXES), "file cases,", len(FILE_FIXES), "file fixes")
