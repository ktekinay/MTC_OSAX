# Generates cases.json for the Array and List Utilities suite, recorded from SatimageOSAX. Run: python3 generate.py
import json, os

cases, names = [], set()
def case(name, script):
    assert name.lower() not in names, name
    names.add(name.lower())
    cases.append({"name": name, "script": script})

D1 = 'date "Saturday, January 1, 2000 at 12:00:00 AM"'
D2 = 'date "Monday, March 1, 2010 at 12:00:00 PM"'

# sortlist
for name, script in [
    ("numbers", "sortlist {2, 5, 1, 3}"),
    ("numbers-descending", "sortlist {2, 5, 1, 3} without ascending"),
    ("numbers-ascending-true", "sortlist {2, 5, 1, 3} with ascending"),
    ("reals", "sortlist {2.5, -1, 0, 1.0E+10, -0.5}"),
    ("integers-and-reals", "sortlist {3, 1.5, 2}"),
    ("strings", 'sortlist {"abc", "ABC", "xyz", "123"}'),
    ("strings-descending", 'sortlist {"abc", "ABC", "xyz", "123"} without ascending'),
    ("strings-numeric", 'sortlist {"a1", "a10", "a2", "1b", "10b", "2b"}'),
    ("comparison-1", 'sortlist {"b", "B", "a", "A", "c"} comparison 1'),
    ("comparison-2", 'sortlist {"a1", "a10", "a2", "1b", "10b", "2b"} comparison 2'),
    ("comparison-3", 'sortlist {"a10", "A2", "a1", "B1"} comparison 3'),
    ("comparison-4", 'sortlist {"b", "B", "a", "A", "c"} comparison 4'),
    ("comparison-5", 'sortlist {"b", "B", "a", "A", "c", "ab", "Ab"} comparison 5'),
    ("comparison-6", 'sortlist {"a10", "A2", "a1", "B1"} comparison 6'),
    ("comparison-0", 'sortlist {"b", "B", "a", "A", "c"} comparison 0'),
    ("comparison-numbers", "sortlist {3, 1, 2} comparison 2"),
    ("accents", 'sortlist {"é", "e", "f", "E", "è", "d"}'),
    ("accents-case-insensitive", 'sortlist {"é", "e", "f", "E", "É", "d"} comparison 1'),
    ("empty-strings", 'sortlist {"b", "", "a"}'),
    ("spaces-punctuation", 'sortlist {"b c", "b", "b-c", "bc", "_b", " b"}'),
    ("dates", f"sortlist {{{D2}, {D1}}}"),
    ("mixed-numbers-strings", 'sortlist {"b", 2, "a", 1}'),
    ("mixed-numbers-strings-dates", f'sortlist {{"b", 2, {D1}, "a", 1}}'),
    ("missing-values", "sortlist {3, missing value, 1, missing value, 2}"),
    ("missing-values-descending", "sortlist {3, missing value, 1, 2} without ascending"),
    ("booleans", "sortlist {true, false, true}"),
    ("records", "sortlist {{a:2}, {a:1}}"),
    ("remove-duplicates", "sortlist {3, 1, 3, 2, 1} with remove duplicates"),
    ("remove-duplicates-reals", "sortlist {1, 1.0, 2} with remove duplicates"),
    ("remove-duplicates-strings", 'sortlist {"a", "A", "b", "a"} with remove duplicates'),
    ("remove-duplicates-case-insensitive", 'sortlist {"a", "A", "b", "a"} with remove duplicates comparison 1'),
    ("remove-duplicates-missing", "sortlist {1, missing value, missing value} with remove duplicates"),
    ("empty", "sortlist {}"),
    ("single", "sortlist {1}"),
    ("number", "sortlist 5"),
    ("string", 'sortlist "abc"'),
    ("array", "sortlist (createarray 4 range {4, 1})"),
    ("array-descending", "sortlist (createarray 3) without ascending"),
    ("array-remove-duplicates", "sortlist (createarray 3 range {1, 1}) with remove duplicates"),
    ("lists-separately", 'sortlist {{3, 1, 2}, {"b", "a"}}'),
    ("lists-separately-descending", 'sortlist {{3, 1, 2}, {"b", "a"}} without ascending'),
    ("documentation-respect", 'sortlist {{1, 2, 3, 4}, {"abc", "ABC", "xyz", "123"}, (createarray 4), {{a:1}, "b", 3, {1, 2, 3}}} with respect to 2'),
    ("respect-1", 'sortlist {{3, 1, 2}, {"c", "a", "b"}} with respect to 1'),
    ("respect-descending", 'sortlist {{3, 1, 2}, {"c", "a", "b"}} with respect to 1 without ascending'),
    ("respect-ties-stable", 'sortlist {{2, 1, 2, 1}, {"a", "b", "c", "d"}} with respect to 1'),
    ("respect-list", 'sortlist {{2, 1, 2, 1}, {"b", "d", "a", "c"}, {1, 2, 3, 4}} with respect to {1, 2}'),
    ("respect-list-ascending-list", 'sortlist {{2, 1, 2, 1}, {"b", "d", "a", "c"}, {1, 2, 3, 4}} with respect to {1, 2} ascending {true, false}'),
    ("respect-remove-duplicates", 'sortlist {{2, 1, 2}, {"a", "b", "c"}} with respect to 1 with remove duplicates'),
    ("respect-uneven", 'sortlist {{3, 1, 2}, {"c", "a"}} with respect to 1'),
    ("respect-out-of-range", 'sortlist {{3, 1, 2}, {"c", "a", "b"}} with respect to 3'),
    ("respect-zero", 'sortlist {{3, 1, 2}, {"c", "a", "b"}} with respect to 0'),
    ("respect-not-lists", "sortlist {3, 1, 2} with respect to 1"),
    ("respect-comparison", 'sortlist {{"b", "A", "a"}, {1, 2, 3}} with respect to 1 comparison 1'),
    ("no-parameter", "sortlist"),
]:
    case("sortlist-" + name, script)

