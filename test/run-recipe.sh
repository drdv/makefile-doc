#!/usr/bin/env bash
# Run one test recipe file.
#
# usage: run-recipe.sh MODE AWK RECIPE_FILE [AWK_FLAGS...]
#
#   MODE  test      the output must match the expected output
#         bug       a known bug: it must NOT match yet (if it does, the
#                   script fails: the test has to move to the integration tests)
#         update    rewrite the recipe file with the current output
#   AWK             the awk binary to run (e.g., test/bin/awk)
#   RECIPE_FILE     the test file (e.g., test/integration/test-default)
#   AWK_FLAGS       optional extra flags passed to awk (e.g., goawk coverage options)
#
# Environment (optional):
#   MAKEFILE_DOC  the awk script (default: makefile-doc.awk)
#
# Recipe file format:
#   - optional leading metadata lines starting with `#:` (ignored when running;
#     bug tests must have a `#: issue: N` line)
#   - first remaining line: the awk arguments
#   - remaining lines: the expected output: stderr, then stdout, then
#     `exit: N` if the exit status is not 0

[ $# -ge 3 ] || { echo "usage: run-recipe MODE AWK RECIPE_FILE [AWK_FLAGS...]" >&2; exit 2; }

mode=$1 awk=$2 file=$3
shift 3
flags=("$@")
doc=${MAKEFILE_DOC:-makefile-doc.awk}
name=$(basename "$file")

if [ "$mode" = bug ] && ! grep -q '^#: issue: *[0-9]' "$file"; then
	echo "$name: missing '#: issue: N' header" >&2
	exit 1
fi

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# split the recipe file into the args line and the expected output
grep -v '^#:' "$file" > "$tmp/recipe"
cmd=$(head -n 1 "$tmp/recipe")
tail -n +2 "$tmp/recipe" > "$tmp/expected"

# We redirect to actual files because making sure that stderr and stdout
# appear in the right order with all awk variants (in particular goawk) and on
# CI was problematic otherwise.
eval "\"\$awk\" -f \"\$doc\" \"\${flags[@]}\" $cmd" \
	 < /dev/null > "$tmp/stdout" 2> "$tmp/stderr"
status=$?
{
	cat "$tmp/stderr"
	cat "$tmp/stdout"
	[ "$status" -ne 0 ] && echo "exit: $status"
} > "$tmp/actual"

# --ignore-space-at-eol is needed as empty descriptions add OFFSET
same() {
	git diff --no-index --quiet --ignore-space-at-eol "$tmp/expected" "$tmp/actual"
}
show_diff() {
	git diff --no-index --ignore-space-at-eol "$tmp/expected" "$tmp/actual"
}

case $mode in
	test)
		if same; then
			echo "[$(basename "$awk")] passed $name"
		else
			show_diff
			echo "failed $name"
			exit 1
		fi
		;;
	bug)
		if same; then
			echo "FIXED: $name (move it to test/integration)"
			exit 1
		else
			show_diff
			echo "still broken: $name"
		fi
		;;
	update)
		{ grep '^#:' "$file"; printf '%s\n' "$cmd"; cat "$tmp/actual"; } > "$tmp/new"
		cat "$tmp/new"
		cp "$tmp/new" "$file"
		;;
	*)
		echo "run-recipe: unknown mode '$mode'" >&2
		exit 2
		;;
esac
