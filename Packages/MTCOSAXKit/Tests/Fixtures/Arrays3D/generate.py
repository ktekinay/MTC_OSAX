# Generates cases.json for Satimage's "3D array handling" suite (Implemented/PLAN-3DArrays.md), recorded from
# SatimageOSAX, and ../Arrays3DFixes/cases.json for what MTC_OSAX does where Satimage is broken (recorded from
# MTC_OSAX). Each case closes the arrays it opens, an error included (`try`), so `list3D` sees only the case's own.
# References are a counter in the app: replays compare them as opaque, and default names are marked by mark_names.py.
# Run: python3 generate.py
import json, os

os.chdir(os.path.dirname(os.path.abspath(__file__)))
cases, fixes, names = [], [], set()
def case(name, *lines, fix=False):
    assert name.lower() not in names, name
    names.add(name.lower())
    (fixes if fix else cases).append({"name": name, "script": "\n".join(lines)})

def array(values):
    return "(extractarray {" + ", ".join(repr(v) if isinstance(v, float) else str(v) for v in values) + "} for -1)"

# A 3×3×3 field: 1 at the center, 0 elsewhere (offset ix + nx*iy + nx*ny*iz).
CENTER = array([1 if i == 13 else 0 for i in range(27)])
ONES = "(createarray 27 range {1, 1})"
ZEROS = "(createarray 27 range {0, 0})"
OPEN = 'set r to open3D "cube" dimensions {3, 3, 3} field ' + CENTER
def closing(*lines):
    """The lines, then close3D r, even if one fails."""
    return ["try", *("\t" + line for line in lines), "on error errorText number n", "\tclose3D r", "\terror errorText number n", "end try", "close3D r"]

# The store: open, info, contents, names, references.
case("open3D-info", OPEN, *closing("info3D r"))
case("open3D-info-by-name", OPEN, *closing('info3D "cube"'))
case("open3D-scales", 'set r to open3D "scaled" dimensions {createarray 3 range {10, 20}, 3, {0, 1, 4}} field ' + CENTER, *closing("info3D r"))
case("open3D-scales-uneven", 'set r to open3D "uneven" dimensions {{0, 0.5, 2}, {-1, 1}, 1} field (createarray 6)', *closing("info3D r"))
case("open3D-real-dimension", 'set r to open3D "real" dimensions {2.5, 2, 2} field (createarray 8)', *closing("info3D r"))
case("open3D-vector-field", 'set r to open3D "flow" dimensions {3, 3, 3} field {' + ONES + ", (randomarray 27 range {-1, 1} seed 3), (createarray 27)}", *closing("info3D r"))
# SatimageOSAX's minimum and maximum were garbage (8.3e-315) when the first number was missing.
case("open3D-missing-values", 'set r to open3D "gaps" dimensions {2, 2, 1} field (divlist (createarray 4) with {0, 1, 0, 1})', *closing("info3D r", "contents3D r"), fix=True)
case("open3D-one-cell", 'set r to open3D "one" dimensions {1, 1, 1} field (createarray 1 range {5, 5})', *closing("info3D r", "contents3D r"))
case("open3D-precision", 'set r to open3D "tenths" dimensions {3, 1, 1} field ' + array([0.1, 0.2, 1 / 3]), *closing("contents3D r", "info3D r"))
case("open3D-wrong-size", 'open3D "bad" dimensions {2, 2, 2} field (createarray 27)')
case("open3D-two-dimensions", 'open3D "bad" dimensions {3, 9} field (createarray 27)')
case("open3D-four-dimensions", 'open3D "bad" dimensions {3, 3, 3, 1} field (createarray 27)')
case("open3D-two-fields", 'open3D "bad" dimensions {3, 3, 3} field {(createarray 27), (createarray 27)}')
case("open3D-no-field", 'open3D "bad" dimensions {3, 3, 3}')
case("open3D-no-dimensions", 'open3D "bad" field (createarray 27)')
case("open3D-dimension-zero", 'open3D "bad" dimensions {0, 3, 3} field (createarray 1)')
case("open3D-scale-wrong-size", 'open3D "bad" dimensions {createarray 2, 3, 3} field (createarray 27)')
case("contents3D-scalar", OPEN, *closing("contents3D r"))
case("contents3D-vector", 'set r to open3D "flow" dimensions {2, 2, 2} field {(createarray 8), (createarray 8 range {10, 17}), (createarray 8 range {20, 27})}', *closing("contents3D r"))
case("list3D-references", OPEN, 'set s to open3D "second" dimensions {1, 1, 1} field (createarray 1)',
     "try", "\tlist3D", "end try", "close3D s", "close3D r")
