"""The platforms of test/containers.toml: awk runs in a container, the tests on the host.

usage: platforms.py list [--ci] [--json]    the names of the platforms
       platforms.py image NAME              the image of a platform

A platform is tested with `pytest --platform NAME` (see conftest.py): its container is
started once, and each awk process of the tests runs in it with `exec`. Nothing but the
awk is needed in the image, so old distributions work too. See test/README.md.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tomllib
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = ROOT / "test/containers.toml"
KEYS = {"image", "build", "args", "awk", "install", "ci"}


class PlatformError(Exception):
    """A platform that is not valid or whose container cannot be used."""


@dataclass(frozen=True)
class Platform:
    """A table of test/containers.toml."""

    name: str
    awk: str  # the awk command to test
    image: str | None = None  # the base image, or
    build: str | None = None  # a Containerfile that builds it
    args: dict[str, str] = field(default_factory=dict)  # the build arguments of `build`
    install: str = ""  # a shell command that installs the awk in the container
    ci: bool = False  # also run in CI

    @property
    def tag(self) -> str:
        """The image to run: `image`, or the name of the one that `build` makes.

        The name of a built image ends with a hash of the Containerfile and its
        arguments: the image is built again when one of them changes, and only then.
        """
        if self.image:
            return self.image
        content = (ROOT / self.build).read_bytes() + json.dumps(self.args, sort_keys=True).encode()
        return f"localhost/makefile-doc-{self.name}:{hashlib.sha256(content).hexdigest()[:12]}"


def load(path: Path = PLATFORMS) -> dict[str, Platform]:
    """Return the platforms of a file, checked."""
    platforms = {}
    for name, table in tomllib.loads(path.read_text()).items():
        if unknown := set(table) - KEYS:
            raise PlatformError(f"[{name}]: unknown key {sorted(unknown)[0]}")
        if ("image" in table) == ("build" in table):
            raise PlatformError(f"[{name}]: give either image or build")
        if not table.get("awk"):
            raise PlatformError(f"[{name}]: awk is missing")
        if "args" in table and "build" not in table:
            raise PlatformError(f"[{name}]: args needs build")
        if not isinstance(table.get("ci", False), bool):
            raise PlatformError(f"[{name}]: ci should be true or false")
        platforms[name] = Platform(name, **table)
    return platforms


def engine_run(engine: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([engine, *args], capture_output=True, text=True, check=False)


def checked(proc: subprocess.CompletedProcess, what: str) -> None:
    if proc.returncode:
        raise PlatformError(f"{what}\n{proc.stdout}{proc.stderr}".rstrip())


@contextmanager
def container(platform: Platform, engine: str, *writable: Path) -> Iterator[str]:
    """Start the container of a platform, yield its name, and remove it at the end.

    The repository is mounted read-only and the `writable` directories read-write, at
    the same paths as on the host (`z`: let the container use them on a host with
    SELinux), so the awk in the container sees the files that the tests name.
    """
    if not shutil.which(engine):
        raise PlatformError(f"{engine}: not found (the container engine)")
    tag = platform.tag
    if platform.build and engine_run(engine, "image", "inspect", tag).returncode:
        build_args = [f"--build-arg={key}={value}" for key, value in platform.args.items()]
        context = str((ROOT / platform.build).parent)
        proc = engine_run(
            engine,
            "build",
            "--file",
            str(ROOT / platform.build),
            "--tag",
            tag,
            *build_args,
            context,
        )
        checked(proc, f"[{platform.name}] cannot build {platform.build}")

    name = f"makefile-doc-{platform.name}"
    remove(engine, name)  # left by a run that was interrupted
    mounts = [f"--volume={ROOT}:{ROOT}:ro,z"] + [f"--volume={path}:{path}:z" for path in writable]
    # sleep: the container only waits for the awk processes of the tests
    proc = engine_run(
        engine,
        "run",
        "--detach",
        "--name",
        name,
        *mounts,
        tag,
        "sh",
        "-c",
        "while :; do sleep 3600; done",
    )
    checked(proc, f"[{platform.name}] cannot start {tag}")
    try:
        if platform.install:
            proc = engine_run(engine, "exec", name, "sh", "-c", platform.install)
            checked(proc, f"[{platform.name}] the install command failed")
        awk = platform.awk.split()[0]
        proc = engine_run(engine, "exec", name, "sh", "-c", f"command -v {awk}")
        checked(proc, f"[{platform.name}] {awk} is not in {tag} (add an install command)")
        yield name
    finally:
        remove(engine, name)


def remove(engine: str, name: str) -> None:
    """Remove a container at once (kill first: sh as PID 1 ignores the signal of a stop)."""
    engine_run(engine, "kill", name)
    engine_run(engine, "rm", "--force", name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)
    list_parser = sub.add_parser("list", help="print the names of the platforms")
    list_parser.add_argument("--ci", action="store_true", help="only those with ci = true")
    list_parser.add_argument("--json", action="store_true", help="as JSON, with `build`")
    image_parser = sub.add_parser("image", help="print the image of a platform")
    image_parser.add_argument("name")
    args = parser.parse_args()
    try:
        platforms = load()
        if args.command == "image":
            print(platforms[args.name].tag)
        else:
            chosen = [p for p in platforms.values() if p.ci or not args.ci]
            if args.json:  # for the matrix of CI
                print(json.dumps([{"name": p.name, "build": bool(p.build)} for p in chosen]))
            else:
                print("\n".join(p.name for p in chosen))
    except KeyError:
        sys.exit(f"ERROR: {args.name}: not a platform of {PLATFORMS.relative_to(ROOT)}")
    except (OSError, PlatformError) as error:
        sys.exit(f"ERROR: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
