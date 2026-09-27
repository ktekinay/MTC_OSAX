# Generates cases.json for the Files and folders and Symlink suites, recorded from SatimageOSAX.
# Every case works in its own folder, $TMP/<case>, and creates what it needs with recorded commands
# (mkdir with a file reference, writetext), so replays rebuild the same setup. Run: python3 generate.py
import json

cases, names = [], set()
def case(name, *lines):
    assert name.lower() not in names, name
    names.add(name.lower())
    home = f'POSIX file "$TMP/{name}"'
    setup = f'mkdir ({home})'
    body = "\n".join(line.replace("@", f"$TMP/{name}") for line in lines)
    cases.append({"name": name, "script": setup + "\n" + body})

F = lambda path: f'(POSIX file "@/{path}")'           # a file reference
A = lambda path: f'(POSIX file "@/{path}" as alias)'  # an alias
S = lambda path: f'"@/{path}"'                         # a POSIX path string
make = lambda path, text="x": f'writetext "{text}" to {F(path)}'
exists = lambda path: f'readtext {F(path)}'            # error -43 if missing

# filegetname
case("getname-file", make("a.txt"), f"filegetname {F('a.txt')}")
case("getname-alias", make("a.txt"), f"filegetname {A('a.txt')}")
case("getname-string", make("a.txt"), f"filegetname {S('a.txt')}")
case("getname-url", make("a.txt"), 'filegetname "file://@/a.txt"')
case("getname-hfs", make("a.txt"), f"filegetname ({F('a.txt')} as text)")
case("getname-folder", f"mkdir {F('sub')}", f"filegetname {F('sub')}")
case("getname-folder-slash", f"mkdir {F('sub')}", f"filegetname {S('sub/')}")
case("getname-list", make("a.txt"), make("b.txt"), f"filegetname {{{F('a.txt')}, {S('b.txt')}}}")
case("getname-missing-file", f"filegetname {S('nope.txt')}")
case("getname-no-parameter", "filegetname")
case("getname-tilde", 'filegetname "~/Library"')

# filenew
case("new-file", f"filenew {F('n.txt')}", exists("n.txt"))
case("new-string", f"filenew {S('n.txt')}")
case("new-alias-folder-name", f"filenew {A('')} name \"n.txt\"", exists("n.txt"))
case("new-string-folder-name", f"filenew {S('')} name \"n.txt\"")
case("new-file-folder-name", f"filenew {F('')} name \"n.txt\"", exists("n.txt"))
case("new-existing", make("n.txt"), f"filenew {F('n.txt')}")
case("new-missing-folder", f"filenew {F('a/b/n.txt')}")
case("new-recursively", f"filenew {F('a/b/n.txt')} with recursively", exists("a/b/n.txt"))
case("new-recursively-false", f"filenew {F('a/n.txt')} without recursively")
case("new-no-parameter", "filenew")

# mkdir
case("mkdir-file", f"mkdir {F('d')}", f"filegetname {F('d')}")
case("mkdir-string", f"mkdir {S('d')}")
case("mkdir-alias-parent-name", f"mkdir {A('')} name \"d\"")
case("mkdir-string-parent-name", f"mkdir {S('')} name \"d\"")
case("mkdir-existing", f"mkdir {F('d')}", f"mkdir {F('d')}")
case("mkdir-nested-default", f"mkdir {F('a/b/c')}")
case("mkdir-nested-not-recursive", f"mkdir {F('a/b/c')} without recursively")
case("mkdir-existing-nested", f"mkdir {F('a/b')}", f"mkdir {F('a/b')}")
case("mkdir-existing-nested-deep", f"mkdir {F('a/b/c')}", f"mkdir {F('a/b/c')}")
case("mkdir-existing-nested-not-recursive", f"mkdir {F('a/b')}", f"mkdir {F('a/b')} without recursively")
case("mkdir-existing-not-recursive", f"mkdir {F('a')}", f"mkdir {F('a')} without recursively")
case("mkdir-existing-string", f"mkdir {F('a')}", f"mkdir {S('a')}")
case("mkdir-existing-name", f"mkdir {F('a')}", f"mkdir {F('')} name \"a\"")
case("mkdir-over-file", make("f"), f"mkdir {F('f')}")

# filerename
case("rename-file", make("a.txt"), f"filerename {F('a.txt')} to \"b.txt\"", exists("b.txt"))
case("rename-string", make("a.txt"), f"filerename {S('a.txt')} to \"b.txt\"")
case("rename-alias", make("a.txt"), f"filerename {A('a.txt')} to \"b.txt\"")
case("rename-folder", f"mkdir {F('d')}", f"filerename {F('d')} to \"e\"")
case("rename-existing-target", make("a.txt"), make("b.txt", "y"), f"filerename {F('a.txt')} to \"b.txt\"", exists("b.txt"))
case("rename-missing", f"filerename {F('nope.txt')} to \"b.txt\"")
case("rename-slash-in-name", make("a.txt"), f"filerename {F('a.txt')} to \"x/y.txt\"")
case("rename-no-to", make("a.txt"), f"filerename {F('a.txt')}")