case("list3D-names", OPEN, 'set s to open3D "second" dimensions {1, 1, 1} field (createarray 1)', 'set t to open3D "third" dimensions {1, 1, 1} field (createarray 1)',
     "try", "\tlist3D as string", "\tlist3D as text", "end try", "close3D t", "close3D s", "close3D r", "list3D as string")
case("list3D-empty", "list3D", "list3D as string")
case("rename3D", OPEN, *closing('rename3D r into "box"', "list3D as string", 'info3D "box"', 'rename3D "box" into "cube"', 'info3D "cube"'))
case("rename3D-missing-into", OPEN, *closing("rename3D r"))
case("names-repeated", OPEN, 'set s to open3D "cube" dimensions {1, 1, 1} field (createarray 1)',
     "try", '\tinfo3D "cube"', "\tlist3D as string", "end try", "close3D s", 'info3D "cube"', "close3D r")
case("close3D-by-name", OPEN, 'close3D "cube"', "list3D")
case("closed-reference", OPEN, "close3D r", "info3D r")
case("close3D-twice", OPEN, "close3D r", "close3D r")
case("unknown-name", 'info3D "nothing"')
case("close3D-unknown-name", 'close3D "nothing"')
case("info3D-not-a-reference", "info3D {1, 2}")

# extract3D, on a 3×4×5 field whose numbers are their offsets.
OPEN345 = 'set r to open3D "box" dimensions {3, 4, 5} field (createarray 60)'
case("extract3D-blocks", OPEN345, *closing(
    "extract3D r start {1, 1, 1} length {3, 4, 5}", "extract3D r start {2, 3, 4} length {1, 1, 1}",
    "extract3D r start {1, 2, 3} length {2, 2, 2}", "extract3D r start {3, 1, 1} length {1, 4, 1}",
    "extract3D r start {1, 1, 2} length {3, 1, 4}"))
case("extract3D-vector-field", 'set r to open3D "flow" dimensions {2, 2, 2} field {(createarray 8), (createarray 8 range {10, 17}), (createarray 8 range {20, 27})}',
     *closing("extract3D r start {1, 1, 1} length {2, 1, 2}", "extract3D r start {1, 1, 1} length {2, 1, 2} field index 2",
              "extract3D r start {1, 1, 1} length {2, 1, 2} field index 3"))
for name, args in [("past-the-end", "start {3, 4, 5} length {2, 1, 1}"), ("start-zero", "start {0, 1, 1} length {1, 1, 1}"),
                   ("length-zero", "start {1, 1, 1} length {0, 1, 1}"), ("negative-start", "start {-1, 1, 1} length {1, 1, 1}"),
                   ("two-starts", "start {1, 1} length {1, 1, 1}"), ("no-length", "start {1, 1, 1}"),
                   ("field-index-2-of-1", "start {1, 1, 1} length {1, 1, 1} field index 2"),
                   ("field-index-zero", "start {1, 1, 1} length {1, 1, 1} field index 0")]:
    case("extract3D-" + name, OPEN345, *closing("extract3D r " + args))
case("extract3D-field-index-4", 'set r to open3D "flow" dimensions {1, 1, 1} field {(createarray 1), (createarray 1), (createarray 1)}',
     *closing("extract3D r start {1, 1, 1} length {1, 1, 1} field index 4"))

# isosurface: SatimageOSAX's left most of the surface out (in a single cell, only corner 0 alone above or below the
# value made a triangle; a random field got a third of its vertices), so only its errors are kept: 7 for a value
# outside the field's range. The surfaces are MTC_OSAX's: marching cubes, every pattern of a cell's corners above the
# value, with corner values that differ, so each vertex is interpolated at its own place along its edge.
case("isosurface-above", OPEN, *closing("isosurface r at 2"))
case("isosurface-below", OPEN, *closing("isosurface r at -1"))
case("isosurface-vector-field-none", 'set r to open3D "flow" dimensions {3, 3, 3} field {' + ONES + ", " + CENTER + ", " + ZEROS + "}",
     *closing("isosurface r at 0.5"))
