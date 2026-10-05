# Generates cases.json: regex patterns covering as many Onigmo tokens as possible, each run with
# `find text … with regexp and all occurrences` (and `using` every group), recorded from SatimageOSAX.
# Run: python3 generate.py
import json

def applescript_string(text):
    """An AppleScript expression for `text`: quoted runs, with control and separator characters as (character id N)."""
    parts, run = [], ""
    for ch in text:
        code = ord(ch)
        if code < 32 or code == 127 or code in (0x85, 0x2028, 0x2029):
            if run: parts.append('"' + run + '"'); run = ""
            parts.append(f"(character id {code})")
        else:
            run += ch.replace("\\", "\\\\").replace('"', '\\"')
    if run or not parts: parts.append('"' + run + '"')
    return parts[0] if len(parts) == 1 else "(" + " & ".join(parts) + ")"

cases, names = [], set()
def case(name, pattern, text, groups=0, syntax=None, flags=None, case_insensitive=False):
    assert name.lower() not in names, name
    names.add(name.lower())
    script = f"find text {applescript_string(pattern)} in {applescript_string(text)} with regexp and all occurrences"
    if groups:
        script += " using {" + ", ".join(applescript_string("\\" + str(i)) for i in range(groups + 1)) + "}"
    if case_insensitive: script += " without case sensitive"
    if syntax: script += f' syntax "{syntax}"'
    if flags: script += " regexpflag {" + ", ".join(f'"{f}"' for f in flags) + "}"
    cases.append({"name": name, "script": script})

# --- Literals and escapes
case("escape-tab-newline-return", r"a\tb\nc\rd", "a\tb\nc\rd")
case("escape-formfeed-vtab-bell-escape", r"\f\v\a\e", "\f\v\a\x1b")
case("escape-octal", r"\101\0102", "AB\x082")
case("escape-hex", r"\x41\x{42}\x{1F600}", "AB😀")
case("escape-unicode-u", r"Aé", "Aé")
case("escape-control", r"\cA\C-b", "\x01\x02")
case("escape-meta-chars", r"\.\*\+\?\(\)\[\]\{\}\|\^\$\\\/", ".*+?()[]{}|^$\\/")
case("escape-unknown-letter", r"\y\q", "yq")
case("dot", r"a.c", "abc a\nc a😀c")
case("dot-multiline-flag", r"a.c", "a\nc", flags=["MULTILINE"])

# --- Character types
case("type-word", r"\w+", "ab_9 é ß 日本")
case("type-nonword", r"\W+", "ab_9 é-ß!")
case("type-space", r"\s+", "a \t\n\r\f\vb c d")
case("type-nonspace", r"\S+", "ab cd ef")
case("type-digit", r"\d+", "12 ٣٤ ３4")
case("type-nondigit", r"\D+", "a1b٣c")
case("type-hex", r"\h+", "0aF xyz 9G")
case("type-nonhex", r"\H+", "0aFxyz9G")
case("type-linebreak", r"\R", "a\r\nb\nc\rd e\x0bf")
case("type-grapheme", r"\X", "éa🇺🇸👍🏽")
case("prop-alpha", r"\p{Alpha}+", "abé1ß日")
case("prop-not-alpha", r"\p{^Alpha}+", "ab12cd")
case("prop-negated-P", r"\P{Digit}+", "ab12cd")
case("prop-script-greek", r"\p{Greek}+", "abc αβγ Ωmega")
case("prop-script-han", r"\p{Han}+", "日本語 かな")
case("prop-hiragana", r"\p{Hiragana}+", "日本語 かな カナ")
case("prop-category-lu", r"\p{Lu}+", "aBCdÉF")
case("prop-category-l", r"\p{L}+", "ab1é日")
case("prop-category-nd", r"\p{Nd}+", "a12٣b")
case("prop-category-p", r"\p{P}+", "a,b.!?c")
case("prop-emoji", r"\p{Emoji}", "a😀1#")
case("prop-any", r"\p{Any}", "a😀")
case("prop-ascii", r"\p{ASCII}+", "abcé")
case("prop-lower-case-name", r"\p{alpha}+", "ab1")
case("prop-unknown", r"\p{Nope}", "a")