# masklist
for name, script in [
    ("documentation", 'masklist {"abc", {a:1}, "b", 3, {1, 2, 3}} with {1, 0, 1, 1, 0}'),
    ("substitute", 'masklist {"abc", "d", "b"} with {1, 0, 1} substitute missing value'),
    ("substitute-text", 'masklist {1, 2, 3} with {0, 1, 0} substitute "x"'),
    ("substitute-list", "masklist {1, 2, 3} with {0, 1, 0} substitute {9}"),
    ("mask-shorter", "masklist {1, 2, 3, 4} with {1, 0}"),
    ("mask-longer", "masklist {1, 2} with {1, 0, 1, 1}"),
    ("mask-other-values", "masklist {1, 2, 3, 4, 5} with {2, -1, 0.5, 0, 0.0}"),
    ("mask-booleans", "masklist {1, 2, 3} with {true, false, true}"),
    ("mask-text", 'masklist {1, 2, 3} with {"1", "0", "1"}'),
    ("mask-array", "masklist {1, 2, 3} with (createarray 3 range {1, 0})"),
    ("mask-all-zero", "masklist {1, 2} with {0, 0}"),
    ("empty", "masklist {} with {}"),
    ("array", "masklist (createarray 4) with {1, 0, 1, 0}"),
    ("number", "masklist 5 with {1}"),
    ("mask-number", "masklist {1, 2} with 1"),
    ("no-with", "masklist {1, 2}"),
    ("no-parameter", "masklist"),
]:
    case("masklist-" + name, script)

