# Generates cases.json for the Mathematical Functions suite, recorded from SatimageOSAX. Run: python3 generate.py
# Each function gets typical values, edges, other kinds of input (integer, text, list, array) and a list of random
# values in its domain (fixed by the seed below, so the cases don't change between runs).
import json, math, os, random

cases, names = [], set()
def case(name, script):
    assert name.lower() not in names, name
    names.add(name.lower())
    cases.append({"name": name, "script": script})

def real(x):
    return repr(float(x)).replace("e", "E") if abs(x) >= 1e16 or (x != 0 and abs(x) < 1e-4) else repr(float(x))

rng = random.Random(20260928)
# name: (typical values, edge values, random domain)
FUNCTIONS = {
    "abs": ([-3, 2.5, 0], [-0.0, -1e308], (-1e6, 1e6)),
    "sqr": ([3, -2.5, 0], [1e200, 1e-200], (-1e3, 1e3)),
    "sqrt": ([4, 2, 0], [-1, 1e-300, 1e308], (0, 1e6)),
    "ceil": ([2.5, -2.5, 3], [0.0000001, -0.9, 1e17], (-1e4, 1e4)),
    "floor": ([2.5, -2.5, 3], [0.9999999, -0.0000001, 1e17], (-1e4, 1e4)),
    "trunc": ([2.7, -2.7, 3], [-0.5, 0.5, 1e17], (-1e4, 1e4)),
    "exp": ([1, 0, -1], [709, 710, -745, -746], (-50, 50)),
    "ln": ([math.e, 1, 10], [0, -1, 1e-300], (1e-6, 1e6)),
    "log10": ([100, 1, 2], [0, -1, 1e-300], (1e-6, 1e6)),
    "sin": ([0, 1, math.pi / 2], [1e10, -1e-10, 1e300], (-10, 10)),
    "cos": ([0, 1, math.pi], [1e10, -1e-10, 1e300], (-10, 10)),
    "tan": ([0, 1, math.pi / 4], [math.pi / 2, 1e10, -1e-10], (-1.5, 1.5)),
    "asin": ([0, 0.5, 1], [-1, 1.0000001, 2], (-1, 1)),
    "acos": ([0, 0.5, 1], [-1, 1.0000001, 2], (-1, 1)),
    "atan": ([0, 1, -1], [1e300, -1e300, 1e-10], (-100, 100)),
    "sinh": ([0, 1, -1], [710, 711, -711], (-20, 20)),
    "cosh": ([0, 1, -1], [710, 711, -711], (-20, 20)),
    "tanh": ([0, 1, -1], [20, -20, 1e-10], (-5, 5)),
    "asinh": ([0, 1, -1], [1e300, -1e300, 1e-10], (-100, 100)),
    "acosh": ([1, 2, 10], [0.5, -1, 1e300], (1, 100)),
    "atanh": ([0, 0.5, -0.5], [1, -1, 2], (-0.99, 0.99)),
    "erf": ([0, 1, -1], [6, -6, 1e-10], (-4, 4)),
    "erfc": ([0, 1, -1], [27, 28, -6], (-4, 10)),
    "gamma": ([1, 5, 0.5], [0, -1, -1.5, 171, 172], (0.1, 30)),
    "lgamma": ([1, 5, 0.5], [0, -1, -1.5, 1e300], (0.1, 100)),
}
for name, (typical, edges, (low, high)) in FUNCTIONS.items():
    for index, value in enumerate(typical):
        case(f"{name}-{index + 1}", f"{name} {real(value) if isinstance(value, float) else value}")
    for index, value in enumerate(edges):
        case(f"{name}-edge-{index + 1}", f"{name} {real(value) if isinstance(value, float) else value}")
    values = [rng.uniform(low, high) for _ in range(20)]
    case(f"{name}-random", f"{name} {{{', '.join(real(v) for v in values)}}}")
    case(f"{name}-array", f"{name} (createarray 5 range {{{real(low / 4)}, {real(high / 4)}}})")

# Other kinds of input, on a few functions.
case("abs-integer", "abs -7")
case("sqrt-integer", "sqrt 9")
case("floor-integer-result", "floor 2")
case("abs-text", 'abs "-2.5"')
case("abs-text-comma", 'abs "-2,5"')
case("abs-text-invalid", 'abs "abc"')
case("abs-list", "abs {-1, 2, -3.5}")
case("abs-list-mixed", 'abs {-1, "-2", 3.5}')
case("abs-list-text-invalid", 'abs {-1, "abc"}')
case("abs-empty-list", "abs {}")
case("abs-list-of-lists", "abs {{-1, -2}, {-3}}")
case("abs-missing-value", "abs missing value")
case("abs-list-missing-value", "abs {-1, missing value, 3}")
case("abs-boolean", "abs true")
case("abs-record", "abs {a:1}")
case("abs-no-parameter", "abs")
case("sqrt-list-negative", "sqrt {4, -1, 9}")
case("sqrt-array-negative", "sqrt (createarray 3 range {-1, 1})")
case("ln-list-zero", "ln {1, 0}")
case("cos-array-single", "cos (createarray 1)")
case("sin-date", 'sin (date "Saturday, January 1, 2000 at 12:00:00 AM")')

# atan2 and hypot take a list of two numbers.
for name in ("atan2", "hypot"):
    for index, pair in enumerate([(1, 1), (0, -1), (-1, 0), (3, 4), (0, 0), (-0.0, -1), (1e300, 1e300), (1e-300, 1e-300)]):
        case(f"{name}-{index + 1}", f"{name} {{{real(pair[0]) if isinstance(pair[0], float) else pair[0]}, {real(pair[1]) if isinstance(pair[1], float) else pair[1]}}}")
    pairs = ", ".join("{%s, %s}" % (real(rng.uniform(-100, 100)), real(rng.uniform(-100, 100))) for _ in range(10))
    case(f"{name}-list-of-pairs", f"{name} {{{pairs}}}")
    case(f"{name}-one-item", f"{name} {{1}}")
    case(f"{name}-three-items", f"{name} {{1, 2, 3}}")
    case(f"{name}-number", f"{name} 1")
    case(f"{name}-empty", f"{name} {{}}")
    case(f"{name}-text", f'{name} {{"3", "4"}}')
    case(f"{name}-array", f"{name} (createarray 2 range {{3, 4}})")
    case(f"{name}-array-four", f"{name} (createarray 4 range {{1, 4}})")

MTC_OSAX_FIXES = {}
assert MTC_OSAX_FIXES.keys() <= names
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
if MTC_OSAX_FIXES:
    os.makedirs("../MathFunctionsFixes", exist_ok=True)
    json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../MathFunctionsFixes/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
