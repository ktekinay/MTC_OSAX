# After recording: the numbers from randomarray without a seed can't be reproduced, so for cases marked "random"
# in cases.json, replaces each number in the last reply with {"type": "any"}; replays then check only how many
# there are. (Their range is checked by unit tests.) Run: python3 mark_random.py
import json, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
for case in json.load(open("cases.json")):
    if not case.get("random") or not os.path.exists(case["name"] + ".json"):
        continue
    fixture = json.load(open(case["name"] + ".json"))
    result = fixture["exchanges"][-1]["reply"]["result"]
    result["items"] = [{"type": "any"} for _ in result["items"]]
    json.dump(fixture, open(case["name"] + ".json", "w"), indent=2, sort_keys=True, ensure_ascii=False)
    print("marked", case["name"], len(result["items"]), "numbers")