# topological sort
for name, script in [
    ("documentation", "topological sort edges {{13, 2}, {1, 13}, {24, 1}}"),
    ("flat-edges", "topological sort edges {13, 2, 1, 13, 24, 1}"),
    ("choices", "topological sort edges {{1, 2}, {1, 3}, {2, 4}, {3, 4}}"),
    ("choices-reversed", "topological sort edges {{3, 4}, {2, 4}, {1, 3}, {1, 2}}"),
    ("vertices", "topological sort {1, 2, 3, 4} edges {{3, 1}}"),
    ("vertices-order", "topological sort {4, 3, 2, 1} edges {{3, 1}}"),
    ("vertices-not-in-edges", "topological sort {1, 2} edges {{3, 4}}"),
    ("vertices-only", "topological sort {3, 1, 2}"),
    ("dependencies", "topological sort {1, 2, 3} dependencies {{2}, {3}, {}}"),
    ("dependencies-no-vertices", "topological sort dependencies {{2}, {3}, {}}"),
    ("dependencies-several", "topological sort {1, 2, 3, 4} dependencies {{2, 3}, {4}, {4}, {}}"),
    ("dependencies-labels", "topological sort {10, 20, 30} dependencies {{20}, {30}, {}}"),
    ("cycle", "topological sort edges {{1, 2}, {2, 1}}"),
    ("self-loop", "topological sort edges {{1, 1}}"),
    ("cycle-long", "topological sort edges {{1, 2}, {2, 3}, {3, 1}}"),
    ("duplicate-edges", "topological sort edges {{1, 2}, {1, 2}}"),
    ("empty-edges", "topological sort edges {}"),
    ("edges-and-dependencies", "topological sort {1, 2} edges {{1, 2}} dependencies {{}, {1}}"),
    ("odd-flat-edges", "topological sort edges {1, 2, 3}"),
    ("strings", 'topological sort edges {{"a", "b"}}'),
    ("reals", "topological sort edges {{1.5, 2}}"),
    ("negative", "topological sort edges {{-1, 0}, {0, 5}}"),
    ("no-parameter", "topological sort"),
]:
    case("toposort-" + name, script)

# suppress item
for name, script in [
    ("documentation-index", 'suppress item 2 from {"abc", {a:1}, "b", 3}'),
    ("documentation-indices", 'suppress item {2, 3} from {"abc", {a:1}, "b", 3}'),
    ("documentation-record", "suppress item name from {b:1, name:\"abc\"}"),
    ("negative", "suppress item -1 from {1, 2, 3}"),
    ("zero", "suppress item 0 from {1, 2, 3}"),
    ("out-of-range", "suppress item 5 from {1, 2, 3}"),
    ("repeated", "suppress item {2, 2} from {1, 2, 3}"),
    ("unsorted", "suppress item {3, 1} from {1, 2, 3, 4}"),
    ("mixed-signs", "suppress item {1, -1} from {1, 2, 3, 4}"),
    ("all", "suppress item {1, 2} from {1, 2}"),
    ("real-index", "suppress item 2.0 from {1, 2, 3}"),
    ("text-index", 'suppress item "2" from {1, 2, 3}'),
    ("empty-indices", "suppress item {} from {1, 2}"),
    ("from-empty", "suppress item 1 from {}"),
    ("record-custom", 'suppress item "abc" from {abc:1, b:2}'),
    ("record-custom-case", 'suppress item "ABC" from {abc:1, b:2}'),
    ("record-code", 'suppress item "pnam" from {name:"x", b:1}'),
    ("record-codes", 'suppress item {"pnam", "c"} from {name:"x", b:1, c:2}'),
    ("record-mixed-keys", 'suppress item {name, "b"} from {name:"x", b:1, c:2}'),
    ("record-missing", 'suppress item "zzz" from {a:1}'),
    ("record-index", "suppress item 1 from {a:1, b:2}"),
    ("record-all", "suppress item {\"a\"} from {a:1}"),
    ("list-keyword", "suppress item name from {1, 2}"),
    ("no-from", "suppress item 1"),
]:
    case("suppress-" + name, script)

# exclude items / keep items
LETTERS = '{"a", "z", "e", "r", "t", "y"}'
for verb in ("exclude", "keep"):
    for name, script in [
        ("documentation", f'{verb} items {{"r", "t", "z"}} from {LETTERS}'),
        ("documentation-lists", f'{verb} items {{"r", "t", "z"}} from {{{LETTERS}, {{1, 2, 3, 4, 5, 6}}, {{"one", "two", "three", "four", "five", "six"}}}}'),
        ("case-sensitive", f'{verb} items {{"A", "b"}} from {{"a", "A", "b", "B"}}'),
        ("case-insensitive", f'{verb} items {{"A", "b"}} from {{"a", "A", "b", "B"}} without case sensitive'),
        ("case-insensitive-accents", f'{verb} items {{"É"}} from {{"é", "e", "É"}} without case sensitive'),
        ("duplicates", f'{verb} items {{"a"}} from {{"a", "b", "a", "b"}}'),
        ("filter-duplicates", f'{verb} items {{"a", "a"}} from {{"a", "b"}}'),
        ("respect-2", f'{verb} items {{"x"}} from {{{{1, 2, 3}}, {{"x", "y", "x"}}}} with respect to 2'),
        ("uneven", f'{verb} items {{"a"}} from {{{{"a", "b", "c"}}, {{1, 2}}}}'),
        ("numbers", f'{verb} items {{1, 2}} from {{1, 2, 3}}'),
        ("numbers-text", f'{verb} items {{"1"}} from {{1, "1", 2}}'),
        ("single-string", f'{verb} items "a" from {{"a", "b"}}'),
        ("empty-filter", f'{verb} items {{}} from {{"a", "b"}}'),
        ("empty-from", f'{verb} items {{"a"}} from {{}}'),
        ("no-from", f'{verb} items {{"a"}}'),
    ]:
        case(f"{verb}-{name}", script)

