"""Integration tests: one test per test/integration/*.test case (format: test/README.md)."""

import shlex
from pathlib import Path

import pytest
from conftest import ROOT, SCRIPT, VERSION


def load(path: Path) -> tuple[dict[str, list[str]], str, str]:
    """Return (metadata, awk arguments, expected output) of a case."""
    lines = path.read_bytes().decode(errors="surrogateescape").splitlines(keepends=True)
    k = next((k for k, line in enumerate(lines) if not line.startswith("#:")), len(lines))
    meta: dict[str, list[str]] = {}
    for line in lines[:k]:
        key, _, value = line[2:].partition(":")
        meta.setdefault(key.strip(), []).append(value.strip())
    return meta, "".join(lines[k : k + 1]).rstrip("\n"), "".join(lines[k + 1 :])


def params() -> list:
    out = []
    for path in sorted((ROOT / "test/integration").glob("*.test")):
        bug = load(path)[0].get("bug")
        marks = [pytest.mark.xfail(reason=f"issue {bug[0]}", strict=True)] if bug else []
        out.append(pytest.param(path, id=path.stem, marks=marks))
    return out


@pytest.mark.parametrize("path", params())
def test_case(awk, path: Path, request: pytest.FixtureRequest) -> None:
    meta, args, expected = load(path)
    env = dict(item.split("=", 1) for item in meta.get("env", []))
    proc = awk("-f", SCRIPT, *shlex.split(args), env=env)

    actual = ""
    for name, data in (("stderr", proc.stderr), ("stdout", proc.stdout)):
        if data:
            actual += f"#: {name}\n" + data.decode(errors="surrogateescape")
    if proc.returncode:
        actual += f"#: exit: {proc.returncode}\n"
    actual = actual.replace(f"Version: {VERSION}", "Version: @VERSION@")

    if request.config.getoption("update") and actual != expected:
        head = path.read_bytes().decode(errors="surrogateescape")[: -len(expected) or None]
        path.write_bytes((head + actual).encode(errors="surrogateescape"))
        return
    # lists of lines: pytest shows a line diff with escapes and trailing blanks visible
    assert actual.splitlines(keepends=True) == expected.splitlines(keepends=True)