# chmod
case("chmod-get", make("a.txt"), f"chmod {F('a.txt')} to \"644\"", f"chmod {F('a.txt')}")
case("chmod-get-string", make("a.txt"), f"chmod {F('a.txt')} to \"640\"", f"chmod {S('a.txt')}")
case("chmod-set-returns-previous", make("a.txt"), f"chmod {F('a.txt')} to \"644\"", f"chmod {F('a.txt')} to \"600\"", f"chmod {F('a.txt')}")
case("chmod-leading-zero", make("a.txt"), f"chmod {F('a.txt')} to \"0755\"", f"chmod {F('a.txt')}")
case("chmod-four-digits", make("a.txt"), f"chmod {F('a.txt')} to \"1755\"", f"chmod {F('a.txt')}")
case("chmod-invalid-text", make("a.txt"), f"chmod {F('a.txt')} to \"abc\"")
case("chmod-invalid-digit", make("a.txt"), f"chmod {F('a.txt')} to \"999\"")
case("chmod-folder", f"mkdir {F('d')}", f"chmod {F('d')} to \"755\"", f"chmod {F('d')}")
case("chmod-missing", f"chmod {F('nope.txt')}")
case("chmod-alias", make("a.txt"), f"chmod {F('a.txt')} to \"644\"", f"chmod {A('a.txt')}")

# filecopy
case("copy-to-folder", make("a.txt"), f"mkdir {F('d')}", f"filecopy {F('a.txt')} to {F('d')}", exists("d/a.txt"))
case("copy-string-to-string", make("a.txt"), f"mkdir {F('d')}", f"filecopy {S('a.txt')} to {S('d/')}")
case("copy-to-folder-no-slash", make("a.txt"), f"mkdir {F('d')}", f"filecopy {S('a.txt')} to {S('d')}")
case("copy-name", make("a.txt"), f"mkdir {F('d')}", f"filecopy {F('a.txt')} to {F('d')} name \"b.txt\"", exists("d/b.txt"))
case("copy-filepath", make("a.txt"), f"filecopy {F('a.txt')} filepath {F('b.txt')}", exists("b.txt"))
case("copy-into-legacy", make("a.txt"), f"filecopy {F('a.txt')} into {F('b.txt')}", exists("b.txt"))
case("copy-existing", make("a.txt"), make("b.txt", "y"), f"filecopy {F('a.txt')} filepath {F('b.txt')}", exists("b.txt"))
case("copy-replacing", make("a.txt"), make("b.txt", "y"), f"filecopy {F('a.txt')} filepath {F('b.txt')} with replacing", exists("b.txt"))
case("copy-list", make("a.txt"), make("b.txt"), f"mkdir {F('d')}", f"filecopy {{{F('a.txt')}, {F('b.txt')}}} to {F('d')}")
case("copy-list-with-name", make("a.txt"), make("b.txt"), f"mkdir {F('d')}", f"filecopy {{{F('a.txt')}, {F('b.txt')}}} to {F('d')} name \"c.txt\"")
case("copy-from-relative", make("a.txt"), f"mkdir {F('d')}", f"filecopy \"a.txt\" from {F('')} to {F('d')}")
case("copy-from-relative-list", make("a.txt"), make("b.txt"), f"mkdir {F('d')}", f"filecopy {{\"a.txt\", \"b.txt\"}} from {F('')} to {F('d')}")
case("copy-folder", f"mkdir {F('s')}", make("s/a.txt"), f"mkdir {F('d')}", f"filecopy {F('s')} to {F('d')}", exists("d/s/a.txt"))
case("copy-full-copy", make("a.txt"), f"filecopy {F('a.txt')} filepath {F('b.txt')} with full copy", exists("b.txt"))
case("copy-missing-source", f"mkdir {F('d')}", f"filecopy {F('nope.txt')} to {F('d')}")
case("copy-missing-destination", make("a.txt"), f"filecopy {F('a.txt')} to {F('nope')}")
case("copy-no-destination", make("a.txt"), f"filecopy {F('a.txt')}")
case("copy-alias", make("a.txt"), f"mkdir {F('d')}", f"filecopy {A('a.txt')} to {A('d')}")

