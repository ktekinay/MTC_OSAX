# Property Lists Plan

Branch: `feature/property_lists`

Goal: implement the **Satimage PropertyList Additions** and **Satimage Pool Additions** suites (priority 5 in [PLAN.md](../PLAN.md)), matching SatimageOSAX where it works and following the dictionary's documentation where it doesn't. This also completes `filter text … into` a property list, deferred from Text Additions.

## Scope

### PropertyList Additions (event class `PLST`, 29 commands, 4 of them hidden)

A property list is a tree of dictionaries, arrays, strings, numbers, booleans, dates and data. Scripts work on it through **CFRefs** (`CFob`): opaque references to a document or to any element inside one, valid until the document is closed.

| Group | Commands |
|---|---|
| Documents | `PlistNew` (from any AppleScript value; `typed`, `in pool`), `PlistOpen` (a file, or `from string`), `PlistClose`, `PlistSave` (`in`, `binary`), `PlistBinaryFormat`, `PlistURL` (`as`, `parent`), `PlistDocument` (the open document for a file), `PlistListDocuments` |
| Reading | `PlistCount`, `PlistChild` (a CFRef, by `index`, `key` or a `using` path like `"key1/key2[4]/key3[2]"`), `PlistGet` (the contents as AppleScript values; `as` for untyped data), `PlistGetXML`, `PlistGetKeys`, `PlistType`, `PlistEqual`, `PlistExist` (the indices or keys holding a value; `several values`), `PlistMatch` (the dictionaries in an array with a key, or a key and value) |
| Changing | `PlistSet` (`index`, `key` or `using`; `to` a value or a CFRef; `suppressing`, `typed`), `PlistNewChild` (`at`, `index`, `key`, `using`), `PlistRemoveChild`, `PlistAdd` (`after`/`before`: concatenate arrays or merge dictionaries) |
| JSON | `PlistToJSON` (`formatting`, `replacer`: a JavaScript function for `JSON.stringify`), `PlistFromJSON` (`in pool`) |
| Identifiers | `PlistSetDocID`, `PlistGetDocByID` |
| Hidden | `PlistRetain`, `PlistToJavaScript`, `PlistGetID`, `PlistFromID` |

### Pool Additions (event class `POOL`, 3 commands)

