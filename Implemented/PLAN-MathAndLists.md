# Math and Lists Plan

Branch: `feature/math_and_lists`

Goal: implement the **Mathematical Functions** and **Array and List Utilities** suites (priority 4 in [PLAN.md](../PLAN.md)), matching SatimageOSAX where it works and following the dictionary's documentation where it doesn't.

From the **Arrays** suite, only what these two need: its `array of real` type, which they accept and return, and the two commands that make arrays, `createarray` and `randomarray`. The other Arrays commands stay in "May Do Later" (decided 2026-09-27).

## Scope

### Mathematical Functions (event class `MATH`, 27 commands)

Each takes a number and returns a real; `atan2` and `hypot` take a list of two numbers. Most also take a list or an `array of real` and return the same kind.

| Commands | Codes |
|---|---|
| `abs`, `sqr`, `sqrt` | `MATHABS `, `MATHSQR `, `MATHSQRT` |
| `ceil`, `floor`, `trunc` | `MATHCEIL`, `MATHFLOO`, `MATHTRUN` |
| `exp`, `ln`, `log10` | `MATHEXP `, `MATHLN  `, `MATHLOG ` |
| `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2` | `MATHSINE`, `MATHCOSI`, `MATHTANG`, `MATHASIN`, `MATHACOS`, `MATHATAN`, `MATHATA2` |
| `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` | `MATHSINH`, `MATHCOSH`, `MATHTANH`, `MATHASIH`, `MATHACOH`, `MATHATAH` |
| `erf`, `erfc`, `gamma`, `lgamma`, `hypot` | `MATHERF `, `MATHERFC`, `MATHGAMM`, `MATHLGAM`, `MATHHYPO` |

### Array and List Utilities (7 commands)

| Command | Code | What it does |
|---|---|---|
| `sortlist` (synonym `sortarray`) | `SATISort` | Stable sort of numbers, strings or dates, missing values last; a list of lists sorted separately, or together by `with respect to` (an index, or a list of indices in priority order); `ascending` (a list when `with respect to` is), `remove duplicates`, `comparison` (1 case-insensitive, 2 numeric, +4 forced "A" < "a" < "B") |
| `masklist` | `SATIMASk` | Keep the items where a mask of 0s and 1s (`with`) has 1, or replace the others with `substitute` |
| `topological sort` | `SATITSrt` | Order vertices from `edges` (pairs, or a flat list) or `dependencies`; error if there's a cycle |
| `suppress item` | `SATIDLKY` | Delete items by index (or a list of indices) from a list, or by key (keywords, or custom properties in quotes) from a record |
| `exclude items` | `SATIEIFL` | Set difference of strings; with a list of lists, filter every list by the one at `with respect to`; `case sensitive` (default true) |
| `keep items` | `SATIKIFL` | Set intersection, with the same options |
| `special concat` | `SATICONC` | Merge two records (lists concatenated, numbers added, other values kept from the first), or put tab-separated text tables side by side |

### From Arrays: `array of real`, `createarray`, `randomarray`

`array of real` (`Lido`) is a packed list of reals. Math functions, `sortlist` and `masklist` (its mask) accept one wherever they take a list of numbers, and return the same kind.

| Command | Code | What it does |
|---|---|---|
| `createarray` | `SATICRAR` | An array of n evenly spaced numbers, across `range {min, max}` |
| `randomarray` | `SATICRRA` | An array of n random numbers within `range`; `seed` for a repeatable sequence |

MTC_OSAX's dictionary gets an "Arrays" suite with only these: the `array of real` type and the two commands, copied verbatim.

Reading the numbers back out of an array (for example `extractarray`) stays with the rest of Arrays. Until then, arrays are for passing from one command to another, as they effectively are in SatimageOSAX, where `as list of real` fails (see below).

None of the scripts in `~/Documents/AppleScript Projects` use any of these commands, so there are no call shapes to prioritize; every parameter gets fixtures.

## Found so far

A first probe of SatimageOSAX (2026-09-27):

- **An `array of real` is opaque data** (`«data Lido…»`): the text "Not a record", the tag `buod`, then little-endian doubles. MTC_OSAX can read and write it.
- **Scripts can't convert arrays.** `anArray as list of real` and `{1, 2, 3} as array of real` fail with -1700 in SatimageOSAX: coercions run in the script's own process, and only the old scripting addition could install them there. MTC_OSAX can't either.
- **Lists in, lists out.** `cos {0, 1}` returns a list and `cos anArray` an array; `sortlist` returns a list for a list.

