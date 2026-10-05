# After recording: replaces the random part of mkstemp/mkdtemp results with {{random:N}}, which replays match
# against any N letters or digits. Uses the "random" hints in cases.json.
# Run: python3 mark_random.py [folder]   (default: this folder; also run it on ../FilesAndFoldersFixes)
import json, os, re, sys
os.chdir(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
for case in json.load(open("cases.json")):
    hint = case.get("random")
    if not hint or not os.path.exists(case["name"] + ".json"):
        continue
    fixture = json.load(open(case["name"] + ".json"))
    result = fixture["exchanges"][-1]["reply"].get("result")
    if not result or "text" not in result:
        continue
    pattern = re.escape(hint["prefix"]) + r"[A-Za-z0-9]+" + re.escape(hint["suffix"]) + "$"
    name_start = result["text"].rstrip("/").rfind("/") + 1
    tail = result["text"][name_start:]
    if not re.match(pattern, tail):
        print("unexpected name:", case["name"], tail)
        continue
    random_length = len(tail) - len(hint["prefix"]) - len(hint["suffix"])
    result["text"] = result["text"][:name_start] + hint["prefix"] + "{{random:%d}}" % random_length + hint["suffix"]
    json.dump(fixture, open(case["name"] + ".json", "w"), indent=2, sort_keys=True, ensure_ascii=False)
    print("marked", case["name"], result["text"][name_start:])
