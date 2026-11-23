# -------------------------------
# BUG: onetrue awk (awk version 20231127, Ubuntu 24.04 package original-awk)
# match() on the result of substr(), when the substr() arguments depend on an earlier match()
# result, returns -1 (expected: 11); with the substr() stored in a variable first, it works
# -------------------------------
# command > original-awk -f onetrue_awk_bug_20261123.awk
# stdout  > -1 11
# -------------------------------
BEGIN {
  s = "t: dep __ x # c"
  p = match(s, /[#=:]/)
  rest = substr(s, p + 1)
  print match(substr(s, p + 1), /[#;=]/), match(rest, /[#;=]/)
}