## Behavior to establish from fixtures

Recorded from SatimageOSAX; where Satimage fails, the documentation wins, per the project rule.

- **Array format.** The header exactly (what the bytes after `buod` mean), empty arrays, NaN for missing values.
- **`createarray`.** The default range (1 to n?), the spacing with `range` (including n = 1, reversed and equal bounds), n = 0 and negative n.
- **`randomarray`.** The default range, whether bounds are included, errors, and whether Satimage's generator can be reproduced.
- **Math results.** Real or integer (`abs -3`, `floor 2.5`); integers, text numbers (`"2.5"`) and lists of lists as input; domain errors (`sqrt -1`, `ln 0`, `acos 2`, `gamma 0`): NaN, infinity or an error; `atan2`/`hypot` with the wrong number of items.
- **Precision.** Whether Satimage's Intel math library and Apple silicon's agree to the last digit.
- **`sortlist`.** Mixed lists (numbers, text, dates), `missing value`, the default string comparison (the example puts "ABC" before "abc"), `comparison 2` and `1+4`, `remove duplicates`, arrays.
- **List utilities.** Masks of other lengths or values; `topological sort` order when several are possible, the flat `edges` form, `dependencies` indexing, cycles; `suppress item` with negative, out-of-range or repeated indices and record keys of each kind; `exclude items`/`keep items` order, duplicates and uneven lists of lists; `special concat` with keys in only one record, nested records, integers vs reals (the example gives `a:3.0`) and text tables of different sizes.

## Architecture

- **Modules** `MathFunctions`, `ListUtilities` and `Arrays` (for now just `createarray` and `randomarray`), registered in `CommandCatalog`, plus a shared `Numerics` module for the array type and number decoding, which the rest of Arrays will build on later.
- **Random numbers** from the Mersenne Twister (MT19937), the generator SatimageOSAX turned out to use, seeded from the system when no `seed` is given.
- **`ArrayOfReal`** in `Numerics`: reads and writes the `Lido` format, and decodes numbers, lists and arrays alike. Results keep the input's kind, as Satimage's do.
- **Math** with Darwin's `libm`.
- **Sorting.** A comparator ordering values by type, then value; stable; the `comparison` flags through `String.compare` options.
- **Records.** `suppress item` and `special concat` need records with user keys (`usrf`) as well as four-character keys; `AppleEventCore` gets record decoding that keeps both, in order.

## Testing

- Fixtures from SatimageOSAX in `Fixtures/MathFunctions` and `Fixtures/ListUtilities`, generated by `generate.py` scripts: every command and parameter at typical values, edges (0, negatives, huge, NaN, infinity, empty), lists and arrays, and errors. Math functions also get a few hundred random inputs, as the number format tests did.
- `DescriptorSnapshot` shows arrays as their numbers, so fixtures are readable and diffs useful.
- If the last digits differ between Intel and Apple silicon, replays compare reals (including inside arrays) within a few units in the last place, for these folders only, and the plan will say so.
- `randomarray` without a seed can't be replayed as recorded; those fixtures check only how many numbers there are (`mark_random.py`), and unit tests check the range.
- Unit tests for every command, the array format, the number decoder, the sort comparator and record keys.
- `Scripts/e2e/math-lists.applescript` through `Scripts/parity.sh`, and a `*-fixes` script for deviations.

## Order of work

1. Copy the two suites, and the `array of real` type with `createarray` and `randomarray`, into the SDEF, with placeholder handlers.
2. Fixture tooling: arrays shown as numbers, tolerant real comparison if needed.
3. Record SatimageOSAX fixtures; settle the behaviors above.
4. `Numerics`: the array format and number decoding. `createarray`, `randomarray`. Math functions.
5. Record keys in `AppleEventCore`; `suppress item`, `special concat`.
6. `sortlist`, `masklist`, `exclude items`, `keep items`, `topological sort`.
7. Anything Satimage gets wrong: implement from the documentation, record from MTC_OSAX into `…Fixes` fixture folders, and list it in this plan.
8. End-to-end and parity scripts.

## Done when

- [x] All 36 commands and the `array of real` type implemented; SDEF consistency tests pass.
- [x] SatimageOSAX fixtures for every command and parameter replay without differences; every deviation listed here with MTC_OSAX fixtures.
- [x] Unit tests for every command, including error cases.
- [x] `Scripts/e2e/math-lists.applescript` passes, and `Scripts/parity.sh` shows no differences for shared behavior.

## Decisions