Pools are named groups of open documents (property lists now, XML documents later): `SetPool` (the default pool for new documents; returns the previous one), `DeletePool` (close every document in a pool), `GetPool` (a document's pool).

### From Text Additions: `filter text … into`

`filter text` was implemented without `into` a CFRef, since property lists didn't exist yet. With them, `into` a CFRef adds the filtered results to that dictionary.

### Your scripts

Two scripts use this suite, in the simplest way: `PlistOpen alias …`, `PlistNew`, `PlistGet … key …`, `PlistSet … key … to …`, `PlistSave … in file …` and `PlistClose`. They get fixtures first.

## Found so far

A first probe of SatimageOSAX (2026-09-28):

- **A CFRef is 16 bytes**: a document number, a constant, and a pointer into SatimageOSAX's memory. MTC_OSAX makes its own (a document number and an element number), so fixture replays must map each recorded CFRef to the one MTC_OSAX returned, and put it into later events.
- **`PlistGetXML`** writes Apple's standard XML format, with dictionary keys sorted.
- **`PlistGet`** of a dictionary returns a record with user-defined keys, in the order of the dictionary's internal hashing, not the order they were set. Fixture replays compare record fields regardless of order.
- **Types.** Text becomes `<string>`, integers `<integer>`, reals `<real>`, booleans `<true/>`/`<false/>`, dates `<date>` (in UTC), lists `<array>`, records `<dict>`.
- **A closed document's CFRefs** give error -1728.

## Behavior to establish from fixtures

- **Values.** Everything `PlistNew`, `PlistSet` and `PlistNewChild` accept, and what `PlistGet` returns: aliases and file references, data, `missing value`, keywords as record keys (`{name:"x"}`), nested lists and records, very large integers, NaN; `typed false` (base64 data of the Apple event descriptor) and reading it back with `as`.
- **Paths.** The `using` syntax: escaping `/` and `[` in keys, indices out of range, paths that end on an array, paths into missing keys (error or created by `PlistSet`?).
- **Changes.** `PlistSet` on a missing index or key, `suppressing` with missing values, `to` a CFRef (copy or share), `PlistNewChild` index rules, `PlistRemoveChild` then using a removed element's CFRef, `PlistAdd` with lists and records instead of CFRefs.
- **Queries.** `PlistExist` and `PlistMatch` matching rules (types, case), results when nothing matches.
- **Files.** `PlistOpen` of XML, binary and invalid files; `from string`; `PlistSave` without `in` (the file it was opened from), `binary`, to a new file; `PlistURL` forms and `parent`; `PlistDocument` for a file opened twice; which errors for missing files and documents that were never saved.
- **JSON.** `PlistToJSON` for each type (dates and data have no JSON form), `formatting`, key order, `replacer`; `PlistFromJSON` with numbers (integer or real), `null`, invalid JSON.
- **Pools and IDs.** `PlistListDocuments` results, `SetPool`/`DeletePool` effects on open CFRefs, `PlistSetDocID` with an ID already used, the hidden number IDs.
- **Errors.** Wrong element type (`PlistGetKeys` of an array), wrong parameter combinations (`index` with `key`), closed documents.

## Architecture

- **Module `PropertyLists`**, registered in `CommandCatalog`, with the Pool commands and a `DocumentStore` that later holds XML documents too.
- **Documents** as a tree of reference-type nodes (dictionary, array, leaf values), so a CFRef to an element stays valid while other elements change. Reading and writing files with `PropertyListSerialization` (XML and binary); dictionaries keep insertion order internally, but `PlistGetXML`/`PlistSave` sort keys as Apple's format does.
- **CFRefs** as `CFob` descriptors holding a document number and an element number; the store maps them to nodes and rejects stale ones (-1728).
- **Conversions** between Apple event descriptors and property list values, shared by `PlistNew`, `PlistSet`, `PlistGet` and `filter text … into`; `typed false` flattens the descriptor to data (`AEFlattenDesc`) and back.
- **JSON** with `JSONSerialization`, and `replacer` through JavaScriptCore's `JSON.stringify`.
- **State in the app.** Open documents live in memory until closed, like Satimage's, and the app doesn't quit for being idle while any are open (decision 1).

## Testing

- Fixtures from SatimageOSAX in `Fixtures/PropertyLists` (and `Fixtures/Pools`), generated by `generate.py`: every command and parameter, and your two scripts' call shapes. Files through `$TMP` and `$FILES` inputs (XML, binary and invalid plists).
- Fixture tooling:
  - **CFRef mapping**: a replay remembers each CFRef the app returned in place of the recorded one and substitutes it in later events.
  - **Records compared regardless of field order** (Satimage's order comes from hashing).
- Unit tests for the node tree, paths, conversions, the store and pools, and each command.
- `Scripts/e2e/plists.applescript` through `Scripts/parity.sh`, and a `*-fixes` script for deviations; your two scripts' patterns in the e2e script.

## Order of work

1. Copy both suites into the SDEF, with placeholder handlers.
2. Fixture tooling: CFRef mapping, unordered record comparison.
3. Record SatimageOSAX fixtures; settle the behaviors above.
4. The node tree, conversions and document store; `PlistNew`, `PlistOpen`, `PlistClose`, `PlistSave`, `PlistGet`, `PlistSet` (your scripts' commands).
5. The other reading and changing commands, and paths.
6. Pools and IDs.
7. JSON.
8. `filter text … into` a CFRef.
9. Anything Satimage gets wrong: implement from the documentation, record from MTC_OSAX into `…Fixes` fixture folders, and list it in this plan.
10. End-to-end and parity scripts.

## Done when

- [x] All 32 commands implemented, and `filter text … into` a CFRef; SDEF consistency tests pass.
- [x] SatimageOSAX fixtures for every command and parameter replay without differences; every deviation listed here with MTC_OSAX fixtures.
- [x] Unit tests for every command, including error cases.
- [x] `Scripts/e2e/plists.applescript` passes, and `Scripts/parity.sh` shows no differences for shared behavior.

## Decisions

Made 2026-09-28:

1. MTC_OSAX doesn't quit for being idle while any document is open (a script that never calls `PlistClose` keeps it running until it's quit).
2. `PlistToJSON … replacer` is supported through JavaScriptCore.
3. The idle timeout is a preference (`IdleTimeoutSeconds`, in seconds; 0 means never quit), reread each time the countdown starts. Done on this branch at your request.

## Findings during implementation

Recorded from SatimageOSAX in `Fixtures/PropertyLists` (241 cases, generated by `generate.py` there, with input files from `make_inputs.py`), all replaying without differences:

- **Recording.** A `using` path with a trailing slash (`"dict/"`) left SatimageOSAX failing every later property list command with -10004 until it was relaunched; the first recording was invalid from there on and was redone.
- **Key order.** Dictionaries come out in Core Foundation's hashing order (in `PlistGet` records, `PlistChild` lists and JSON). MTC_OSAX keeps each dictionary's keys in an `NSMutableDictionary`, copied rather than rebuilt, which gives the same order. Fixture replays compare records regardless of order anyway.
- **References.** SatimageOSAX's CFRefs were pointers; equal small numbers shared one (Core Foundation caches them). Replays map recorded CFRefs to MTC_OSAX's and match references loosely.
- **Values.** `PlistType` names are `dictionary`, `array`, `string`, `integer`, `real`, `boolean`, `date` and `base64`. Values with no property list type (aliases, file references, `missing value`, data, classes) are stored as the flattened descriptor (`dle2`, byte for byte as SatimageOSAX made it) and come back as the value; other data comes back as text of its bytes, or as the `as` type. Record keywords become keys like `«class pnam»`. `without typed` stores a value's raw bytes for `PlistSet`/`PlistNewChild`.
- **Selectors.** `index` works on arrays and `key` on dictionaries (else -1); a list of keys works, a list of indices doesn't; no selector means every child. A missing key is -1728 with `key`, -2763 at the end of a `using` path and -1 in the middle of one. Paths have no escaping.
- **Changes.** `PlistSet … to` a CFRef copies; indices go up to count + 1; with a list of keys, `missing value` removes the key. `PlistRemoveChild` ignores keys and indices that aren't there. `PlistAdd` merges dictionaries like AppleScript's `&` (`after` keeps the target's values).
- **Files.** `PlistSave` saves the whole document (whichever element is given), in its own format unless `binary` is given, to `in` or the file it came from (-1701 for a new document). `PlistURL` gives a POSIX path, or a percent-encoded file URL `as text`; -2763 without a file.
- **Documents.** `PlistRetain` really retains: a retained document needs two `PlistClose`s. `PlistGetDocByID` finds the first document with the ID in the pool. `DeletePool` without a name deletes the current pool.
- **JSON** is JavaScriptCore's `JSON.stringify` (with tab indentation for `formatting`) and `JSON.parse` (every number a real).

## Fixing Satimage's bugs

Recorded from MTC_OSAX in `Fixtures/PropertyListsFixes` (which share `PropertyLists/Input`), with unit tests and `Scripts/e2e/plists-fixes.applescript`:

| Area | Satimage | MTC_OSAX |
|---|---|---|
| `using` path ending in `/` | Returned nothing, then failed every property list command (-10004) | The slash is ignored |
| Integers beyond 32 bits | `PlistGet` returned 0 | Reals |
| A removed element's CFRef | Returned nothing | Error -1728, as for a closed document |
| `PlistSave … in` a POSIX path | Error -1 | Saves |
| `PlistToJSON` with dates or data | Returned nothing | Dates as ISO 8601 text, data as base64 text |
| `PlistFromJSON` with `null` | Made a property list that couldn't be read | `missing value` |
| `PlistSet` a list of keys with `missing value`, `without suppressing` | Ignored the key | Stores `missing value` |
| `PlistNew … without typed` | Ignored | Stores each value inside as its raw bytes, as `PlistSet` does (decided 2026-09-28); booleans as one byte, since `true` and `false` have no bytes of their own |
| `filter text … into` a CFRef | `filter text` never worked (-1708) | Adds the keys to the dictionary |