# --- Anchors
case("anchor-caret-dollar-lines", r"^\w+$", "one\ntwo\rthree\r\nfour")
case("anchor-A-z-Z", r"\A\w+|\w+\z|\w+\Z", "first mid last\n")
case("anchor-Z-before-newline", r"last\Z", "first last\n")
case("anchor-z-strict", r"last\z", "first last\n")
case("anchor-G", r"\Ga", "aaab")
case("anchor-word-boundary", r"\bcat\b", "cat concat cat_ cat.")
case("anchor-nonword-boundary", r"\Bcat\B", "concats cat")
case("anchor-boundary-unicode", r"\b\w+\b", "é1 café")

# --- Bracket expressions
case("class-simple", r"[abc]+", "xabcabx")
case("class-negated", r"[^abc]+", "abxyzab")
case("class-range", r"[a-f0-3]+", "xyzabc0129")
case("class-escapes", r"[\]\\\-^]+", "a]\\-^b")
case("class-caret-not-first", r"[a^]+", "x^a^")
case("class-types-inside", r"[\w\s]+", "ab c!d")
case("class-hex-range", r"[\x41-\x43]+", "ABCD")
case("class-unicode-range", r"[à-ÿ]+", "aàéÿĀ")
case("class-posix-alpha", r"[[:alpha:]]+", "ab1é日")
case("class-posix-negated", r"[[:^digit:]]+", "a1b2")
case("class-posix-all", r"[[:alnum:]][[:punct:]][[:space:]][[:upper:]][[:lower:]][[:xdigit:]][[:cntrl:]][[:print:]][[:graph:]][[:blank:]][[:word:]]", "1! Ab\x01xy \x5f")
case("class-intersection", r"[a-z&&[^aeiou]]+", "aeibcdo")
case("class-nested", r"[a-c[x-z]]+", "abxyzm")
case("class-property-inside", r"[\p{Greek}\d]+", "αβ12a")
case("class-dash-first-last", r"[-a]+[b-]+", "-a-b-")
case("class-empty-negated-newline", r"a[^x]b", "a\nb a\rb ayb")
case("class-case-insensitive", r"[a-c]+", "ABCabc", case_insensitive=True)

# --- Quantifiers
case("quant-star-plus-question", r"ab*c+d?", "ac abbcc abccd")
case("quant-exact", r"a{3}", "aaaaaaa")
case("quant-at-least", r"a{2,}", "a aa aaaa")
case("quant-at-most", r"a{,2}", "aaaa")
case("quant-range", r"a{2,3}", "aaaaaaa")
case("quant-lazy", r"<.+?>", "<a><b>")
case("quant-lazy-star-question", r"a*?b|c??d", "aab cd d")
case("quant-lazy-range", r"a{2,4}?", "aaaaa")
case("quant-possessive", r"a++b|x*+x", "aab xxx")
case("quant-possessive-question", r"a?+a", "aa a")
case("quant-brace-literal", r"a{x}|a{", "a{x} a{")
case("quant-nested", r"(?:ab){2}(?:c|d)+", "ababcd abab")

# --- Groups
case("group-capture", r"(\w+)@(\w+)", "joe@example bob@host", groups=2)
case("group-noncapture", r"(?:a|b)(c)", "ac bc", groups=1)
case("group-named", r"(?<user>\w+)@(?<host>\w+)", "joe@example", groups=2)
case("group-named-quote", r"(?'user'\w+)@", "joe@", groups=1)
case("group-named-and-numbered", r"(?<n>a)(b)", "ab", groups=2)
case("group-unmatched-optional", r"(a)?(b)", "b ab", groups=2)
case("group-repeated-last-value", r"(\w)+", "abc", groups=1)
case("group-atomic", r"(?>a+)b|(?>a+)a", "aab aaa")
case("group-nested", r"((a)(b(c)))", "abc", groups=4)
case("group-alternation-empty", r"a(|b)c", "ac abc", groups=1)