Made 2026-09-27 and 2026-09-28:

1. From Arrays, only the `array of real` type, `createarray` and `randomarray`; the rest of the suite stays in "May Do Later".

## Findings during implementation

Recorded from SatimageOSAX in `Fixtures/MathFunctions` (255 cases), `Fixtures/Arrays` (38) and `Fixtures/ListUtilities` (131), generated by `generate.py` in each, all replaying without differences:

- **`array of real`** is the text "Not a record", the tag `buod`, then little-endian doubles. It's in `AppleEventCore` (`ArrayOfReal`), since fixtures store arrays as their numbers. Scripts still can't convert arrays to lists (`as list of real` fails in SatimageOSAX too).
- **Math.** Results are reals. A single result that isn't finite (NaN, infinity, overflow) is error -50; in a list it's `missing value`, in an array NaN. Text that reads as a number is accepted; booleans, dates and `missing value` are -1700, a record -1701. `atan2`/`hypot` need a list of exactly two numbers (not an array), else -50.
- **Precision.** Intel's and Apple silicon's math libraries differ by up to 2 units in the last place for trigonometry and 15 for `lgamma` near its roots, so math replays allow 16 units (`realTolerances` in `FixtureReplayTests`).
- **`createarray n`** makes 0 to n−1, or n evenly spaced numbers (`min + i × step`) across `range`; `range` uses its first two numbers, and one number means min = max. Sizes round half to even (2.5 makes 2); below 1 is -50.
- **`randomarray`** is MT19937 (`init_genrand` with the seed, each 32-bit output divided by 2³²), so seeded arrays match SatimageOSAX exactly; seeds round half to even and wrap to 32 bits.
- **`sortlist`.** Text sorts by character code; any text in a list makes it a text sort, turning numbers and booleans into text; numbers stay integers unless one is a real; dates can't be mixed (-1700). `comparison` 4 is case-insensitive with uppercase first. Lists of lists that differ in length, or a `with respect to` that isn't a list's index, are error -1.
- **`masklist`.** A shorter mask repeats; a longer one is -50; a mask value that isn't a number (such as a boolean) keeps its item.
- **`suppress item`.** A list of indices may use negatives from the end; 0 and out-of-range indices are -1719, reals and text -50; record keys are keywords, four-character codes as text, or user property names (case-sensitive).
- **`exclude items`/`keep items`** compare as text, so `1` matches `"1"`. A real's text is the Apple Event Manager's, not AppleScript's: up to 15 digits and no `.0` (1.0 is `"1"`, 0.1 + 0.2 is `"0.3"`), with a leading space when it has an exponent (`" 1e+20"`). So `"1"` matches 1.0, `"1.0"` matches no number, and 0.3 matches 0.1 + 0.2; `sortlist` of reals with text returns those texts (`exclude-reals-*`, `sortlist-reals-and-text*`).
- **`special concat`** adds numbers as reals (a one-item list counts as its number), joins lists, merges nested records, keeps the first value otherwise, and appends the second record's other properties. Tables keep their row separator; missing cells are empty.

## Fixing Satimage's bugs

Recorded from MTC_OSAX in `Fixtures/ListUtilitiesFixes` and `Fixtures/ArraysFixes`, with unit tests and `Scripts/e2e/math-lists-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `topological sort` | Replied -1708: never worked | Implemented from the dictionary: edges as pairs or a flat list, `dependencies` (the vertices that come before each vertex), ties in the order vertices were given; a cycle is -2700 |
| `sortlist` of a single value | An empty list | A list of that value |
| `sortlist` without a parameter | No result | Error -1701 |
| `sortlist` with `missing value` | Returned NaN reals (turning every number into a real), in the middle when sorting descending, and kept duplicates | `missing value`, always last, one kept with `remove duplicates` |
| `suppress item` with one index | Error -1719, even for the dictionary's example | Removes it (-1 is the last item) |
| `exclude items`/`keep items` `without case sensitive` | Still case-sensitive | Ignores case |
| `exclude items`/`keep items` from an `array of real` | No result; an array among the lists was never filtered | Filtered as a list of the same reals is, and returned as a list of reals (unit tests) |
| `keep items {}` | `{{}, {}}` | `{}` |
| `special concat` text with a record | Garbage (the record's bytes as text) | Error -1700 |
| `special concat` with empty text | No result | Empty cells (`"" with "b"` is tab & "b") |
| `randomarray … seed` beyond 32 bits | Ignored the seed | Uses its low 32 bits, so the numbers repeat |