# filemove
case("move-to-folder", make("a.txt"), f"mkdir {F('d')}", f"filemove {F('a.txt')} to {F('d')}", exists("d/a.txt"), exists("a.txt"))
case("move-name", make("a.txt"), f"mkdir {F('d')}", f"filemove {F('a.txt')} to {F('d')} name \"b.txt\"", exists("d/b.txt"))
case("move-filepath", make("a.txt"), f"filemove {F('a.txt')} filepath {F('b.txt')}", exists("b.txt"))
case("move-string", make("a.txt"), f"mkdir {F('d')}", f"filemove {S('a.txt')} to {S('d/')}")
case("move-existing", make("a.txt"), make("b.txt", "y"), f"filemove {F('a.txt')} filepath {F('b.txt')}", exists("b.txt"))
case("move-replacing", make("a.txt"), make("b.txt", "y"), f"filemove {F('a.txt')} filepath {F('b.txt')} with replacing", exists("b.txt"))
case("move-list", make("a.txt"), make("b.txt"), f"mkdir {F('d')}", f"filemove {{{F('a.txt')}, {F('b.txt')}}} to {F('d')}")
case("move-from-relative", make("a.txt"), f"mkdir {F('d')}", f"filemove \"a.txt\" from {F('')} to {F('d')}")
case("move-folder", f"mkdir {F('s')}", make("s/a.txt"), f"mkdir {F('d')}", f"filemove {F('s')} to {F('d')}", exists("d/s/a.txt"))
case("move-missing-source", f"mkdir {F('d')}", f"filemove {F('nope.txt')} to {F('d')}")

# fileremove
case("remove-file", make("a.txt"), f"fileremove {F('a.txt')}", exists("a.txt"))
case("remove-string", make("a.txt"), f"fileremove {S('a.txt')}", exists("a.txt"))
case("remove-list", make("a.txt"), make("b.txt"), f"fileremove {{{F('a.txt')}, {F('b.txt')}}}", exists("b.txt"))
case("remove-from-relative", make("a.txt"), f"fileremove \"a.txt\" from {F('')}", exists("a.txt"))
case("remove-folder", f"mkdir {F('d')}", make("d/a.txt"), f"fileremove {F('d')}", f"filegetname {F('d')}", exists("d/a.txt"))
case("remove-filesonly", f"mkdir {F('d')}", make("d/a.txt"), f"mkdir {F('d/e')}", make("d/e/b.txt"), f"fileremove {F('d')} with filesonly", exists("d/a.txt"), exists("d/e/b.txt"), f"filegetname {F('d/e')}")
setup_tree = [f"mkdir {F('d')}", make("d/a.txt"), f"mkdir {F('d/e')}", make("d/e/b.txt")]
case("remove-filesonly-subfolder-file", *setup_tree, f"fileremove {F('d')} with filesonly", exists("d/e/b.txt"))
case("remove-filesonly-keeps-subfolder", *setup_tree, f"fileremove {F('d')} with filesonly", f"mkdir {F('d/e')}")
case("remove-filesonly-keeps-folder", *setup_tree, f"fileremove {F('d')} with filesonly", f"mkdir {F('d')}")
case("remove-filesonly-file", make("a.txt"), f"fileremove {F('a.txt')} with filesonly", exists("a.txt"))
case("remove-folder-gone", f"mkdir {F('d')}", make("d/a.txt"), f"fileremove {F('d')}", f"mkdir {F('d')}")
case("remove-filesonly-after", f"mkdir {F('d')}", make("d/a.txt"), f"fileremove {F('d')} with filesonly after date \"Saturday, January 1, 2000 at 12:00:00 AM\"", exists("d/a.txt"))
case("remove-filesonly-before", f"mkdir {F('d')}", make("d/a.txt"), f"fileremove {F('d')} with filesonly before date \"Saturday, January 1, 2000 at 12:00:00 AM\"", exists("d/a.txt"))
case("remove-after-without-filesonly", make("a.txt"), f"fileremove {F('a.txt')} after date \"Saturday, January 1, 2000 at 12:00:00 AM\"")
case("remove-missing", f"fileremove {F('nope.txt')}")
case("remove-no-parameter", "fileremove")

# mkstemp, mkdtemp (random names: one event each, compared by pattern)
case("mkstemp-folder-name", f"mkstemp {F('')} name \"tmp.txt\" suffix 4")
case("mkstemp-string", f"mkstemp {S('')} name \"tmp.txt\" suffix 4")
case("mkstemp-path", f"mkstemp {F('tmp')}")
case("mkstemp-wildcards", f"mkstemp {F('')} name \"t\" wildcards 3")
case("mkstemp-mode", f"mkstemp {F('')} name \"t\" mode \"600\"")
case("mkdtemp-folder-name", f"mkdtemp {F('')} name \"dir\"")
case("mkdtemp-string", f"mkdtemp {S('')} name \"dir\"")
case("mkdtemp-path", f"mkdtemp {F('dir')}")
case("mkdtemp-wildcards", f"mkdtemp {F('')} name \"d\" wildcards 8")

