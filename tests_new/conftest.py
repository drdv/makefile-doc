"""Shared pytest configuration: which awk to test, and how to run it."""

import os
import re
import shlex
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
SCRIPT = "makefile-doc.awk"
VERSION = re.search(r'^\s*VERSION = "([^"]+)"', (ROOT / SCRIPT).read_text(), re.M)[1]


@dataclass(frozen=True)
class Awk:
    """An awk command line, e.g. `gawk --posix` or `busybox awk`."""

    argv: tuple[str, ...]

    def __call__(self, *args: object, env: dict[str, str] | None = None, timeout: float = 30):
        # a hermetic environment: nothing of the caller (NO_COLOR, AWKPATH, LC_ALL, ...) leaks in
        base = {"PATH": os.environ["PATH"], "LC_ALL": "C"}
        return subprocess.run(
            [*self.argv, *map(str, args)],
            cwd=ROOT, env={**base, **(env or {})}, stdin=subprocess.DEVNULL,
            capture_output=True, timeout=timeout, check=False,
        )  # fmt: skip


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("makefile-doc")
    group.addoption(
        "--awk", action="append", default=[], metavar="CMD",
        help="awk command to test, with its flags (repeatable), e.g. --awk gawk "
        "--awk 'gawk --posix' --awk 'busybox awk' (default: $AWK or awk)",
    )  # fmt: skip
    group.addoption("--update", action="store_true", help="rewrite the expected outputs")


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "awk" in metafunc.fixturenames:
        specs = metafunc.config.getoption("awk") or [os.environ.get("AWK", "awk")]
        metafunc.parametrize("awk", specs, indirect=True, scope="session")


@pytest.fixture(scope="session")
def awk(request: pytest.FixtureRequest) -> Awk:
    argv = shlex.split(request.param)
    if not shutil.which(argv[0]):
        pytest.fail(f"{argv[0]}: not found", pytrace=False)
    return Awk(tuple(argv))
