# Check the helpers of the script (its section Helpers): pure functions.

function test_max_min() {
  check("max: second is larger", max(1, 2), 2)
  check("max: first is larger", max(1, -3), 1)
  check("min: first is smaller", min(1, 2), 1)
  check("min: second is smaller", min(1, -3), -3)
}

function test_text_length() {
  check("text_length: ASCII", text_length("abc"), 3)
  check("text_length: empty", text_length(""), 0)
  check("text_length: an accented letter is one character", text_length("d\303\251ployer"), 8)
  check("text_length: a Japanese character is one character",
        text_length("\343\203\223\343\203\253\343\203\211"), 3)
}

function test_repeated_string() {
  check("repeated_string: a character", repeated_string("a", 4), "aaaa")
  check("repeated_string: a string", repeated_string("ab", 2), "abab")
  check("repeated_string: an empty string", repeated_string("", 5), "")
  check("repeated_string: zero times", repeated_string("a", 0), "")
  check("spaces", spaces(3), "   ")
}

function test_array_length(arr) { #locals
  check("array_length: empty array", array_length(arr), 0)

  arr["k1"] = "this"
  arr["k2"] = "is"
  arr["k3"] = "a"
  arr["k4"] = "test"
  check("array_length: 4 elements", array_length(arr), 4)
}

function test_array_get(arr) { #locals
  arr["k"] = "value"
  arr["empty"] = ""
  check("array_get: existing key", array_get(arr, "k"), "value")
  check("array_get: key with an empty value", array_get(arr, "empty"), "")
  check("array_get: missing key", array_get(arr, "missing"), "")
  check_true("array_get: a missing key is not created", !("missing" in arr))
  check("array_get: the array is unchanged", array_length(arr), 2)
}

function test_join(arr, n) { #locals
  n = split("this is another test", arr, " ")
  check("join: colon delimiter", join(arr, n, ":"), "this:is:another:test")

  split("", arr)
  arr[1] = "first line"
  check("join: one element", join(arr, 1, "\n"), "first line")
  arr[2] = "   second line"
  arr[3] = "\t last line  "
  check("join: lines joined with newlines (spaces kept)",
        join(arr, 3, "\n"), "first line\n   second line\n\t last line  ")
  check("join: only the elements 1..n", join(arr, 2, "|"), "first line|   second line")
  arr["other"] = "x"
  check("join: other keys are ignored", join(arr, 1, "|"), "first line")
  split("", arr)
  check("join: empty array", join(arr, 0, "\n"), "")
}

function test_string_replace(text, parts) { #locals
  text = "this is my text and this also is text not end"
  check("string_replace: two matches in the middle",
        string_replace("text", "X", text),
        "this is my X and this also is X not end")
  check("string_replace: matches at the start",
        string_replace("this", "X", text),
        "X is my text and X also is text not end")
  check("string_replace: match at the end",
        string_replace("end", "X", text),
        "this is my text and this also is text not X")
  # a "0" from split() looks like a number: it is false in a condition, but not empty
  split("0", parts, ";")
  check("string_replace: a search string of 0 (from split) is replaced",
        string_replace(parts[1], "X", "a0b0"),
        "aXbX")
  # many occurrences (a recursive implementation exhausts the stack of mawk at about 200)
  check("string_replace: 1000 occurrences",
        string_replace(" ", ".", spaces(1000)),
        repeated_string(".", 1000))
  check("string_replace: the replacement is not searched again",
        string_replace("a", "aa", "a-a"), "aa-aa")
  check("string_replace: overlapping occurrences are replaced from the left",
        string_replace("aa", "b", "aaa"), "ba")
  check("string_replace: empty search string changes nothing",
        string_replace("", "X", text),
        text)
  check("string_replace: empty replacement",
        string_replace("this", "", text),
        " is my text and  also is text not end")

  check("string_replace: no regex interpretation of $(VAR)",
        string_replace("$(VAR)", "VALUE", "this is my $(VAR) and this also is $(VAR) not end"),
        "this is my VALUE and this also is VALUE not end")
  check("string_replace: inner reference of a nested one",
        string_replace("$(NESTED)", "VAR", "nested vars $($(NESTED)) end"),
        "nested vars $(VAR) end")
  check("string_replace: reference left by the previous replacement",
        string_replace("$(VAR)", "VAL", "nested vars $(VAR) end"),
        "nested vars VAL end")
}

