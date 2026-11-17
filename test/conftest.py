"""Shared pytest configuration: which awk to test, and how to run it."""

import os
import re
import shlex
import shutil
import subprocess
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

import platforms
import pytest

ROOT = Path(__file__).parent.parent
SCRIPT = "makefile-doc.awk"
VERSION = re.search(r'^\s*VERSION = "([^"]+)"', (ROOT / SCRIPT).read_text(), re.M)[1]


@dataclass(frozen=True)
class Awk:
    """An awk command line, e.g. `gawk --posix` or `busybox awk`."""

    argv: tuple[str, ...]
    # to run it in a container: the start of the exec command of the engine and the name
    # of the container, e.g. ("podman", "exec", "--interactive") and "makefile-doc-debian12"
    exec_prefix: tuple[str, ...] = ()
    container: str = ""

    def __call__(self, *args: object, env: dict[str, str] | None = None, timeout: float = 30):
        # a hermetic environment: nothing of the caller (NO_COLOR, AWKPATH, LC_ALL, ...) leaks in
        env = {"LC_ALL": "C", **(env or {})}
        command = [*self.argv, *map(str, args)]
        if self.container:
            # the engine runs with the environment of the caller (it needs it); the awk in
            # the container gets `env`, and the PATH of the container
            variables = [f"--env={name}={value}" for name, value in env.items()]
            workdir = f"--workdir={ROOT}"
            command = [*self.exec_prefix, workdir, *variables, self.container, *command]
            env = None
        else:
            env = {"PATH": os.environ["PATH"], **env}
        return subprocess.run(
            command,
            cwd=ROOT,
            env=env,
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
    group.addoption(
        "--platform",
        action="append",
        default=[],
        metavar="NAME",
        help="platform of test/containers.toml whose awk to test, in a container (repeatable)",
    )
    group.addoption(
        "--engine", default="podman", metavar="CMD", help="container engine (default: podman)"
    )
    group.addoption("--update", action="store_true", help="rewrite the expected outputs")


def pytest_configure(config: pytest.Config) -> None:
    try:
        targets = awk_targets(config)
    except platforms.PlatformError as error:
        raise pytest.UsageError(str(error)) from None
    if config.getoption("update") and len(targets) > 1:
        raise pytest.UsageError("--update rewrites the expected outputs: give one awk")


def awk_targets(config: pytest.Config) -> list[str | platforms.Platform]:
    """What to test: the awk commands of --awk and the platforms of --platform.

    Without either, the command is $AWK or awk.
    """
    commands = config.getoption("awk")
    names = config.getoption("platform")
    if not names:
        return commands or [os.environ.get("AWK", "awk")]
    known = platforms.load()
    if unknown := [name for name in names if name not in known]:
        raise platforms.PlatformError(f"{unknown[0]}: not a platform of test/containers.toml")
    return [*commands, *(known[name] for name in names)]


def target_id(target: str | platforms.Platform) -> str:
    return target if isinstance(target, str) else target.name


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "awk" in metafunc.fixturenames:
        targets = awk_targets(metafunc.config)
        metafunc.parametrize("awk", targets, ids=target_id, indirect=True, scope="session")


def pytest_report_collectionfinish(config: pytest.Config, items: list[pytest.Item]) -> str | None:
    """Show what is tested after `collected N items`, if a collected test runs awk."""
    if any("awk" in getattr(item, "fixturenames", ()) for item in items):
        return "awk: " + ", ".join(
            target if isinstance(target, str) else f"{target.name} ({target.tag}: {target.awk})"
            for target in awk_targets(config)
        )
    return None


@pytest.fixture(scope="session")
def awk(request: pytest.FixtureRequest, tmp_path_factory: pytest.TempPathFactory) -> Iterator[Awk]:
    target = request.param
    if isinstance(target, str):  # an awk command of the host
        argv = shlex.split(target)
        if not shutil.which(argv[0]):
            pytest.fail(f"{argv[0]}: not found", pytrace=False)
        yield Awk(tuple(argv))
        return
    # a platform: its container runs until the last test, and each awk process is an exec
    # in it. The tests give awk files in the repository and in pytest's temporary directory.
    engine = request.config.getoption("engine")
    try:
        with platforms.container(target, engine, tmp_path_factory.getbasetemp()) as name:
            yield Awk(tuple(shlex.split(target.awk)), (engine, "exec", "--interactive"), name)
    except platforms.PlatformError as error:
        pytest.fail(str(error), pytrace=False)
