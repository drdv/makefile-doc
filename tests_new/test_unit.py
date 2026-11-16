"""Unit tests of the awk functions: each test/unit/test_*.awk prints TAP (see harness.awk)."""

from pathlib import Path

import pytest
from conftest import ROOT, SCRIPT
from tap.parser import Parser

FILES = sorted((ROOT / "test/unit").glob("test_*.awk"))


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem.removeprefix("test_"))
def test_unit(awk, path: Path, tmp_path: Path, subtests: pytest.Subtests) -> None:
    stderr = tmp_path / "stderr"
    stderr.touch()
    proc = awk(
        "-v", "UNIT_TEST=1", "-v", f"STDERR={stderr}",
        "-f", "test/unit/harness.awk", "-f", SCRIPT, "-f", path, "/dev/null",
    )  # fmt: skip
    lines = list(Parser().parse_text(proc.stdout.decode(errors="replace")))
    checks = [line for line in lines if line.category == "test"]
    plans = [line for line in lines if line.category == "plan"]
    diagnostics = {}  # check number -> the `#   got/want` lines after it
    for line in lines:
        if line.category == "test":
            current = diagnostics.setdefault(line.number, [])
        elif line.category == "diagnostic" and checks:
            current.append(line.text)

    for check in checks:
        with subtests.test(msg=check.description, n=check.number):
            if check.todo:  # check_bug(): a known bug must still fail
                assert not check.ok, f"FIXED ({check.directive.text}): use check()"
            else:
                assert check.ok, "\n".join(diagnostics[check.number])

    assert not [line.text for line in lines if line.category == "bail"]
    assert plans, f"no TAP plan (crash?)\n{proc.stderr.decode(errors='replace')}"
    assert [c.number for c in checks] == list(range(1, plans[0].expected_tests + 1))
    assert proc.returncode == (1 if any(not c.ok and not c.todo for c in checks) else 0)
