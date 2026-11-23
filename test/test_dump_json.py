"""tools/dump-json.awk prints valid JSON for every fixture, consistent with the help."""

import json
from pathlib import Path

import pytest
from platforms import ROOT, SCRIPT, Awk

FIXTURES = sorted((ROOT / "test/fixtures").glob("Makefile.*"))


@pytest.mark.parametrize("path", FIXTURES, ids=lambda p: p.name.removeprefix("Makefile."))
def test_dump_json(awk: Awk, path: Path) -> None:
    proc = awk("-f", "tools/dump-json.awk", "-f", SCRIPT, path.relative_to(ROOT).as_posix())
    data = json.loads(proc.stdout.decode(errors="surrogateescape"))
    assert set(data) == {"files", "anchors", "display", "warnings"}
    # each displayed anchor is a documented one, and each documented one is displayed (the
    # options that hide anchors are not passed)
    documented = {(a["kind"], a["name"]) for a in data["anchors"]}
    displayed = [(d["kind"], d["name"]) for d in data["display"]]
    assert set(displayed) == documented
    assert len(displayed) == len(documented)
