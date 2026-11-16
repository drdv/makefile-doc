"""Lint makefile-doc.awk with `gawk --lint` while it runs every case and unit test file."""

import re
import shlex
import shutil
import tomllib
from collections import defaultdict

import pytest
from conftest import ROOT, SCRIPT, Awk
from test_integration import load

IGNORE = [
    re.compile(p)
    for p in tomllib.loads((ROOT / "pyproject.toml").read_text())["tool"]["makefile-doc"]["lint"][
        "ignore"
    ]
]
UNIT = sorted(p.relative_to(ROOT) for p in (ROOT / "test/unit").glob("test_*.awk"))
POSITION = re.compile(r"\(FILENAME=.*? FNR=\d+\) |^gawk: |warning: ")


def unit_args(path, stderr):
    return ["-v", "UNIT_TEST=1", "-v", f"STDERR={stderr}",
            "-f", "test/unit/harness.awk", "-f", SCRIPT, "-f", path, "/dev/null"]  # fmt: skip


@pytest.fixture(scope="session")
def gawk() -> Awk:
    if not shutil.which("gawk"):
        pytest.skip("gawk is not installed")
    return Awk(("gawk",))


@pytest.fixture(scope="session")
def warnings(gawk, tmp_path_factory) -> dict[str, set[str]]:
    """Each distinct warning (without the input position) -> the runs that print it."""
    stderr = tmp_path_factory.mktemp("lint") / "STDERR"
    stderr.touch()
    runs = {
        p.stem: ["-v", "STDERR=/dev/null", "-f", SCRIPT, *shlex.split(load(p)[1])]
        for p in sorted((ROOT / "test/integration").glob("*.test"))
    } | {p.stem: unit_args(p, stderr) for p in UNIT}
    found = defaultdict(set)
    for name, args in runs.items():
        out = gawk("--lint", *args).stderr.decode(errors="replace").replace(str(stderr), "STDERR")
        for line in out.splitlines():
            found[POSITION.sub("", line)].add(name)
    return found


def inline_ignored(warning: str) -> bool:
    """`# lint: ignore` at the end of the line of the warning, or alone on the line before."""
    m = re.match(rf"{re.escape(SCRIPT)}:(\d+): ", warning)
    if not m:
        return False
    lines = [""] + (ROOT / SCRIPT).read_text().splitlines()
    n = int(m[1])
    return "# lint: ignore" in lines[n] or lines[n - 1].lstrip().startswith("# lint: ignore")


def test_no_unexpected_warnings(warnings) -> None:
    unexpected = {
        w: sorted(runs)[:3]
        for w, runs in warnings.items()
        if not any(p.search(re.sub(r":\d+:", ":", w, count=1)) for p in IGNORE)
        and not inline_ignored(w)
        and not w.startswith("test/")  # test code: not checked
    }
    assert not unexpected


def test_no_stale_ignore(warnings) -> None:
    flat = [re.sub(r":\d+:", ":", w, count=1) for w in warnings]
    assert not [p.pattern for p in IGNORE if not any(p.search(w) for w in flat)]


def globals_of(gawk: Awk, tmp_path, *args) -> set[str]:
    dump = tmp_path / "globals"
    gawk(f"-d{dump}", *args)
    return {line.split(":")[0] for line in dump.read_text().splitlines() if line}


def test_global_names(gawk, tmp_path) -> None:
    names = globals_of(gawk, tmp_path, "-v", "SHOW_HELP=0", "-f", SCRIPT)
    assert not sorted(n for n in names if not re.fullmatch(r"[A-Z_]+|g_[a-z_]+", n))


@pytest.mark.parametrize("path", UNIT, ids=lambda p: p.stem)
def test_unit_file_defines_no_globals(gawk, tmp_path, path) -> None:
    script = globals_of(gawk, tmp_path, "-v", "SHOW_HELP=0", "-f", SCRIPT)
    stderr = tmp_path / "stderr"
    stderr.touch()
    leaked = globals_of(gawk, tmp_path, *unit_args(path, stderr)) - script
    assert not sorted(n for n in leaked if not n.startswith("HARNESS_"))
