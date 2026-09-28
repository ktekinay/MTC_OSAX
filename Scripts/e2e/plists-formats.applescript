-- End-to-end checks of PlistToYAML, PlistFromYAML, PlistToTOML and PlistFromTOML (see Implemented/PLAN-YAMLTOML.md).
-- MTC_OSAX only. Run with Scripts/run-e2e.sh plists-formats (through iTerm).

use AppleScript version "2.4"
use application "MTC_OSAX"

property checks : 0

on check(label, actual, expected)
	set checks to checks + 1
	if actual is not expected then error label & ": expected " & my show(expected) & ", got " & my show(actual)
end check

on show(value)
	try
		return value as text
	on error
		return "(" & (class of value as text) & ")"
	end try
end show

on errorNumber(yamlOrToml, sourceText)
	try
		if yamlOrToml is "YAML" then
			PlistFromYAML sourceText
		else
			PlistFromTOML sourceText
		end if
	on error number n
		return n
	end try
	return 0
end errorNumber

-- TOML
set p to PlistNew {person:"Ann", address:{city:"Paris"}}
set toml to PlistToTOML p
check("toml table", toml contains "[address]" & linefeed & "city = \"Paris\"", true)
check("toml key", toml contains "person = \"Ann\"", true)
set q to PlistFromTOML toml
check("toml round trip", PlistEqual p to q, true)
PlistClose q
PlistClose p

set p to PlistNew {a:1, phone:missing value}
check("toml missing value", PlistToTOML p, "a = 1" & linefeed & "# phone = NULL" & linefeed)
PlistClose p
set p to PlistFromTOML "when = 2026-09-28T10:30:00-04:00" & linefeed & "time = 14:30:00"
check("toml offset date", PlistToJSON p, "{\"when\":\"2026-09-28T14:30:00Z\",\"time\":\"14:30:00\"}")
PlistClose p
check("toml invalid", errorNumber("TOML", "a = "), -1)

-- YAML
set p to PlistNew {person:"Ann", sample:{"a", "b"}}
set yaml to PlistToYAML p
check("yaml sequence", yaml contains "sample:" & linefeed & "- a" & linefeed & "- b", true)
set q to PlistFromYAML yaml
check("yaml round trip", PlistEqual p to q, true)
PlistClose q
PlistClose p
set p to PlistFromYAML "country: no" & linefeed & "ok: true" & linefeed & "nothing: null" in pool "mtc-e2e-yaml"
check("yaml 1.2 no", PlistGet (PlistChild p key "country"), "no")
check("yaml true", PlistGet (PlistChild p key "ok"), true)
check("yaml null", PlistGet (PlistChild p key "nothing"), missing value)
check("pool", GetPool p, "mtc-e2e-yaml")
DeletePool "mtc-e2e-yaml"
check("yaml documents", errorNumber("YAML", "a: 1" & linefeed & "---" & linefeed & "b: 2"), -50)

-- Files, JSON included
set p to PlistNew {person:"Ann", sample:{1, 2}}
PlistToJSON p in (POSIX file "/private/tmp/mtc-e2e-formats.json")
PlistToYAML p in "/private/tmp/mtc-e2e-formats.yaml"
PlistToTOML p in (POSIX file "/private/tmp/mtc-e2e-formats.toml")
set q to PlistFromJSON (POSIX file "/private/tmp/mtc-e2e-formats.json")
check("json file", PlistEqual p to q, true)
PlistClose q
set q to PlistFromYAML (POSIX file "/private/tmp/mtc-e2e-formats.yaml")
check("yaml file", PlistEqual p to q, true)
PlistClose q
set q to PlistFromTOML (POSIX file "/private/tmp/mtc-e2e-formats.toml")
check("toml file", PlistEqual p to q, true)
PlistClose q
PlistClose p
check("text is never a path", errorNumber("TOML", "/private/tmp/mtc-e2e-formats.toml"), -1)

"OK: " & checks & " checks passed"
