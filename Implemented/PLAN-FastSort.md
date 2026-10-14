# Faster sortlist Plan

Branch: `feature/fast_sortlist`

Goal: make `sortlist` faster without changing a single result. The rules stay as they are (see [Sorting.swift](../Packages/MTCOSAXKit/Sources/ListUtilities/Sorting.swift)): stable, `missing value` and NaN last in both directions, text by character code with comparison flags 1, 2 and 4, several lists sorted together by `with respect to`, and `remove duplicates`.

## Where the time goes now

`order` sorts the row indices with Swift's `sorted`, through an array of comparison closures (one per key column), each calling a generic `ordered` with another closure. Swift can't inline through those, so each comparison makes several indirect calls. Text keys are an array of `UInt32` per item: one allocation each, and a pointer to follow at every comparison.

## Steps

1. **A benchmark** (`sort-benchmark`, an executable target built in release, run with `Scripts/sort-benchmark.sh`). For 1,000, 100,000 and 1,000,000 items, it times:
   - `array of real`; a list of reals; a list of integers; dates; texts with flags 0, 1, 2 and 4; texts that share a long start (paths in one folder); numbers mixed with text; reals and texts that are 95% sorted (2.5% of places swapped in pairs) and 95% duplicates (drawn from a twentieth as many distinct items, also with `remove duplicates`), and a 95% sorted `array of real`; and three lists sorted together by two keys (a number and a text), and by two number keys;
   - the whole command in process (the dispatcher, descriptor in and out), the sort (making the keys and ordering the rows), and the ordering alone (`Sorting.order`), so we can see whether the sort or the descriptors cost more.

   Its numbers before and after each step go in the Results section below.
2. **A radix sort for numbers and dates.** Each `Double` becomes a `UInt64` whose unsigned order is the number's order (the sign bit flipped for positives, every bit for negatives; -0 counts as 0). Descending inverts the key, and `missing value`/NaN is `UInt64.max`, so it's last either way. An LSD radix sort, a byte at a time, carries 32-bit row numbers; a pass is skipped when every key has the same byte there (common: whole numbers as reals end in zero bytes). It's stable, so ties keep their order without comparing row numbers, and several number keys sort together by doing the least important key first. Lists under 64 items use the merge sort of step 3.
3. **Text keys in one buffer, compared as bytes, sorted by a merge sort of our own.**
   - Every item's text (lowercased for flags 1 and 4) is UTF-8 in one shared byte buffer, the item keeping an offset and a length; flag 4 also keeps the text as it is. UTF-8's byte order is character-code order, so without flag 2 two keys compare with `memcmp`, and then by length.
   - Flag 2 (digits by value) compares the bytes in a loop like today's. Digits are ASCII and no byte of a longer character is a digit, so the rules carry over unchanged.
   - A stable merge sort of the 32-bit row numbers, with a scratch buffer made once, an insertion sort for short runs, and no merge when two runs are already in order. Its comparison is a generic parameter (not a closure), so the compiler builds a version for each kind of key. It also sorts keys that mix text with numbers (`with respect to` a text list and a number list).
   - Texts without flag 2, from 64 items, are first ordered by a radix sort of 8 bytes of each (after the bytes every text in the list shares), and only rows whose 8 bytes are equal are compared. The same goes for a number key followed by others: rows with equal numbers are compared.
   - `remove duplicates` compares neighbors with the same keys.

