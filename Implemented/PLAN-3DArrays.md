# 3D Arrays Plan

Branch: `feature/3d_arrays`

Goal: implement Satimage's **3D array handling** suite (in "May Do Later" in [PLAN.md](../PLAN.md)): 9 commands and the
`Array3DRef` type. A script loads a 3D array of numbers (or a vector field, three of them) with `open3D`, refers to it
by the reference it gets back or by its name, and reads it (`info3D`, `contents3D`, `extract3D`), computes an
`isosurface` or a `streamline` from it, and releases it with `close3D`. As before: match SatimageOSAX where it works,
follow the dictionary where it doesn't.

## What a first probe of SatimageOSAX found (2026-10-19)

About 50 cases on 3×3×3 fields (not kept; the fixtures come in step 2):

- **References** are `«data VI3D…»`: a 4-byte little-endian number from a counter that runs for the life of the app
  (1, 2, 3, … across `open3D`s, closed ones included). `class of` one is `Array3DRef`; `as integer` is -1700.
- **Names:** `open3D` without one names the array `3Darray` and its number in four digits (`3Darray0003`). Names may
  repeat; a name finds the most recently opened array with it. Every command but `open3D` and `list3D` takes a
  reference or a name; a closed one, or an unknown name, is -1728 ("Can't get «data VI3D…»" or "Can't get "nothing"").
