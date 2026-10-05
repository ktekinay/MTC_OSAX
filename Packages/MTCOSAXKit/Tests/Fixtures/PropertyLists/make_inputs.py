# Writes the property list files in Input/ that the cases open. Run: python3 make_inputs.py
import datetime, os, plistlib
os.makedirs("Input", exist_ok=True)
simple = {
    "name": "Simple", "count": 3, "ratio": 2.5, "enabled": True, "disabled": False,
    "when": datetime.datetime(2020, 5, 17, 12, 30, 0),
    "blob": b"\x00\x01\x02hello",
    "list": ["a", 1, 2.5, True, {"nested": "yes"}],
    "dict": {"x": 1, "y": {"z": "deep"}, "empty": {}},
    "emptyList": [],
    "emptyText": "",
    "unicode": "café ☃",
    "people": [{"first": "Ann", "age": 30}, {"first": "Bob", "age": 40}, {"first": "Cy", "age": 30, "pet": "cat"}],
}
with open("Input/simple.plist", "wb") as f:
    plistlib.dump(simple, f, fmt=plistlib.FMT_XML, sort_keys=True)
with open("Input/binary.plist", "wb") as f:
    plistlib.dump(simple, f, fmt=plistlib.FMT_BINARY, sort_keys=True)
with open("Input/array.plist", "wb") as f:
    plistlib.dump([1, "two", {"three": 3}], f, fmt=plistlib.FMT_XML)
with open("Input/keys.plist", "wb") as f:
    plistlib.dump({"a/b": 1, "c[1]": 2, "": 3, "sp ace": 4, "nest": {"a/b": {"c": 5}}}, f, fmt=plistlib.FMT_XML)
with open("Input/big.plist", "wb") as f:
    plistlib.dump({"big": 2**40, "neg": -5, "small": 1e-300, "huge": 1e300}, f, fmt=plistlib.FMT_XML)
with open("Input/invalid.plist", "w") as f:
    f.write("this is not a property list\n")
with open("Input/prefs.plist", "wb") as f:
    plistlib.dump({"String_Utils_Script_Path": "/Users/me/Library/Scripts/String Utils.scpt"}, f, fmt=plistlib.FMT_XML)
with open("Input/messages.plist", "wb") as f:
    plistlib.dump({"MessageList": [{"id": 1, "subject": "Hi"}, {"id": 2, "subject": "Spam"}]}, f, fmt=plistlib.FMT_XML)
print(sorted(os.listdir("Input")))
