"""Unit tests of the awk functions: each test/unit/test_*.awk prints TAP (see harness.awk)."""

from pathlib import Path

import pytest
from platforms import ROOT, SCRIPT, Awk
from pydantic import BaseModel, ConfigDict
from tap.line import Plan, Result
from tap.parser import Parser

UNIT_FILES = sorted((ROOT / "test/unit").glob("test_*.awk"))


def unit_args(path: Path, stderr: Path) -> list[str]:
    """The awk arguments that run the unit test file `path` (its code writes to `stderr`)."""
    return [
        "-v",
        "UNIT_TEST=1",
        "-v",
        # awk processes escapes in -v values: no backslashes (Windows paths)
        f"STDERR={stderr.as_posix()}",
        "-f",
        "test/unit/harness.awk",
        "-f",
        SCRIPT,
        "-f",
        str(path.relative_to(ROOT)),
        "/dev/null",
    ]


class Tap(BaseModel):
    """The lines of a TAP output, by kind."""

    model_config = ConfigDict(arbitrary_types_allowed=True)  # tap.py's Result and Plan

    checks: list[Result] = []
    plans: list[Plan] = []
    unexpected: list[str] = []
    diagnostics: dict[int, list[str]] = {}  # check number -> its lines


def parse_tap(text: str) -> Tap:
    tap = Tap()
    for line in Parser().parse_text(text):
        match line.category:
            case "test":
                tap.checks.append(line)
                tap.diagnostics[line.number] = []
            case "diagnostic" if tap.checks:  # attach to the last check
                tap.diagnostics[tap.checks[-1].number].append(line.text)
            case "plan":
                tap.plans.append(line)
            case _:  # bail, version, unknown, or a diagnostic before the first check
                tap.unexpected.append(line.text)
    return tap


@pytest.mark.parametrize("path", UNIT_FILES, ids=lambda p: p.stem.removeprefix("test_"))
def test_unit(awk: Awk, path: Path, tmp_path: Path, subtests: pytest.Subtests) -> None:
    stderr = tmp_path / "stderr"
    stderr.touch()
    proc = awk(*unit_args(path, stderr))

    tap = parse_tap(proc.stdout.decode(errors="replace"))

    for check in tap.checks:
        with subtests.test(msg=check.description, n=check.number):
            if check.todo:  # check_bug(): a known bug must still fail
                assert not check.ok, (
                    f"FIXED ({check.directive.text}): replace check_bug() with check()"
                )
            else:
                assert check.ok, "\n".join(tap.diagnostics[check.number])

    stderr_file_content = stderr.read_text()

    assert tap.plans, f"no TAP plan (crash?)\n{proc.stderr.decode(errors='replace')}"
    assert not tap.unexpected, "unexpected output:\n" + "\n".join(tap.unexpected)
    assert not stderr_file_content, f"unchecked stderr output:\n{stderr_file_content}"
    assert not proc.stderr, f"output of awk on stderr:\n{proc.stderr.decode(errors='replace')}"
    assert proc.returncode == (1 if any(not c.ok and not c.todo for c in tap.checks) else 0)
