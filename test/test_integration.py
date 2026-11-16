"""Integration tests: one test per test/integration/*.test case (format: test/README.md)."""

import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Self

import pytest
from conftest import ROOT, SCRIPT, VERSION


@dataclass(frozen=True)
class Case:
    """A test/integration/*.test file."""

    path: Path
    head: str  # the metadata lines and the line of the awk arguments
    meta: dict[str, list[str]]  # the `#: key: value` lines at the start
    args: str  # the awk arguments, in shell syntax
    expected: str  # the expected output

    @classmethod
    def read(cls, path: Path) -> Self:
        lines = path.read_bytes().decode(errors="surrogateescape").splitlines(keepends=True)
        # k: the line of the arguments, the first one that is not metadata
        k = next((k for k, line in enumerate(lines) if not line.startswith("#:")), len(lines))
        meta: dict[str, list[str]] = {}
        for line in lines[:k]:
            key, _, value = line[2:].partition(":")
            meta.setdefault(key.strip(), []).append(value.strip())
        args = lines[k].rstrip("\n") if k < len(lines) else ""
        return cls(path, "".join(lines[: k + 1]), meta, args, "".join(lines[k + 1 :]))

    @property
    def name(self) -> str:
        return self.path.stem

    @property
    def bug(self) -> str | None:
        """The issue of the known bug that the case reproduces (`#: bug: N`)."""
        return self.meta["bug"][0] if "bug" in self.meta else None

    @property
    def env(self) -> dict[str, str]:
        """The environment variables of the `#: env: NAME=value` lines."""
        return dict(item.split("=", 1) for item in self.meta.get("env", []))

    def update(self, actual: str) -> None:
        """Replace the expected output in the file."""
        self.path.write_bytes((self.head + actual).encode(errors="surrogateescape"))


CASES = [Case.read(path) for path in sorted((ROOT / "test/integration").glob("*.test"))]


def render(proc: subprocess.CompletedProcess) -> str:
    """Return the result of an awk process in the format of the expected output."""
    out = ""
    for name, data in (("stderr", proc.stderr), ("stdout", proc.stdout)):
        if data:
            out += f"#: {name}\n" + data.decode(errors="surrogateescape")
    if proc.returncode:
        out += f"#: exit: {proc.returncode}\n"
    return out.replace(f"Version: {VERSION}", "Version: @VERSION@")


def params() -> list:
    """One parameter per case; the case of a known bug is expected to fail."""
    return [
        pytest.param(
            case,
            id=case.name,
            marks=[pytest.mark.xfail(reason=f"issue {case.bug}", strict=True)] if case.bug else [],
        )
        for case in CASES
    ]


@pytest.mark.parametrize("case", params())
def test_case(awk, case: Case, request: pytest.FixtureRequest) -> None:
    actual = render(awk("-f", SCRIPT, *shlex.split(case.args), env=case.env))

    # the expected output of a known bug is written by hand: it is never updated
    if request.config.getoption("update") and not case.bug and actual != case.expected:
        case.update(actual)
        return
    # lists of lines: pytest shows a line diff with escapes and trailing blanks visible
    assert actual.splitlines(keepends=True) == case.expected.splitlines(keepends=True)
