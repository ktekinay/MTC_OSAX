# sortlist Audit Plan

Branch: `feature/arrays` (with the Arrays audit)

An audit of `sortlist` and the code around it (2026-10-17), each case reproduced through the dispatcher in a scratch
build. The sort itself is sound: the benchmark matches [the faster sortlist's](Implemented/PLAN-FastSort.md) final
results. What it found, and what's to be done, crashes first:

## Crashes and runaway memory

- [x] `with respect to` naming 100,000 criteria (or 20,000 lists sorted together, each by itself) crashed after
  growing to 8.9 GB: `withOrders` recursed once per criterion, copying the orders so far each time. With several
  criteria, text columns always become ranks (as they did from 64 rows), so every key is a number and one order
  compares them, without recursion.
- [x] A criterion that repeats an earlier one is dropped, with its `ascending`: rows equal by every criterion before
  it are equal by it too, so it can't change the order (1,000 of them on 100,000 rows took 10.5 s and 1.7 GB).
- [x] `ascending` is read only as far as there are criteria (an array of 10,000,000 made a descriptor for each
  number: 11.8 s and 1.6 GB), and `with respect to`'s numbers without a descriptor for each.

Afterwards (the same probes): 100,000 repeated criteria 25 ms, 20,000 lists sorted together 40 to 51 ms, 1,000
criteria on 100,000 rows 61 ms, an `ascending` array of 10,000,000 11 ms. Sorting together otherwise takes what it did
(`Scripts/sort-benchmark.sh --only together`), and lists under 64 rows are now checked against the reference too.

## Speed

- [x] Dates' keys from their 8 bytes (seconds since 1904, local time) instead of a descriptor and its `dateValue`:
  365 ms to 56 for a million. The order is the same, but for local times that don't exist (the hour skipped when
  clocks go forward), which a script can only make itself (decided 2026-10-17: that's on the script).
- [x] `NumberText` writes reals in one buffer, without arrays: 757 ms to 398 for a million, the same text for
  5,000,000 random numbers.

Afterwards (`Scripts/sort-benchmark.sh`, the whole command): a million dates 610 ms to 280, a million numbers and
texts 816 to 660 (100,000: 51 to 17.5, and 70 to 52). `NumberText` also gave the same text as before for 5,000,012
random numbers, besides `NumberTextTests`' comparison with the coercion.

## Code quality

- [ ] One type for "an `array of real`'s numbers or a list" (`Sorting.Together` and `ListUtilities.Items`), one
  `isList`, a list item's number decoded in `RawList.Item` for both suites, an array in a list of lists decoded once.

## Testing

Tests for each case above; the existing tests and the SatimageOSAX fixtures must all still pass, and
`Scripts/sort-benchmark.sh` must show no slower case.