case("isosurface-center", OPEN, *closing("isosurface r at 0.5", "isosurface r at 0.25"), fix=True)
case("isosurface-scaled", 'set r to open3D "scaled" dimensions {createarray 3 range {10, 20}, 3, {0, 1, 4}} field ' + CENTER, *closing("isosurface r at 0.5"), fix=True)
case("isosurface-vector-field", 'set r to open3D "flow" dimensions {3, 3, 3} field {' + ONES + ", " + CENTER + ", " + ZEROS + "}",
     *closing("isosurface r at 0.5 field index 2", "isosurface r at 0.5 field index 3"), fix=True)
case("isosurface-at-the-ends", OPEN, *closing("isosurface r at 1", "isosurface r at 0"), fix=True)
def corners(pattern):
    # Above 0.5 where the pattern's bit is set; each corner a little different.
    return [round(0.6 + 0.05 * k if pattern >> k & 1 else 0.4 - 0.04 * k, 2) for k in range(8)]
for first in range(0, 256, 32):
    patterns = ", ".join("{" + ", ".join(map(str, corners(p))) + "}" for p in range(first, first + 32))
    case(f"isosurface-patterns-{first:03}", f"repeat with values in {{{patterns}}}",
         '\tset r to open3D "cell" dimensions {2, 2, 2} field (extractarray (contents of values) for -1)',
         "\ttry", "\t\tisosurface r at 0.5", "\tend try", "\tclose3D r", "end repeat", fix=True)
for seed, (nx, ny, nz) in [(1, (4, 4, 4)), (2, (5, 4, 3)), (3, (3, 5, 4))]:
    count = nx * ny * nz
    case(f"isosurface-random-{seed}", f'set r to open3D "random" dimensions {{{nx}, {ny}, {nz}}} field (randomarray {count} seed {seed})',
         *closing("isosurface r at 0.5", "isosurface r at 0.3"), fix=True)
case("isosurface-random-scaled", 'set r to open3D "random" dimensions {createarray 4 range {-2, 1}, {0, 1, 3, 7}, createarray 3 range {5, 6}} field (randomarray 48 seed 4)',
     *closing("isosurface r at 0.5"), fix=True)

# streamline: SatimageOSAX's never moved (Implemented/PLAN-3DArrays.md); only its error for a scalar field is kept. From
# outside the box it gave error 2000 once and an empty array another time.
FLOW = 'set r to open3D "flow" dimensions {3, 3, 3} field {' + ONES + ", " + ZEROS + ", " + ZEROS + "}"
case("streamline-outside", FLOW, *closing("streamline r starting at {5, 1, 1}"), fix=True)
case("streamline-scalar-field", OPEN, *closing("streamline r starting at {1, 1, 1}"))

# MTC_OSAX's own, where Satimage is broken.
case("streamline-uniform", FLOW, *closing("streamline r starting at {0, 1, 1}", "streamline r starting at {0, 1, 1} resolution 0.25",
                                          "streamline r starting at {2, 1, 1} direction -1"), fix=True)
case("streamline-rotating",
     # (vx, vy) = (-(y - 1), x - 1) on a 5×5×2 grid from 0 to 2: circles about (1, 1).
     'set r to open3D "rotating" dimensions {createarray 5 range {0, 2}, createarray 5 range {0, 2}, 2} field {'
     + array([-(iy / 2 - 1) for iz in range(2) for iy in range(5) for ix in range(5)]) + ", "
     + array([ix / 2 - 1 for iz in range(2) for iy in range(5) for ix in range(5)]) + ", (createarray 50 range {0, 0})}",
     *closing("streamline r starting at {1.5, 1, 0.5} resolution 0.5"), fix=True)
case("open3D-field-as-list", 'set r to open3D "list" dimensions {2, 1, 1} field {1, 2}', *closing("contents3D r", "info3D r"), fix=True)
case("open3D-full-precision", 'set r to open3D "precise" dimensions {3, 1, 1} field ' + array([0.1, 1e300, -1e-300]), *closing("contents3D r", "info3D r"), fix=True)

for folder, entries in [(".", cases), ("../Arrays3DFixes", fixes)]:
    os.makedirs(folder, exist_ok=True)
    json.dump(entries, open(os.path.join(folder, "cases.json"), "w"), indent=1, ensure_ascii=False)
    print(len(entries), "cases in", os.path.normpath(folder))
