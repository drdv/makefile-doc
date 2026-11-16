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
            cwd=ROOT,
            env={**base, **(env or {})},
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=timeout,
            check=False,
        )


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("makefile-doc")
    group.addoption(
        "--awk",
        action="append",
        default=[],
        metavar="CMD",
        help="awk command to test, with its flags (repeatable), e.g. --awk gawk "
        "--awk 'gawk --posix' --awk 'busybox awk' (default: $AWK or awk)",
    )
    group.addoption("--update", action="store_true", help="rewrite the expected outputs")


def pytest_configure(config: pytest.Config) -> None:
    if config.getoption("update") and len(config.getoption("awk")) > 1:
        raise pytest.UsageError("--update rewrites the expected outputs: give one --awk")


def awk_commands(config: pytest.Config) -> list[str]:
    """The awk commands to test: the --awk options, by default $AWK or awk."""
    return config.getoption("awk") or [os.environ.get("AWK", "awk")]


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "awk" in metafunc.fixturenames:
        metafunc.parametrize("awk", awk_commands(metafunc.config), indirect=True, scope="session")


def pytest_report_collectionfinish(config: pytest.Config, items: list[pytest.Item]) -> str | None:
    """Show the awk commands after `collected N items`, if a collected test runs them."""
    if any("awk" in getattr(item, "fixturenames", ()) for item in items):
        return "awk: " + ", ".join(awk_commands(config))
    return None


@pytest.fixture(scope="session")
def awk(request: pytest.FixtureRequest) -> Awk:
    argv = shlex.split(request.param)
    if not shutil.which(argv[0]):
        pytest.fail(f"{argv[0]}: not found", pytrace=False)
    return Awk(tuple(argv))
