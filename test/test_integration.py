"""Integration tests: one test per test/integration/*.test case (format: test/README.md)."""

import shlex
import subprocess
from pathlib import Path
from typing import Self

import pytest
from platforms import ROOT, SCRIPT, VERSION, Awk
from pydantic import BaseModel, ConfigDict, model_validator

# the keys of the `#:` lines (see test/README.md)
META_KEYS = {"desc", "issue", "bug", "env", "stdin", "trace"}

# loaded before the script by the cases with `#: trace`
TRACER = "tools/trace-state.awk"
# with --new-parser: the tracer of the new parser, loaded before the script and the new parser
NEW_TRACER = ("-f", "tools/trace-parser.awk", "-f", SCRIPT, "-f", "parser.awk")


class Case(BaseModel):
    """A test/integration/*.test file."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    path: Path
    head: str  # the metadata lines and the line of the awk arguments
    meta: dict[str, list[str]]  # the `#: key: value` lines at the start
    args: tuple[str, ...]  # the awk arguments (the line is in shell syntax)
    expected: str  # the expected output

    @model_validator(mode="after")
    def check_meta(self) -> Self:
        if unknown := sorted(self.meta.keys() - META_KEYS):
            raise ValueError(f"{self.path.name}: unknown metadata: {', '.join(unknown)}")
        if not any(self.meta.get("desc", [])):
            raise ValueError(f"{self.path.name}: needs a non-empty `#: desc:` line")
        return self

    @classmethod
    def read(cls, path: Path) -> Self:
        lines = path.read_bytes().decode(errors="surrogateescape").splitlines(keepends=True)
        # k: the line of the arguments, the first one that is not metadata
        k = next((k for k, line in enumerate(lines) if not line.startswith("#:")), len(lines))
        meta: dict[str, list[str]] = {}
        for line in lines[:k]:
            key, _, value = line[2:].partition(":")
            meta.setdefault(key.strip(), []).append(value.strip())
        args = tuple(shlex.split(lines[k])) if k < len(lines) else ()
        return cls(
            path=path,
            head="".join(lines[: k + 1]),
            meta=meta,
            args=args,
            expected="".join(lines[k + 1 :]),
        )

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

    @property
    def trace(self) -> bool:
        """Whether the output is the trace of the parser (`#: trace`) instead of the help."""
        return "trace" in self.meta

    @property
    def stdin(self) -> bytes:
        """The stdin of awk: the content of the file of the `#: stdin: PATH` line (or empty)."""
        return (ROOT / self.meta["stdin"][0]).read_bytes() if "stdin" in self.meta else b""

    def update(self, actual: str) -> None:
        """Replace the expected output in the file."""
        self.path.write_bytes((self.head + actual).encode(errors="surrogateescape"))


CASES = [Case.read(path) for path in sorted((ROOT / "test/integration").glob("*.test"))]


def render(proc: subprocess.CompletedProcess[bytes]) -> str:
    """Return the result of an awk process in the format of the expected output."""
    out = ""
    for name, data in (("stderr", proc.stderr), ("stdout", proc.stdout)):
        if data:
            # output without a final newline is a bug of the script: it is never accepted
            assert data.endswith(b"\n"), f"{name} does not end with a newline"
            out += f"#: {name}\n" + data.decode(errors="surrogateescape")
    if proc.returncode:
        out += f"#: exit: {proc.returncode}\n"
    return out.replace(f"Version: {VERSION}", "Version: @VERSION@")


def params() -> list[pytest.ParameterSet]:
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
def test_case(awk: Awk, case: Case, request: pytest.FixtureRequest) -> None:
    if case.trace and request.config.getoption("new_parser"):
        program: tuple[str, ...] = NEW_TRACER
    else:
        program = ("-f", TRACER, "-f", SCRIPT) if case.trace else ("-f", SCRIPT)
    actual = render(awk(*program, *case.args, env=case.env, stdin=case.stdin))

    # the expected output of a known bug is written by hand: it is never updated
    if request.config.getoption("update") and not case.bug and actual != case.expected:
        case.update(actual)
        pytest.skip(f"updated {case.path.relative_to(ROOT)}")
    # lists of lines: pytest shows a line diff with escapes and trailing blanks visible
    assert actual.splitlines(keepends=True) == case.expected.splitlines(keepends=True)
