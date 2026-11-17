"""Tests of test/platforms.py (they start no container)."""

from pathlib import Path

import platforms
import pytest


def test_platforms_file() -> None:
    """test/containers.toml is valid, and its Containerfiles exist."""
    known = platforms.load()
    assert known
    for platform in known.values():
        assert platform.build is None or (platforms.ROOT / platform.build).is_file()


@pytest.mark.parametrize(
    ("toml", "message"),
    [
        ('[p]\nawk = "awk"', "give either image or build"),
        ('[p]\nimage = "i"\nbuild = "b"\nawk = "awk"', "give either image or build"),
        ('[p]\nimage = "i"', "awk is missing"),
        ('[p]\nimage = "i"\nawk = "awk"\nflags = "-x"', "unknown key flags"),
        ('[p]\nimage = "i"\nawk = "awk"\nargs = { V = "1" }', "args needs build"),
        ('[p]\nimage = "i"\nawk = "awk"\nci = "yes"', "ci should be true or false"),
    ],
)
def test_load_rejects(tmp_path: Path, toml: str, message: str) -> None:
    path = tmp_path / "containers.toml"
    path.write_text(toml)
    with pytest.raises(platforms.PlatformError, match=message):
        platforms.load(path)


def test_tag() -> None:
    assert platforms.Platform("p", "awk", image="debian:12").tag == "debian:12"
    build = "test/containers/mawk.Containerfile"
    one = platforms.Platform("p", "mawk", build=build, args={"VERSION": "1"})
    two = platforms.Platform("p", "mawk", build=build, args={"VERSION": "2"})
    assert one.tag.startswith("localhost/makefile-doc-p:")
    assert one.tag != two.tag  # other arguments: another image
    assert one.tag == platforms.Platform("p", "mawk", build=build, args={"VERSION": "1"}).tag