4. **Text keys as ranks when sorting by several keys.** Each text key column is ordered once on its own (as a single text column is), and each row gets its text's rank (equal texts the same rank). Every key is then a number, so the rows are ordered by the radix sort alone; `remove duplicates` compares ranks.
5. **Faster conversion of items, measured first** (a million items, in a release build: `Scripts/sort-benchmark.sh` and a probe of the Apple Event Manager):
   - Reading each item as an `NSAppleEventDescriptor` (`atIndex`), then its `stringValue` made native UTF-8, took 386 ms for a million texts; `AESizeOfNthItem` and `AEGetNthPtr` read the same as UTF-16 straight into the key buffer in 72 ms, and a million reals in 40 ms (83 through descriptors). Lists are read that way: numbers, integers, booleans and `missing value` from their bytes, `utxt` text as UTF-16; anything else (other text encodings, dates) still as a descriptor.
   - The sorted list is made with `AEGetNthDesc` and `AEPutDesc` from the original list (96 ms for a million texts, 138 through descriptors), and `AEPutPtr` for items that change (numbers as text or as reals), with no `NSAppleEventDescriptor` for each item.
   - A number as text took the Apple Event Manager's coercion 5.4 µs. Its form, found by comparison: 16 significant digits without trailing zeros; plain from 1e-6 up to 1e16, otherwise with an exponent without leading zeros (`1e-7`, `1e+16`) and a leading space unless negative; -0 is "0". Whole numbers below 1e16 and integers are written as integers, other finite reals from `%.15e`; infinities and NaN are written as the coercion writes them (" INF", "-INF", " NAN(000)", "-NAN(000)"): in a process that had loaded AppleScript, its first coercion of a NaN left out the space, so the text of NaN depended on what had run before. A test compares millions of numbers (every exponent, random bits) with the coercion, which every Mac has. `exclude items` and `keep items` use the same conversion.

## Letter case and accents

Added on 2026-10-14, after checking whether case-insensitive sorting works. SatimageOSAX was recorded on 16 edge cases (Greek final sigma, ß and ẞ, ligatures, the Kelvin sign, Turkish i, title-case digraphs, ÿ and Ÿ, accents typed precomposed and decomposed). It ignored case with full Unicode case folding; MTC_OSAX only lowercased, so "ος"/"ΟΣ", "straße"/"STRASSE" and "ﬀ"/"FF" weren't equal with flag 1. Both broke flag 4's ties by character code, which puts "ÿ" before "Ÿ", and both treated "é" typed as one character and as "e" with a combining accent as different texts under every flag. The aim is the right behavior, whatever Satimage did:

