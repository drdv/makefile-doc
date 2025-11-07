# -------------------------------
# BUG: BusyBox v1.37.0 (2024-09-26 21:31:42 UTC) multi-call binary.
# maybe related to: https://lists.busybox.net/pipermail/busybox-cvs/2009-November/030285.html
# -------------------------------
# command > bawk -v a=0 -f busybox_awk_bug.awk
# stdout  > b: 0
# -------------------------------
function f(x) {
  return x
}

BEGIN {
  b = f(a)

  if (a) printf("a: %s\n", a)
  if (b) printf("b: %s\n", b)
}
# -------------------------------
