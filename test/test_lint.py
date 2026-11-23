"""Lint makefile-doc.awk with `gawk --lint` while it runs every case and unit test file.

A warning in makefile-doc.awk is expected (see test/README.md)
  * by a regular expression of `ignore` in [tool.makefile-doc.lint] of pyproject.toml, or
  * by a `# lint: ignore[TEXT]` comment at its line, where TEXT is a part of its message.
"""

import re
import shutil
import tomllib
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple, Self

import pytest
from platforms import ROOT, SCRIPT, Awk
from test_integration import CASES
from test_unit import UNIT_FILES, unit_args

IGNORE = [
    re.compile(p)
    for p in tomllib.loads((ROOT / "pyproject.toml").read_text())["tool"]["makefile-doc"]["lint"][
        "ignore"
    ]
]

# what gawk adds to a warning: its name, the position in the input and the word `warning`
NOISE = re.compile(r"^gawk: |\(FILENAME=.*? FNR=\d+\) |warning: ")
LOCATION = re.compile(r"(?P<file>[^:\s]+):(?P<line>\d+): (?P<message>.*)")
INLINE = re.compile(r"# lint: ignore\[(?P<text>[^\]]*)\]")


class LintWarning(NamedTuple):
    """A warning of gawk --lint, e.g., `makefile-doc.awk:211: substr: start index 0 is ...`."""

    file: str | None  # None: gawk gives no location e.g., for a function never called
    line: int | None
    message: str

    @classmethod
    def parse(cls, text: str) -> Self:
        m = LOCATION.fullmatch(text)
        return cls(m["file"], int(m["line"]), m["message"]) if m else cls(None, None, text)

    def __str__(self) -> str:
        return f"{self.file}:{self.line}: {self.message}" if self.file else self.message

    @property
    def without_line(self) -> str:
        """The form that the `ignore` expressions of pyproject.toml are searched in."""
        return f"{self.file}: {self.message}" if self.file else self.message


class Inline(NamedTuple):
    """A `# lint: ignore[TEXT]` comment of makefile-doc.awk."""

    line: int  # the line of the comment
    target: int  # the line whose warnings it expects
    text: str

    def expects(self, warning: LintWarning) -> bool:
        return (
            warning.file == SCRIPT and warning.line == self.target and self.text in warning.message
        )


def inline_comments(lines: list[str]) -> list[Inline]:
    """Return the `# lint: ignore[TEXT]` comments of a script.

    A comment at the end of a line of code is for that line. A comment alone on its line is
    for the next line of code: several such comments can follow each other, one per text.
    """
    comments = []
    pending = []  # (line, text) of the comments that wait for the next line of code
    for number, line in enumerate(lines, start=1):
        m = INLINE.search(line)
        if m and line.lstrip().startswith("# lint: ignore["):
            pending.append((number, m["text"]))
            continue
        comments += [Inline(n, number, text) for n, text in pending]
        pending = []
        if m:
            comments.append(Inline(number, number, m["text"]))
    return comments


INLINE_COMMENTS = inline_comments((ROOT / SCRIPT).read_text().splitlines())


@pytest.fixture(scope="session")
def gawk() -> Awk:
    if not shutil.which("gawk"):
        pytest.skip("gawk is not installed")
    return Awk(awk=("gawk",))


@pytest.fixture(scope="session")
def warnings(gawk: Awk, tmp_path_factory: pytest.TempPathFactory) -> dict[LintWarning, set[str]]:
    """Each distinct warning (without the input position) -> the runs that print it."""
    stderr = tmp_path_factory.mktemp("lint") / "STDERR"
    stderr.touch()
    # name -> (awk arguments, environment, stdin): the cases run with their `#: env:` variables
    # and their `#: stdin:` file
    runs = {
        case.name: (["-v", "STDERR=/dev/null", "-f", SCRIPT, *case.args], case.env, case.stdin)
        for case in CASES
    } | {path.stem: (unit_args(path, stderr), {}, b"") for path in UNIT_FILES}
    found: defaultdict[LintWarning, set[str]] = defaultdict(set)
    for name, (args, env, stdin) in runs.items():
        proc = gawk("--lint", *args, env=env, stdin=stdin)
        out = proc.stderr.decode(errors="replace").replace(str(stderr), "STDERR")
        if "fatal:" in out:
            pytest.fail(f"{name}: gawk failed\n{out}", pytrace=False)
        for line in out.splitlines():
            found[LintWarning.parse(NOISE.sub("", line))].add(name)
    return found


def expected(warning: LintWarning) -> bool:
    return any(p.search(warning.without_line) for p in IGNORE) or any(
        comment.expects(warning) for comment in INLINE_COMMENTS
    )


def test_inline_comments() -> None:
    lines = [
        "x = 1 # lint: ignore[at the end] (a note)",  # 1
        "# lint: ignore[first]",  # 2
        "    # lint: ignore[second] (a note)",  # 3
        "y = 2 # lint: ignore[third]",  # 4
        "# an ordinary comment",  # 5
    ]
    assert inline_comments(lines) == [
        Inline(1, 1, "at the end"),
        Inline(2, 4, "first"),
        Inline(3, 4, "second"),
        Inline(4, 4, "third"),
    ]
    first = Inline(2, 4, "first")
    assert first.expects(LintWarning(SCRIPT, 4, "the first message"))
    assert not first.expects(LintWarning(SCRIPT, 4, "another message"))
    assert not first.expects(LintWarning(SCRIPT, 5, "the first message"))
    assert not first.expects(LintWarning("test/unit/harness.awk", 4, "the first message"))


def test_no_unexpected_warnings(warnings: dict[LintWarning, set[str]]) -> None:
    unexpected = {
        str(warning): sorted(runs)[:3]  # with up to three of the runs that print it
        for warning, runs in warnings.items()
        if not expected(warning)
        and not (warning.file or "").startswith("test/")  # test code is not checked
    }
    assert not unexpected


def test_no_stale_ignore(warnings: dict[LintWarning, set[str]]) -> None:
    """Every `ignore` expression and every inline comment expects at least one warning."""
    stale = [p.pattern for p in IGNORE if not any(p.search(w.without_line) for w in warnings)]
    stale += [
        f"{SCRIPT}:{comment.line}: # lint: ignore[{comment.text}]"
        for comment in INLINE_COMMENTS
        if not comment.text or not any(comment.expects(w) for w in warnings)
    ]
    assert not stale


def globals_of(gawk: Awk, tmp_path: Path, *args: str) -> set[str]:
    dump = tmp_path / "globals"
    gawk(f"-d{dump}", *args)
    return {line.split(":")[0] for line in dump.read_text().splitlines() if line}


def test_global_names(gawk: Awk, tmp_path: Path) -> None:
    names = globals_of(gawk, tmp_path, "-f", SCRIPT)
    assert not sorted(n for n in names if not re.fullmatch(r"[A-Z_]+", n))


@pytest.mark.parametrize("path", UNIT_FILES, ids=lambda p: p.stem)
def test_unit_file_defines_no_globals(gawk: Awk, tmp_path: Path, path: Path) -> None:
    script = globals_of(gawk, tmp_path, "-f", SCRIPT)
    stderr = tmp_path / "stderr"
    stderr.touch()
    leaked = globals_of(gawk, tmp_path, *unit_args(path, stderr)) - script
    assert not sorted(n for n in leaked if not n.startswith("HARNESS_"))
