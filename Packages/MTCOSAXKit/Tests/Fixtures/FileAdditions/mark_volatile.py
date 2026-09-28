# After recording: replaces values that depend on the machine or the moment with {"type": "any"}, which replays
# accept for any value: the dates and default application in `URL info for` records.
# Run: python3 mark_volatile.py [folder]   (default: this folder; also run it on ../FileAdditionsFixes)
import glob, json, os, sys
os.chdir(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
VOLATILE = {"ascd", "asmo", "asda"}
def mark(value):
    changed = False
    for field in value.get("fields", []):
        if field["key"] in VOLATILE and field["value"] != {"type": "any"}:
            field["value"] = {"type": "any"}
            changed = True
        changed |= mark(field["value"])
    for item in value.get("items", []):
        changed |= mark(item)
    return changed
count = 0
for path in glob.glob("*.json"):
    if path == "cases.json":
        continue
    fixture = json.load(open(path))
    if any(mark(exchange["reply"].get("result", {})) for exchange in fixture["exchanges"]):
        json.dump(fixture, open(path, "w"), indent=2, sort_keys=True, ensure_ascii=False)
        count += 1
print(count, "fixtures marked")