# special concat
for name, script in [
    ("documentation", 'special concat {a:1, b:{1}, c:"A", d:0} with {a:2, b:{2}, c:"B"}'),
    ("documentation-text", 'special concat ("1" & tab & "2" & return & "A" & tab & "B") with ("3" & return & "C")'),
    ("only-in-second", "special concat {a:1} with {b:2}"),
    ("reals", "special concat {a:1.5} with {a:2.25}"),
    ("integers", "special concat {a:1} with {a:2}"),
    ("list-and-number", "special concat {a:{1}} with {a:2}"),
    ("number-and-list", "special concat {a:1} with {a:{2}}"),
    ("nested-records", "special concat {a:{x:1}} with {a:{x:2}}"),
    ("lists-of-lists", "special concat {a:{{1}}} with {a:{{2}}}"),
    ("text-and-number", 'special concat {a:"x"} with {a:1}'),
    ("custom-keys", "special concat {abc:1, name:\"n\"} with {abc:2, name:\"m\"}"),
    ("empty-records", "special concat {} with {a:1}"),
    ("text-linefeed", 'special concat ("1" & linefeed & "A") with ("3" & linefeed & "C")'),
    ("text-uneven", 'special concat ("1" & return & "A" & return & "X") with ("3" & return & "C")'),
    ("text-uneven-second", 'special concat ("1" & return & "A") with ("3" & return & "C" & return & "Z")'),
    ("text-trailing-return", 'special concat ("1" & return & "A" & return) with ("3" & return & "C" & return)'),
    ("text-single-line", 'special concat "a" with "b"'),
    ("text-empty", 'special concat "" with "b"'),
    ("text-and-record", 'special concat "a" with {a:1}'),
    ("lists", "special concat {1, 2} with {3}"),
    ("no-with", "special concat {a:1}"),
]:
    case("concat-" + name, script)

# Where SatimageOSAX is broken, MTC_OSAX follows the dictionary; these cases are recorded from MTC_OSAX into
# ../ListUtilitiesFixes instead.
MTC_OSAX_FIXES = {
    "sortlist-number": "Satimage returned an empty list for a single value",
    "sortlist-string": "Satimage returned an empty list for a single value",
    "sortlist-no-parameter": "Satimage returned nothing instead of error -1701",
    "sortlist-missing-values": "Satimage returned missing values as NaN reals (and made every number a real)",
    "sortlist-missing-values-descending": "Satimage put missing values in the middle when sorting descending",
    "sortlist-remove-duplicates-missing": "Satimage returned missing values as NaN reals and didn't remove duplicates",
    "suppress-documentation-index": "Satimage: error -1719 for any single index, even the dictionary's example",
    "suppress-negative": "Satimage: error -1719 for any single index (-1 means the last item, as in a list of indices)",
    "exclude-case-insensitive": "Satimage ignored case sensitive false",
    "exclude-case-insensitive-accents": "Satimage ignored case sensitive false",
    "keep-case-insensitive": "Satimage ignored case sensitive false",
    "keep-case-insensitive-accents": "Satimage ignored case sensitive false",
    "keep-empty-filter": "Satimage returned {{}, {}} for keep items {}",
    "concat-text-and-record": "Satimage returned garbage (bytes of the record as text)",
    "concat-text-empty": "Satimage returned nothing for empty text",
    **{c["name"]: "Satimage replied -1708: it never worked" for c in cases if c["name"].startswith("toposort-")},
}
assert MTC_OSAX_FIXES.keys() <= names
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
if MTC_OSAX_FIXES:
    os.makedirs("../ListUtilitiesFixes", exist_ok=True)
    json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../ListUtilitiesFixes/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
