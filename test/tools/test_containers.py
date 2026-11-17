"""Tests of test/tools/containers.py (run them with `make test-tools`)."""

import importlib.util
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("containers", TOOLS / "containers.py")
containers = importlib.util.module_from_spec(_spec)
sys.modules["containers"] = containers
_spec.loader.exec_module(containers)


def test_platforms_file() -> None:
    """test/containers.toml is valid, and its Containerfiles exist."""
    platforms = containers.load()
    assert platforms
    for platform in platforms.values():
        if "build" in platform:
            assert (containers.ROOT / platform["build"]).is_file()


@pytest.mark.parametrize(
    ("toml", "message"),
    [
        ('[p]\nawk = "awk"', "give either image or build"),
        ('[p]\nimage = "i"\nbuild = "b"\nawk = "awk"', "give either image or build"),
        ('[p]\nimage = "i"', "awk is missing"),
        ('[p]\nimage = "i"\nawk = "awk"\nflags = "-x"', "unknown key flags"),
    ],
)
def test_load_rejects(tmp_path: Path, toml: str, message: str) -> None:
    path = tmp_path / "containers.toml"
    path.write_text(toml)
    with pytest.raises(ValueError, match=message):
        containers.load(path)


def test_commands_with_image() -> None:
    platform = {"image": "debian:12", "awk": "mawk -W posix", "install": "x || y"}
    build, test = containers.commands("p", platform, "podman", ["-k", "misc"])
    assert build[:2] == ["podman", "build"]
    assert "BASE=debian:12" in build
    assert "INSTALL=x || y" in build
    assert test[:2] == ["podman", "run"]
    assert "AWK=mawk -W posix" in test
    assert test[-2:] == ["-k", "misc"]


def test_commands_with_build() -> None:
    platform = {"build": "test/containers/p.Containerfile", "awk": "mawk"}
    base, build, _ = containers.commands("p", platform, "docker", [])
    assert base[:4] == ["docker", "build", "--file", "test/containers/p.Containerfile"]
    assert "localhost/makefile-doc-base:p" in base
    assert "BASE=localhost/makefile-doc-base:p" in build
    assert "INSTALL=" in build


def test_run_without_build(monkeypatch: pytest.MonkeyPatch) -> None:
    ran = []

    def fake_run(command, **kwargs):
        ran.append(command[:2])
        return containers.subprocess.CompletedProcess(command, 0, stdout=b"")

    monkeypatch.setattr(containers.subprocess, "run", fake_run)
    name = next(iter(containers.load()))
    assert containers.run(name, "podman", build_image=False, args=[]) == 0
    assert ran == [["podman", "run"]]
    ran.clear()
    assert containers.run(name, "podman", build_image=True, args=[]) == 0
    assert ran == [["podman", "build"], ["podman", "run"]]