- **Accents however they're typed:** texts compare in Unicode's composed form (NFC) under every flag, so "é" and "e" + U+0301 are equal (and `remove duplicates` keeps the first). Composed rather than decomposed, so accented letters keep their place after the unaccented ones ("é" after "f", as Satimage recorded). Canonical equivalence only: "ﬀ" and "ff", or "²" and "2", stay different with flag 0.
- **Flag 1 (and 4) ignores case by full case folding,** as Satimage did: ß = ss = ẞ, ς = σ, ﬀ = ff, ᾳ = αι, the Kelvin sign = k. (Turkish İ and ı stay apart from i, as in any comparison that doesn't depend on a language.) The texts are decomposed, folded and composed again, Unicode's canonical caseless match.
- **Flag 4 puts uppercase first by letter case, not character code:** texts equal ignoring case are ordered by the case of their characters in turn (uppercase, then title case, then the rest), and then by character code, so different texts are never duplicates. "Ÿ" comes before "ÿ", "Ǆ" before "ǅ" before "ǆ"; ASCII keeps its order.
- **Speed:** Foundation's normalizing and folding of every text took flag 1 from 980 ms to 1734 for a million texts, and flag 4 from 1245 to 2310. ASCII texts skip them (they change nothing but A-Z), and texts of characters below U+0300 (Latin) are composed already and fold character by character, from a table made once with the same calls. Other texts (Greek, CJK, combining marks) still go through Foundation.

Satimage's recordings that match go in `Fixtures/ListUtilities`; the three that don't (decomposed accents with flags 0 and 1, ÿ and Ÿ with flag 4) move to `Fixtures/ListUtilitiesFixes`, recorded from MTC_OSAX, and in the README's differences.

## Testing

No result may change, so the existing tests and SatimageOSAX fixtures (`Fixtures/ListUtilities/sortlist-*`) must all still pass. In addition:

- `SortEquivalenceTests` (2,000 random texts, every flag, both directions, with and without removing duplicates, against the comparison `sortlist` first used) gets lists long enough for the radix sort and merge sort (not just the insertion sort), and numbers with -0, infinities and NaN.
- Unit tests for the new parts on their own: the `Double` to `UInt64` key (order across negative, -0, 0, subnormal, positive, infinities), the radix sort against a stable reference sort for random keys of every length around the insertion-sort threshold, the merge sort likewise, and the UTF-8 comparison with flag 2 on text with characters of every UTF-8 length next to digits.

## Results

Times in ms (median), from `Scripts/sort-benchmark.sh` on the same Mac. *command* is the whole `sortlist` in process (descriptors in and out); *sort* is making the keys and ordering the rows.

### Before (develop at 1.0.1)

```
1000 items                   command       sort
array of real                  0.141      0.142
reals                          0.561      0.292
integers                       0.923      0.665
dates                          0.719      0.451
text, flags 0                  1.043      0.764
text, flags 1                  1.013      0.741
text, flags 2                  1.060      0.777
text, flags 4                  1.203      0.928
numbers and text               3.040      2.767
together, number and text      1.822      0.931
together, two numbers          1.407      0.473

100000 items                 command       sort
array of real                   20.9       21.0
reals                           64.2       36.6
integers                       103.0       73.8
dates                           80.9       54.2
text, flags 0                  133.2       91.5
text, flags 1                  119.9       89.8
text, flags 2                  130.5       91.2
text, flags 4                  150.8      108.2
numbers and text               337.6      306.1
together, number and text      206.6      105.1
together, two numbers          154.7       55.1

1000000 items                command       sort
array of real                  270.7      267.3
reals                          854.8      410.5
integers                      1309.0      848.6
dates                         1169.0      621.9
text, flags 0                 1640.1     1041.9
text, flags 1                 1513.5     1052.1
text, flags 2                 1564.1     1079.8
text, flags 4                 1836.7     1333.7
numbers and text              3854.6     3329.7
together, number and text     2908.4     1259.6
together, two numbers         2217.5      634.9
```

For lists, much of *sort* is reading each item's descriptor in `classify` (an `array of real` has none: its 267 ms for a million is all ordering), and numbers mixed with text are slow because each number becomes text through the Apple Event Manager.

### After steps 2 and 3

*order* is the ordering alone, with the keys already made. Run before the shared start of texts was skipped (see below), which took the paths in one folder from 332.6 ms to 34.7 for a million and changed nothing else.

```
1000 items                   command       sort      order
array of real                  0.021      0.016      0.015
reals                          0.465      0.167      0.014
integers                       0.580      0.308      0.018
dates                          0.605      0.357      0.018
text, flags 0                  0.789      0.527      0.015
text, flags 1                  0.772      0.512      0.015
text, flags 2                  0.816      0.551      0.038
text, flags 4                  0.884      0.621      0.016
text, one folder's paths       1.057      0.781      0.049
numbers and text               2.695      2.342      0.016
together, number and text      1.577      0.678      0.030
together, two numbers          1.199      0.296      0.026

100000 items                 command       sort      order
array of real                  1.421      1.197      1.197
reals                           43.3       14.6      1.191
integers                        56.5       30.3      1.650
dates                           59.6       33.4      1.494
text, flags 0                   81.9       53.7      1.440
text, flags 1                   80.8       52.6      1.483
text, flags 2                   94.8       65.8       14.1
text, flags 4                   92.9       64.3      1.485
text, one folder's paths       151.5       97.9       18.6
numbers and text               270.5      240.6      1.400
together, number and text      179.0       78.7       13.9
together, two numbers          130.0       28.9      2.296

1000000 items                command       sort      order
array of real                   15.6       13.1       13.1
reals                          628.2      148.4       13.0
integers                       747.9      306.6       17.9
dates                          766.4      335.3       15.8
text, flags 0                  977.7      536.4       17.1
text, flags 1                  980.1      521.6       19.2
text, flags 2                 1175.0      712.2      209.2
text, flags 4                 1245.2      702.9       25.5
text, one folder's paths      1789.4     1168.4      332.6
numbers and text              3213.2     2598.4       19.1
together, number and text     2736.4      974.7      288.7
together, two numbers         2058.1      306.0       25.3
```

For a million: an `array of real` 267 ms to 15.6 (17 times as fast); lists of numbers and dates a quarter to 40% faster; texts 1640 ms to 978. With the keys made, ordering is now 13 to 35 ms for everything but flag 2 (about 210) and texts sorted after a number (about 290), which compare. What's left is reading the descriptors and making the keys: the steps under "Later" above.

Step 3 also orders texts without flag 2 by a radix sort of 8 bytes of each (after the bytes every text shares), and only compares rows whose 8 bytes are equal: for a million texts, comparing them all took 222 ms (394 before step 3), and this takes 17.

### After letter case and accents

```
1000 items                   command       sort      order
array of real                  0.021      0.015      0.015
reals                          0.459      0.162      0.014
integers                       0.578      0.306      0.018
dates                          0.604      0.348      0.017
text, flags 0                  0.816      0.537      0.017
text, flags 1                  0.837      0.573      0.017
text, flags 2                  0.821      0.557      0.039
text, flags 4                  0.954      0.675      0.017
text, one folder's paths       1.070      0.785      0.030
numbers and text               2.636      2.358      0.018
together, number and text      1.585      0.685      0.031
together, two numbers          1.199      0.299      0.026

100000 items                 command       sort      order
array of real                  1.421      1.191      1.194
reals                           42.3       14.7      1.191
integers                        56.4       30.0      1.651
dates                           61.0       33.6      1.505
text, flags 0                   83.8       54.6      1.734
text, flags 1                   86.4       57.2      1.769
text, flags 2                   95.3       67.0       14.0
text, flags 4                   95.3       66.3      1.788
text, one folder's paths       117.5       81.5      3.090
numbers and text               274.9      241.2      1.664
together, number and text      190.7       81.3       14.0
together, two numbers          135.6       29.5      2.305

1000000 items                command       sort      order
array of real                   15.6       13.1       13.1
reals                          595.6      151.1       13.1
integers                       728.4      299.4       17.2
dates                          768.8      334.0       15.9
text, flags 0                  997.3      547.3       18.7
text, flags 1                 1024.4      577.8       20.1
text, flags 2                 1185.7      730.5      205.7
text, flags 4                 1168.2      670.5       25.6
text, one folder's paths      1392.9      818.9       32.7
numbers and text              2969.7     2447.4       18.1
together, number and text     2262.7      911.6      242.4
together, two numbers         1760.9      294.1       24.5
```

Texts take about what they did before, with the right results: the benchmark's words are Latin (a third have é, É, ø or ß), so they use the table. Greek, CJK and other texts above U+0300 are normalized and folded by Foundation, which is slower.

### After steps 4 and 5

The whole command in ms (median), before any change (the commit that added the benchmark) and after step 5, run one after the other on the same Mac (with a Time Machine backup running for both). "One folder's paths" is newer than the first run. The benchmark's full output after step 5:

| List | 100,000: before | after | faster | 1,000,000: before | after | faster |
|---|--:|--:|--:|--:|--:|--:|
| array of real | 21.2 | 1.482 | 14.3× | 275.2 | 16.7 | 16.5× |
| reals | 65.2 | 18.1 | 3.6× | 870.8 | 327.8 | 2.7× |
| integers | 104.0 | 18.1 | 5.7× | 1267.2 | 307.1 | 4.1× |
| dates | 81.7 | 52.9 | 1.5× | 1038.9 | 699.2 | 1.5× |
| text, flags 0 | 118.8 | 28.5 | 4.2× | 1517.9 | 397.9 | 3.8× |
| text, flags 1 | 119.2 | 29.1 | 4.1× | 1523.6 | 385.6 | 4.0× |
| text, flags 2 | 120.5 | 42.7 | 2.8× | 1560.1 | 595.7 | 2.6× |
| text, flags 4 | 138.5 | 29.2 | 4.7× | 1754.1 | 441.6 | 4.0× |
| text, one folder's paths | — | 38.8 |  | — | 612.3 |  |
| numbers and text | 339.4 | 76.1 | 4.5× | 3810.0 | 963.0 | 4.0× |
| together, number and text | 207.4 | 76.3 | 2.7× | 2801.4 | 1130.5 | 2.5× |
| together, two numbers | 160.4 | 68.0 | 2.4× | 2447.6 | 987.5 | 2.5× |

```
1000 items                   command       sort      order
array of real                  0.018      0.013      0.013
reals                          0.174      0.091      0.013
integers                       0.174      0.097      0.019
dates                          0.500      0.424      0.017
text, flags 0                  0.220      0.132      0.017
text, flags 1                  0.221      0.132      0.019
text, flags 2                  0.243      0.151      0.040
text, flags 4                  0.276      0.186      0.018
text, one folder's paths       0.287      0.181      0.031
numbers and text               0.708      0.553      0.018
together, number and text      0.683      0.234      0.044
together, two numbers          0.642      0.188      0.027

100000 items                 command       sort      order
array of real                  1.482      1.229      1.233
reals                           18.1      8.704      1.221
integers                        18.1      9.294      1.717
dates                           52.9       42.8      1.609
text, flags 0                   28.5       14.0      1.945
text, flags 1                   29.1       13.9      1.921
text, flags 2                   42.7       28.1       15.7
text, flags 4                   29.2       16.7      1.841
text, one folder's paths        38.8       19.9      3.218
numbers and text                76.1       58.1      1.747
together, number and text       76.3       23.5      4.618
together, two numbers           68.0       17.1      2.374

1000000 items                command       sort      order
array of real                   16.7       13.9       13.7
reals                          327.8       88.0       14.4
integers                       307.1       96.8       18.1
dates                          699.2      437.1       16.4
text, flags 0                  397.9      135.4       20.8
text, flags 1                  385.6      149.3       23.9
text, flags 2                  595.7      356.0      233.2
text, flags 4                  441.6      186.4       29.1
text, one folder's paths       612.3      198.5       36.2
numbers and text               963.0      583.5       20.9
together, number and text     1130.5      246.7       61.7
together, two numbers          987.5      172.4       25.3
```

Most of what's left is the Apple Event Manager's: reading a list's items and making the sorted list (*command* less *sort*), and for dates, which are still read as descriptors, their keys. Flag 2's texts still compare (about 230 ms of ordering for a million).

### Lists 95% sorted, and 95% duplicates

Added after step 5, at the user's request, with tests (`SortedResultTests` sorts numbers and texts arranged each way). The same cases added to the benchmark at the commit that added it, so the lists are the same, and run one after the other:

| List | 100,000: before | after | faster | 1,000,000: before | after | faster |
|---|--:|--:|--:|--:|--:|--:|
| array of real, 95% sorted | 7.156 | 1.437 | 5.0× | 93.9 | 15.9 | 5.9× |
| reals, 95% sorted | 47.3 | 16.6 | 2.8× | 497.3 | 176.9 | 2.8× |
| reals, 95% duplicates | 62.3 | 17.8 | 3.5× | 864.7 | 310.6 | 2.8× |
| reals, 95% dup., unique | 41.9 | 9.265 | 4.5× | 480.0 | 96.7 | 5.0× |
| text, 95% sorted | 95.0 | 20.6 | 4.6× | 1006.3 | 213.8 | 4.7× |
| text, 95% duplicates | 114.2 | 22.4 | 5.1× | 1532.8 | 374.4 | 4.1× |
| text, 95% dup., unique | 94.3 | 14.6 | 6.5× | 1195.1 | 168.7 | 7.1× |

Swift's sort, which the command used before, took advantage of order already there (a 95% sorted array of real took 94 ms for a million, a random one 275); the radix sort takes the same time however the list is arranged, 16 ms. Duplicates make little difference to either, beyond `remove duplicates` leaving a twentieth as many items to put in the result.
