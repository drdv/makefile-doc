# The parser redesign passes an untyped local array to a function that fills it (an awk
# function cannot return an array), possibly through a function that only passes it on.
# These checks confirm that every supported awk handles it. Temporary: to be removed when
# the new parser, which relies on it, has its own tests.

# The callers come before the functions that they call: it is the harder order for the awks
# that infer the types of the variables when they load the script.

function test_array_param_filled_two_calls_down(    facts) {
  arrays_forward(facts, "a b")
  check("array param: filled two calls down", length_array_posix(facts), 2)
  check("array param: the caller sees the values", facts["first"] "/" facts["count"], "a/2")
  check("array param: passed on to a function that reads it", arrays_read(facts), "a/2")
}

function test_array_param_fresh_at_each_call() {
  check("array param: a filled local (first call)", arrays_fill_once("x"), "2 x")
  check("array param: the local starts empty (second call)", arrays_fill_once(""), "0 ")
}

# a function whose local array is filled only when word is not empty
function arrays_fill_once(word, #locals
                          facts) {
  if (word != "") {
    arrays_forward(facts, word)
  }
  return length_array_posix(facts) " " array_get(facts, "first")
}

# only passes the array on: its type comes from the function that it calls
function arrays_forward(arr, words) {
  arrays_fill(arr, words)
}

function arrays_fill(arr, words, #locals
                     parts, n) {
  split("", arr)
  n = split(words, parts, " ")
  arr["first"] = parts[1]
  arr["count"] = n
}

function arrays_read(arr) {
  return arr["first"] "/" arr["count"]
}

BEGIN {
  test_array_param_filled_two_calls_down()
  test_array_param_fresh_at_each_call()
  done()
}
