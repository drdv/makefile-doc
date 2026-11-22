# Releasing

`tools/release.py` manages the version and the releases; the Makefile calls it in `release-notes`
and `bump`.

The version is defined in `makefile-doc.awk` (e.g., `VERSION = "v1.9"`). The release pipeline:

1. `make release-notes` writes a draft of the notes to `release-message.md` (then edit it).
2. `make bump V=v1.10` sets the version in the script and the README, commits them, and creates an
   annotated tag with `release-message.md` as its message (the file is then deleted). Without
   `release-message.md`, it only sets the version, without committing or tagging.
3. Manually push the commit and the tag: `git push -u origin BRANCH TAG`.
4. CI (`.github/workflows/release.yml`) runs the tests, checks that the tag matches the version in
   both `makefile-doc.awk` and the README, and creates a draft release including `makefile-doc.awk`
   and its checksum as assets.
5. Review the draft release on GitHub and publish it.