# create symlink, testsymlink, readlink
case("symlink-absolute", make("a.txt"), f"create symlink {S('a.txt')} in {F('')} name \"l\"", f"readlink {S('l')}", f"testsymlink {S('l')}")
case("symlink-relative", make("a.txt"), "create symlink \"a.txt\" in " + F('') + " name \"l\"", f"readlink {S('l')}")
case("symlink-default-name", f"mkdir {F('d')}", make("a.txt"), f"create symlink {S('a.txt')} in {F('d')}", f"readlink {S('d/a.txt')}")
case("symlink-file-target", make("a.txt"), f"create symlink {F('a.txt')} in {F('')} name \"l\"", f"readlink {S('l')}")
case("symlink-alias-target", make("a.txt"), f"create symlink {A('a.txt')} in {F('')} name \"l\"", f"readlink {S('l')}")
case("symlink-string-folder", make("a.txt"), f"create symlink \"a.txt\" in {S('')} name \"l\"", f"readlink {S('l')}")
case("symlink-replacing-default", make("a.txt"), make("b.txt"), f"create symlink \"a.txt\" in {F('')} name \"l\"", f"create symlink \"b.txt\" in {F('')} name \"l\"", f"readlink {S('l')}")
case("symlink-not-replacing", make("a.txt"), make("b.txt"), f"create symlink \"a.txt\" in {F('')} name \"l\"", f"create symlink \"b.txt\" in {F('')} name \"l\" without replacing")
case("symlink-over-file", make("a.txt"), make("l"), f"create symlink \"a.txt\" in {F('')} name \"l\"")
case("symlink-dangling", f"create symlink \"nope.txt\" in {F('')} name \"l\"", f"readlink {S('l')}", f"testsymlink {S('l')}")
case("testsymlink-file", make("a.txt"), f"testsymlink {S('a.txt')}")
case("testsymlink-folder", f"mkdir {F('d')}", f"testsymlink {S('d')}")
case("testsymlink-missing", f"testsymlink {S('nope')}")
case("testsymlink-url", make("a.txt"), "create symlink \"a.txt\" in " + F('') + " name \"l\"", 'testsymlink "file://@/l"')
case("testsymlink-file-reference", make("a.txt"), "create symlink \"a.txt\" in " + F('') + " name \"l\"", f"testsymlink {F('l')}")
case("readlink-not-a-link", make("a.txt"), f"readlink {S('a.txt')}")
case("readlink-missing", f"readlink {S('nope')}")
case("readlink-folder-link", f"mkdir {F('d')}", "create symlink \"d\" in " + F('') + " name \"l\"", f"readlink {S('l')}")

RANDOM = {
    "mkstemp-folder-name": ("tmp", 6, ".txt"), "mkstemp-string": ("tmp", 6, ".txt"), "mkstemp-path": ("tmp", 6, ""),
    "mkstemp-wildcards": ("t", 3, ""), "mkstemp-mode": ("t", 6, ""),
    "mkdtemp-folder-name": ("dir", 6, "/"), "mkdtemp-string": ("dir", 6, "/"), "mkdtemp-path": ("dir", 6, "/"),
    "mkdtemp-wildcards": ("d", 8, "/"),
}
for c in cases:
    if c["name"] in RANDOM:
        prefix, length, suffix = RANDOM[c["name"]]
        c["random"] = {"prefix": prefix, "length": length, "suffix": suffix}
# Where SatimageOSAX is broken, MTC_OSAX follows the dictionary; these cases are recorded from MTC_OSAX into
# ../FilesAndFoldersFixes instead.
MTC_OSAX_FIXES = {
    "getname-hfs": "Satimage: error 143 for an HFS path",
    "mkdtemp-wildcards": "Satimage ignored wildcards for folders (always 6)",
    "remove-filesonly": "Satimage reported 0 items removed with filesonly",
    "remove-filesonly-after": "Satimage reported 0 items removed with filesonly",
    "remove-filesonly-keeps-folder": "Satimage reported 0 items removed with filesonly",
    "remove-filesonly-keeps-subfolder": "Satimage reported 0, and then error 1 instead of 17 for the existing folder",
    "remove-filesonly-subfolder-file": "Satimage reported 0 items removed with filesonly",
}
assert MTC_OSAX_FIXES.keys() <= names
import os
os.makedirs("../FilesAndFoldersFixes", exist_ok=True)
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open("../FilesAndFoldersFixes/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