function test_strip_trailing_blanks() {
  check("strip_trailing_blanks: nothing to strip", strip_trailing_blanks("a b\n c\n"), "a b\n c\n")
  check("strip_trailing_blanks: empty text", strip_trailing_blanks(""), "")
  check("strip_trailing_blanks: spaces before a newline",
        strip_trailing_blanks("a  \nb\n"), "a\nb\n")
  check("strip_trailing_blanks: tabs before a newline",
        strip_trailing_blanks("a\t\t\nb\n"), "a\nb\n")
  check("strip_trailing_blanks: spaces and tabs mixed", strip_trailing_blanks("a \t \n"), "a\n")
  check("strip_trailing_blanks: blanks at the end of the text (no final newline)",
        strip_trailing_blanks("a\nb  "), "a\nb")
  check("strip_trailing_blanks: every line", strip_trailing_blanks("a \nb \nc \n"), "a\nb\nc\n")
  check("strip_trailing_blanks: a line with only blanks becomes empty",
        strip_trailing_blanks("a\n   \nb\n"), "a\n\nb\n")
  check("strip_trailing_blanks: leading and inner blanks are kept",
        strip_trailing_blanks("  a  b  \n"), "  a  b\n")
  check("strip_trailing_blanks: empty lines are kept",
        strip_trailing_blanks("a \n\n\nb\n"), "a\n\n\nb\n")
}

function test_strip_blanks() {
  check("strip_blanks: spaces",
        strip_blanks("   a test string   "), "a test string")
  check("strip_blanks: spaces and tabs",
        strip_blanks(" \t   a test string \t   "), "a test string")
}

function test_is_bool_is_hex_color() {
  check_true("is_bool: 0", is_bool(0))
  check_true("is_bool: 1", is_bool("1"))
  check_true("is_bool: 2", !is_bool(2))
  check_true("is_bool: empty", !is_bool(""))
  check_true("is_bool: text", !is_bool("yes"))
  check_true("is_hex_color: lower case", is_hex_color("7c3f00"))
  check_true("is_hex_color: upper case", is_hex_color("AABBCC"))
  check_true("is_hex_color: 3 digits", !is_hex_color("fff"))
  check_true("is_hex_color: leading #", !is_hex_color("#7c3f00"))
  check_true("is_hex_color: not hex", !is_hex_color("00000g"))
  check_true("is_hex_color: empty", !is_hex_color(""))
}

function test_has_odd_terminal_backslashes() {
  check("has_odd_terminal_backslashes: none", has_odd_terminal_backslashes("abc"), 0)
  check("has_odd_terminal_backslashes: empty string", has_odd_terminal_backslashes(""), 0)
  check("has_odd_terminal_backslashes: only a backslash", has_odd_terminal_backslashes("\\"), 1)
  check("has_odd_terminal_backslashes: one", has_odd_terminal_backslashes("abc\\"), 1)
  check("has_odd_terminal_backslashes: two", has_odd_terminal_backslashes("abc\\\\"), 0)
  check("has_odd_terminal_backslashes: three", has_odd_terminal_backslashes("abc\\\\\\"), 1)
  check("has_odd_terminal_backslashes: only the trailing run counts",
        has_odd_terminal_backslashes("a\\ \\"), 1)
  check("has_odd_terminal_backslashes: not at the end",
        has_odd_terminal_backslashes("a\\ b"), 0)
}


function test_or_list() {
  check("or_list: one word", or_list("a"), "a")
  check("or_list: two words", or_list("a b"), "a or b")
  check("or_list: three words", or_list("ANSI HTML LATEX"), "ANSI, HTML or LATEX")
}

BEGIN {
  test_or_list()
  test_max_min()
  test_text_length()
  test_repeated_string()
  test_array_length()
  test_array_get()
  test_join()
  test_string_replace()
  test_strip_blanks()
  test_strip_trailing_blanks()
  test_is_bool_is_hex_color()
  test_has_odd_terminal_backslashes()
  done()
}