# --- Lookaround
case("look-ahead", r"\w+(?=@)", "joe@x bob")
case("look-ahead-negative", r"\b\w+\b(?!@)", "joe@x bob")
case("look-behind", r"(?<=\$)\d+", "cost $42 or 7")
case("look-behind-negative", r"(?<!\$)\b\d+", "cost $42 or 7")
case("look-behind-alternatives", r"(?<=ab|x)c", "abc xc zc")
case("look-behind-variable-error", r"(?<=a+)b", "aab")
case("look-keep-K", r"foo\Kbar", "foobar")

# --- Backreferences
case("backref-number", r"(\w)\1", "aabbcd", groups=1)
case("backref-named", r"(?<c>\w)\k<c>", "xxyz", groups=1)
case("backref-named-quote", r"(?<c>\w)\k'c'", "zzy", groups=1)
case("backref-relative", r"(a)(b)\k<-1>\k<-2>", "abba", groups=2)
case("backref-case-insensitive", r"(a)\1", "aA", groups=1, case_insensitive=True)
case("backref-undefined-error", r"(a)\2", "aa")
case("backref-to-unmatched", r"(a)?b\1", "b ab aba")

# --- Subexpression calls and recursion
case("call-named", r"(?<d>\d)-\g<d>", "1-2 3-x")
case("call-number", r"(\d)-\g<1>", "1-2")
case("call-recursive-parens", r"(?<p>\((?:[^()]|\g<p>)*\))", "x(a(b)c)y()", groups=1)
case("call-whole-pattern", r"a\g<0>?b", "aaabbb ab")
case("call-relative", r"(a)\g<-1>", "aa")

# --- Conditionals
case("cond-number", r"(a)?(?(1)b|c)", "ab c xb")
case("cond-name", r"(?<q>\")?\w+(?(<q>)\")", "\"hi\" there \"x")

# --- Inline options and comments
case("option-i", r"(?i)abc", "ABC aBc")
case("option-i-scoped", r"a(?i:b)c", "aBc ABC")
case("option-i-off", r"(?i)a(?-i)b", "Ab AB")
case("option-m-dotall", r"(?m)a.b", "a\nb")
case("option-x", r"(?x) a  b # comment\n c", "abc")
case("option-comment", r"a(?#this is ignored)b", "ab")
case("option-x-escaped-r", r"(?x)a # c\rb", "ab acb")
case("option-x-escaped-t", r"(?x)a # c\tb", "ab acb")
case("option-x-real-newline", "(?x)a # c\nb", "ab acb")
case("option-x-real-return", "(?x)a # c\rb", "ab acb")
case("option-x-real-nel", "(?x)a # c\u0085b", "ab acb")
case("option-x-real-line-separator", "(?x)a # c\u2028b", "ab acb")
case("option-x-real-form-feed", "(?x)a # c\fb", "ab acb")
case("option-x-escaped-hash", r"(?x)a\#b", "a#b ab")
case("option-flag-extend", r"a b c", "abc", flags=["EXTEND"])
case("option-flag-singleline", r"^b$", "a\nb", flags=["SINGLELINE"])
case("option-flag-ignorecase", r"straße", "STRASSE Straße", flags=["IGNORECASE"])
case("option-flag-find-longest", r"a|ab|abc", "abc", flags=["FIND LONGEST"])
case("option-flag-dont-capture", r"(a)(?<n>b)", "ab", groups=1, flags=["DONT CAPTURE GROUP"])
case("option-absent", r"/\*(?~\*/)\*/", "/* a */ b */")

# --- Alternation and Unicode case folding
case("alternation-order", r"a|ab|abc", "abc")
case("alternation-empty-branch", r"a|", "ba")
case("fold-sharp-s", r"ß", "SS ss ß ẞ", case_insensitive=True)
case("fold-kelvin", r"k", "K k K", case_insensitive=True)
case("fold-greek-sigma", r"σ", "Σ σ ς", case_insensitive=True)
case("fold-dotless-i", r"i", "I ı İ", case_insensitive=True)