- **`list3D`** gives the open arrays' references, newest first; `as string` (or `as text`) their names; `{}` if none.
- **`info3D`**: `{name, dimensions:{nx, ny, nz}, scale:{x array, y array, z array}, number of field: 1 or 3,
  minimum:{…}, maximum:{…}}`, minimum and maximum for each field (`missing value` for fields it doesn't have), leaving
  out NaN. A dimension given as a number has the scale 0, 1, 2, …; given as an array (or a list), those numbers.
- **Values are stored as 4-byte reals**, and come back as such: `contents3D`, `extract3D` and the scales are arrays of
  4-byte reals (the tag `gnis`, which `ArrayOfReal` already reads). 0.1 comes back as 0.10000000149, and 1.0E+300 as
  infinity.
- **`extract3D`** gives the block from the 1-based `start`, `length` long in each dimension, x varying fastest; a block
  past the edge, a start of 0 or a length of 0 is -1719; `field index` past the fields is -1.
- **`isosurface`** gives triangles, 9 numbers each (three vertices, x, y, z), in the scales' coordinates: a value of 1
  at the center of a 3×3×3 field of 0 gives 8 triangles at 0.5 (an octahedron), as marching cubes makes them. None at
  that value is error 7. `field index` picks a vector field's component.
- **`streamline` doesn't work:** from any point inside, in any field (a uniform flow, a rotating one), at any
  `resolution` and `direction`, it returns the starting point 30,001 times. From outside the box it's error 2000; on a
  scalar field, -1.
- **Recording the fixtures showed more** (2026-10-19):
  - **`isosurface` is broken too:** it leaves most of the surface out. In a single cell, only corner 0 alone above or
    below the value makes a triangle (254 of the 256 patterns gave nothing or an error); random 4×4×4 fields got a
    third to a half of their vertices. The 3×3×3 center case only looked right because it's symmetric. Error 7 is a
    value outside the field's range (above its maximum or below its minimum); at the minimum itself it gave an empty
    array, and at the maximum degenerate triangles at the corner.
  - `info3D`'s minimum and maximum (4-byte reals) were garbage (8.3e-315) when the field's first number was missing.
  - `streamline` from outside the box gave error 2000 once and an empty array another time.
  - `contents3D` of a vector field gives a list of its three arrays. `extract3D` counts a negative start from the
    end, as `extractarray` does; two starts is -1721, no `length` -1701, `field index` 0 -1. A dimension of 0 is
    error 10.
- **Errors:** a field that isn't nx × ny × nz numbers is error 2; dimensions that aren't three, error 3; one field or
  three (two is -1); no `field` is -1701. A dimension of 2.5 is 2. A field given as a list (not an array) is -1, though
  the other Arrays commands take lists.

## Commands

1. **The store and references:** `open3D`, `close3D`, `list3D`, `rename3D`, `info3D`, `contents3D`. Opened arrays
   live in the app's `DocumentStore`, with the property lists and XML documents, so the app doesn't quit for being
   idle while one is open (but outside pools: `DeletePool` doesn't close them). References are `VI3D` descriptors as
   Satimage's, numbered from a counter of their own, and fixture replay treats them as it treats CFRefs and XMLRefs.
   A direct parameter may be a reference or a name (text).
2. **`extract3D`**, and `field index` for vector fields.
3. **`isosurface`**, from the dictionary (Satimage's left most of the surface out): marching cubes on the cells (x
   varying fastest), a corner counting as below the value if it's less, vertices interpolated along the edges in the
   scales' coordinates. Its table is made by a program from the corners alone, rather than copied: on each face of a
   cell, the edges where the value is crossed are joined so that corners below it that touch only at a corner stay
   apart (a rule of the face alone, so neighbouring cells agree and the surface has no cracks), and each loop is a fan
   of triangles turning the same way. Error 7 for a value outside the field's range, as recorded; none crossed (at the
   minimum) is an empty array.
4. **`streamline`** (see decision 2).

## Decisions

All five accepted as proposed (2026-10-19).

1. **Precision:** store and return 8-byte reals, as `read binary` does (decided for the Arrays suite), rather than
   Satimage's 4-byte ones, which lose digits and turn large numbers into infinity. Fixtures compare reals within a
   tolerance where Satimage's 4-byte results differ only by that; the README lists the difference.
2. **`streamline`, from the dictionary** (Satimage's never moved): the field interpolated trilinearly in the scales'
   coordinates, integrated by fourth-order Runge–Kutta in steps of `resolution` times the smallest grid spacing (so a
   smaller resolution gives more points, as the dictionary says), along the field's direction (or against it with
   `direction -1`), stopping at the edge of the box (the last point clipped to it), where the field is 0, or after
   30,000 steps (Satimage's 30,001 points). Result: the points, the start first. Error 2000 for a start outside the
   box, -1 for a scalar field, as recorded.
3. **Lists for `field` and the dimensions**, as the other Arrays commands take them (Satimage: -1 for a list field).
4. **Limits:** a field at most 100,000,000 numbers (all three components together), as for the Arrays commands; no
   limit on how many arrays are open (as for documents), each one's memory freed by `close3D`.
5. **Release:** this goes in the README's 1.1 release notes with the Arrays suite, unless 1.1 has been released by then.

## Testing

- **SatimageOSAX fixtures** in `Fixtures/Arrays3D` from a `generate.py`: every command and parameter, names and
  references (by name, repeated names, renamed, closed), and errors. Each case closes what it opens, and references
  are compared as opaque. Satimage's 4-byte values are compared within a 4-byte real's precision.
- **Where Satimage is broken** (`isosurface`'s surfaces, `streamline`, minimum and maximum with a missing first
  number, 4-byte precision where it shows, a list as `field`): cases in `Fixtures/Arrays3DFixes`, recorded from
  MTC_OSAX, among them `isosurface` on each of the 256 corner patterns once (with corners that differ, so each vertex
  is at its own place along its edge) and on random fields; in the README's differences and this plan.
- **Unit tests**: the store (counter, names, newest first, idle timeout, pools), `extract3D` against the offsets the
  dictionary gives, `isosurface` (every vertex on the isosurface by interpolation, the surface closed for a field inside
  the box, all 256 patterns), `streamline` against fields with known streamlines (uniform: a straight line; rotating: a
  circle whose radius stays within the integration's error; one that leaves the box: stops at the edge), and errors.
- **End to end:** `Scripts/e2e/arrays3d.applescript` with `parity.sh` against SatimageOSAX, and
  `arrays3d-fixes.applescript` for what MTC_OSAX does differently.

## Steps

1. Copy the suite into `MTC_OSAX.sdef` verbatim, with placeholder handlers; SDEF consistency tests pass.
2. Record the fixtures from SatimageOSAX.
3. Implement in the order above, each group with its tests, committed as it's done.
4. Fixes for what Satimage gets wrong, recorded from MTC_OSAX.
5. README (move 3D arrays out of "Not implemented", the differences, the release notes), PLAN.md, e2e scripts; full
   test suite.

## Results

- [x] The suite in the dictionary, as Satimage's, with `dimensions`, `scale` and `number of field` (`info3D`'s record,
  from Satimage's Linear algebra suite) in the Types suite; the SDEF consistency tests pass.
- [x] 44 fixtures recorded from SatimageOSAX in `Fixtures/Arrays3D` (references compared as opaque, reals within a
  4-byte real's precision: 2^30 units in the last place, or 1e-6), all replaying.
- [x] 22 cases where MTC_OSAX follows the dictionary, recorded from MTC_OSAX in `Fixtures/Arrays3DFixes`: `isosurface`
  (the 256 corner patterns, random fields, scales, a vector field, the field's ends), `streamline` (uniform and rotating
  flows, a start outside), minimum and maximum with a missing first number, a field as a list, 8-byte precision.
- [x] Unit tests (`Tests/Arrays3DTests`): the store (references, names, newest first, idle timeout, outside pools),
  `extract3D` against the dictionary's offsets, `isosurface` (the table cuts exactly the crossed edges; a linear
  field's surface exactly on the value and facing up its gradient; a sphere's closed and facing out; the octahedron),
  `streamline` (a uniform flow's straight line ending on the edge; a rotating flow's circle within 1e-3 over 30,000
  steps; stopping where the field is 0; scales out of order).
- [x] `Scripts/e2e/arrays3d.applescript` (27 checks, the same output from both apps) and `arrays3d-fixes.applescript`
  (12 checks).
- [x] README: out of "Not implemented", the fixes and differences, the 1.1 release notes; PLAN.md.

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `isosurface` | Most of the surface left out (1 of 256 corner patterns made a triangle) | The whole surface (marching cubes) |
| `streamline` | The start, 30,001 times; from outside, error 2000 or an empty array | Follows the field to the edge; error 2000 from outside |
| `info3D` minimum and maximum with a missing first number | Garbage (8.3e-315) | Leave out missing values |
| `open3D … field` a list | -1 | Taken, as the Arrays commands take lists |
| Numbers | 4-byte reals (0.1 is 0.10000000149; 1.0E+300 is infinity) | 8-byte reals |
