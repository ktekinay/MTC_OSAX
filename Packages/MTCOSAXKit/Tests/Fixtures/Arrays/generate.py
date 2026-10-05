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

# Where SatimageOSAX is broken, MTC_OSAX follows the dictionary; these cases are recorded from MTC_OSAX into
# ../ArraysFixes instead.
MTC_OSAX_FIXES = {
    "randomarray-seed-large": "Satimage ignored a seed beyond the 32-bit range (the numbers weren't repeatable)",
}
assert MTC_OSAX_FIXES.keys() <= names
os.makedirs("../ArraysFixes", exist_ok=True)
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../ArraysFixes/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