# --- Other syntaxes
case("perl-h-is-horizontal-space", r"a\hb", "a b a\tb", syntax="PERL")
case("perl-dollar-before-final-newline", r"b$", "a\nb\n", syntax="PERL")
case("perl-caret-single-line", r"^b", "a\nb", syntax="PERL")
case("perl-named-P", r"(?P<n>a)(?P=n)", "aa", syntax="PERL", groups=1)
case("perl-quote-QE", r"\Qa.b\E", "a.b axb", syntax="PERL")
case("java-possessive", r"a*+a", "aaa", syntax="JAVA")
case("java-class-intersection", r"[a-z&&[^b]]+", "abc", syntax="JAVA")
case("gnu-word-boundaries", r"\<ab\>", "ab abc", syntax="GNU_REGEX")
case("gnu-buffer-anchors", r"\`a|b\'", "ab", syntax="GNU_REGEX")
case("grep-groups-and-alternation", r"\(a\|b\)c", "ac bc cc", syntax="GREP", groups=1)
case("grep-plus-is-literal", r"a+", "aa a+", syntax="GREP")
case("grep-interval", r"a\{2\}", "aaa", syntax="GREP")
case("emacs-groups", r"\(ab\)+", "ababx", syntax="EMACS", groups=1)
case("emacs-word-boundaries", r"\bab\b", "ab cab", syntax="EMACS")
case("posix-basic-interval", r"a\{1,2\}b", "aab ab b", syntax="POSIX")
case("posix-basic-star-first-literal", r"*a", "*a a", syntax="POSIX")
case("posix-extended-alternation", r"(a|b)+c", "abac", syntax="POSIX_EXTENDED", groups=1)
case("posix-extended-no-lazy", r"a+?", "aa", syntax="POSIX_EXTENDED")

# --- Pathological and edge cases
case("empty-pattern-all", r"", "ab")
case("only-anchors", r"^$", "a\n\nb")
case("zero-width-lookahead-all", r"(?=a)", "aaa")
case("emoji-surrogates", r"😀+", "a😀😀b")
case("emoji-class", r"[😀-😂]+", "😀😁😂😃")
case("combining-mark", r"é", "caf" + "é")
case("long-alternation", r"(?:one|two|three|four|five|six|seven|eight|nine|ten)+", "onetwothreexfour")

# Cases where SatimageOSAX fails or uses outdated Unicode data (its Onigmo is from about 2013). MTC_OSAX's newer
# Onigmo is kept for these, so they're recorded from MTC_OSAX into TextAdditionsFixes/RegexTokens instead.
MTC_OSAX_FIXES = {
    "option-absent": "Satimage: error -119, the absent operator (?~…) didn't exist yet",
    "prop-emoji": "Satimage: error -223, no Emoji property in its Unicode data",
    "prop-lower-case-name": "Satimage: error -223, property names were case-sensitive",
    "type-grapheme": "Satimage: \\X matched single code points, splitting é, flags and skin tones",
    "type-linebreak": "Satimage: \\R didn't match U+2028 LINE SEPARATOR",
    "fold-sharp-s": "Satimage: case-insensitive ß didn't match capital ẞ (U+1E9E)",
}
assert MTC_OSAX_FIXES.keys() <= names
fixes_folder = "../../TextAdditionsFixes/RegexTokens"
import os
os.makedirs(fixes_folder, exist_ok=True)
json.dump([c for c in cases if c["name"] not in MTC_OSAX_FIXES], open("cases.json", "w"), indent=1, ensure_ascii=False)
json.dump([c for c in cases if c["name"] in MTC_OSAX_FIXES], open(f"{fixes_folder}/cases.json", "w"), indent=1, ensure_ascii=False)
print(len(cases) - len(MTC_OSAX_FIXES), "Satimage cases,", len(MTC_OSAX_FIXES), "MTC_OSAX fixes")
