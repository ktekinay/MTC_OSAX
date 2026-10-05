-- Opens every File Additions dialog, one after another, and prints what each returned, so the dialogs can be
-- checked by hand against the dictionary (SatimageOSAX's never worked: they all reply -1708). Each dialog's prompt says what to do. Run with Scripts/manual/dialogs.sh.

use AppleScript version "2.4"
use application "MTC_OSAX"

property results : {}

on report(label, value)
	try
		set AppleScript's text item delimiters to ", "
		if class of value is list then
			set shown to {}
			repeat with anItem in value
				set end of shown to POSIX path of anItem
			end repeat
			set value to "{" & (shown as text) & "}"
		else if class of value is not integer and class of value is not text then
			set value to POSIX path of value
		end if
		set end of results to label & ": " & value
	on error message
		set end of results to label & ": (" & message & ")"
	end try
end report

on run
	set folder to POSIX file "/Applications/"
	with timeout of 600 seconds
		try
			report("navchoose file", (navchoose file with prompt "1. Choose two files (multiple selection)" starting at folder))
		on error message number n
			report("navchoose file", "error " & n)
		end try
		try
			report("navchoose file single", (navchoose file with prompt "2. Only .txt and .md files can be chosen; choose one" of extension {"txt", "md"} without multiple files))
		on error message number n
			report("navchoose file single", "error " & n)
		end try
		try
			report("navchoose file packages", (navchoose file with prompt "3. Applications can't be chosen (show packages false); click Cancel" starting at folder without show packages))
		on error message number n
			report("navchoose file packages", "error " & n)
		end try
		try
			report("navchoose folder", (navchoose folder with prompt "4. Choose a folder; remember it with key 42" key 42))
		on error message number n
			report("navchoose folder", "error " & n)
		end try
		try
			report("navchoose folder key", (navchoose folder with prompt "5. This should start next to the folder from step 4" key 42))
		on error message number n
			report("navchoose folder key", "error " & n)
		end try
		try
			report("navchoose object", (navchoose object with prompt "6. Choose a file or a folder" with open packages))
		on error message number n
			report("navchoose object", "error " & n)
		end try
		try
			report("navchoose volume", (navchoose volume with prompt "7. Choose a volume"))
		on error message number n
			report("navchoose volume", "error " & n)
		end try
		try
			report("navchoose file name", (navchoose file name with prompt "8. Save as (nothing is created)" default name "Untitled.txt" with menu {"Plain text", "Rich text"} menu index 2))
		on error message number n
			report("navchoose file name", "error " & n)
		end try
		try
			report("navnew folder", (navnew folder with prompt "9. Name a new folder (nothing is created)"))
		on error message number n
			report("navnew folder", "error " & n)
		end try
		try
			report("navask save closing", (navask save file name "Report.txt" action 1))
		on error message number n
			report("navask save closing", "error " & n)
		end try
		try
			report("navask save quitting", (navask save file name "Report.txt" action 2))
		on error message number n
			report("navask save quitting", "error " & n)
		end try
		try
			report("navask save", (navask save))
		on error message number n
			report("navask save", "error " & n)
		end try
		try
			report("navchoose file canceled", (navchoose file with prompt "13. Click Cancel"))
		on error message number n
			report("navchoose file canceled", "error " & n)
		end try
	end timeout
	set AppleScript's text item delimiters to linefeed
	return results as text
end run
