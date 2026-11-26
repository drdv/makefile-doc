"""Manage the platforms in test/containers.toml.

When a platform is a container, it is started once in a context manager so that each awk process of
the tests runs in it using `exec`. Nothing but the awk is needed in the image, so old distributions
work too.

A platform can be the HOST machine, in which case a container is not started.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tomllib
from collections.abc import Iterator
from contextlib import contextmanager
from fnmatch import fnmatchcase
from pathlib import Path
from typing import Self

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    ValidationError,
    computed_field,
    model_validator,
)

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = "makefile-doc.awk"  # the script under test (relative to ROOT)
PLATFORMS = ROOT / "test/containers.toml"
ENGINE = "podman"
HOST = "HOST"  # refers to the local machine
# the PATH of awk in a container (/usr/local/bin first: the awk built by a Containerfile)
CONTAINER_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# the version of the script; raises if there is not exactly one match (and mypy is happy)
(VERSION,) = re.findall(r'^\s*VERSION = "([^"]+)"', (ROOT / SCRIPT).read_text(), re.M)


class PlatformError(Exception):
    """A platform that is not valid or whose container cannot be used."""


class Awk(BaseModel):
    """Awk command line (either for the host system or for a container)."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    awk: tuple[str, ...] = ("awk",)  # awk program and its flags (e.g., ("mawk", "-W", "posix"))

    # determine where to execute (in a container or on the host system)
    container_name: str = HOST

    engine: str = ENGINE

    crlf: bool = False  # awk writes \r\n: the output is compared with \n
    ansi_args: bool = False  # awk gets its arguments in the ANSI code page, not in UTF-8

    def _get_host_args(
        self, awk_exec_cmd: list[str], env: dict[str, str]
    ) -> tuple[list[str], dict[str, str]]:
        variables = {"LC_ALL": "C", "PATH": os.environ["PATH"]}
        if os.name == "nt":
            # MSYS programs (e.g., the awk of Git for Windows) glob the arguments they get
            # from a Windows program: `{` and `\` would not reach awk unchanged
            variables["MSYS"] = "noglob"
        return awk_exec_cmd, variables | env

    def _get_container_args(
        self, awk_exec_cmd: list[str], env: dict[str, str]
    ) -> tuple[list[str], None]:
        # the engine runs with the environment of the caller; in the container, `env -i` runs
        # awk with these variables only (not those of the image), as on the host
        variables = {"LC_ALL": "C", "PATH": CONTAINER_PATH} | env
        command = [
            self.engine,
            "exec",
            "--interactive",  # pass stdin to awk
            f"--workdir={ROOT}",
            self.container_name,
            "env",
            "-i",
            *[f"{name}={value}" for name, value in variables.items()],
            *awk_exec_cmd,
        ]
        return command, None

    def command(
        self, *args: str, env: dict[str, str] | None = None
    ) -> tuple[list[str], dict[str, str] | None]:
        """Return the command that runs awk with args, and its environment (None: inherited)."""
        awk_exec_cmd = [*self.awk, *args]
        if self.container_name and self.container_name != HOST:
            return self._get_container_args(awk_exec_cmd, env or {})
        return self._get_host_args(awk_exec_cmd, env or {})

    def __call__(
        self,
        *args: str,
        env: dict[str, str] | None = None,
        stdin: bytes = b"",
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[bytes]:
        """Run awk with args, with `stdin` as its stdin (empty by default)."""
        command, env = self.command(*args, env=env)
        proc = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            input=stdin,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        if self.crlf:
            proc.stdout = proc.stdout.replace(b"\r\n", b"\n")
            proc.stderr = proc.stderr.replace(b"\r\n", b"\n")
        return proc


class Platform(BaseModel):
    """A table of test/containers.toml.

    A container platform runs awk in a container of `image`. A host platform (`host = true`)
    runs awk on this machine: either an awk that is installed, or, with `build`, the binary
    that the Containerfile builds, copied out of the image to `awk` (e.g., test/bin/mawk).
    """

    model_config = ConfigDict(frozen=True, extra="forbid")

    name: str
    awk: str = Field(min_length=1)  # the awk command to test

    image: str | None = None  # the image of the container
    install: str = ""  # a shell command that installs the awk in the container

    build: str | None = None  # a Containerfile that builds the binary of a host platform
    args: dict[str, str] = {}  # arguments for the build (correspond to ARGs in the Containerfile)

    host: StrictBool = False  # run awk on this machine, not in a container
    ci: StrictBool = False  # also run in CI
    explicit: StrictBool = False  # selected only by its name, not by a pattern
    crlf: StrictBool = False  # awk writes \r\n (e.g., a native Windows awk)
    ansi_args: StrictBool = False  # awk gets its arguments in the ANSI code page (native Windows)

    engine: str = ENGINE

    @computed_field  # type: ignore[prop-decorator]
    @property
    def container_name(self) -> str:
        return f"makefile-doc-{self.name}"

    @property
    def awk_argv(self) -> tuple[str, ...]:
        """The awk command split into words; the relative path of a host awk is made absolute."""
        program, *flags = shlex.split(self.awk)
        if self.host and "/" in program:
            program = str(ROOT / program)
        return (program, *flags)

    @property
    def tag(self) -> str:
        """The image: `image`, the name of the one that `build` makes, or HOST (neither).

        The name of a built image ends with a hash of the Containerfile and its
        arguments: the image is built again when one of them changes, and only then.
        """
        if self.image:
            return self.image

        if not self.build:
            return HOST

        content = (ROOT / self.build).read_bytes() + json.dumps(self.args, sort_keys=True).encode()
        # named after the Containerfile, not the platform: platforms with the same build and
        # args (e.g., [host-mawk] and [host-mawk-posix]) share the image (and the binary)
        name = Path(self.build).stem
        return f"localhost/makefile-doc-{name}:{hashlib.sha256(content).hexdigest()[:12]}"

    @model_validator(mode="after")
    def check_image_or_build(self) -> Self:
        if self.host:
            if self.image is not None or self.install:
                raise ValueError("a host platform has no image or install")
            if self.build is not None and "/" not in shlex.split(self.awk)[0]:
                raise ValueError("with build, the awk of a host platform is a path (test/bin/...)")
        elif self.image is None or self.build is not None:
            raise ValueError("a container platform has an image and no build")
        if self.args and self.build is None:
            raise ValueError("args needs build")
        return self

    @classmethod
    def from_table(cls, name: str, table: dict[str, object], engine: str = ENGINE) -> Self:
        """Return an instance of Platform from a table."""
        try:
            return cls.model_validate({"name": name, **table, "engine": engine})
        except ValidationError as error:
            raise PlatformError(f"[{name}] {error}") from None

    @contextmanager
    def run(self, *writable: Path, keep_container: bool = False) -> Iterator[Awk]:
        """Run the platform: yield the Awk that runs its awk."""
        if self.host:
            if self.build:
                self._export_binary()
            self._verify_awk()
            yield Awk(
                awk=self.awk_argv,
                engine=self.engine,
                crlf=self.crlf,
                ansi_args=self.ansi_args,
            )
            return

        mounts = [f"--volume={ROOT}:{ROOT}:ro,z"] + [
            f"--volume={path}:{path}:z" for path in writable
        ]

        self.remove_container()

        self._engine_run(
            "run",
            "--detach",
            "--name",
            self.container_name,
            *mounts,
            self.tag,
            "sh",
            "-c",
            "while :; do sleep 3600; done",
            what=f"cannot start {self.name}",
        )  # sleep: the container only waits for the awk processes of the tests

        try:
            self._install_in_container()
            yield Awk(awk=self.awk_argv, container_name=self.container_name, engine=self.engine)
        finally:
            self.remove_container(keep_container)

    def _install_in_container(self) -> None:
        if self.install:
            self._engine_run(
                "exec",
                self.container_name,
                "sh",
                "-c",
                self.install,
                what="the install command failed",
            )

        self._verify_awk()

    def _verify_awk(self) -> None:
        awk = self.awk_argv[0]
        if self.host:
            if not shutil.which(awk):
                raise PlatformError(f"{awk} is not available on the host platform")
            return

        # with the PATH that the tests use (this also checks that env is in the image)
        self._engine_run(
            "exec",
            self.container_name,
            "env",
            "-i",
            f"PATH={CONTAINER_PATH}",
            "sh",
            "-c",
            f"command -v {shlex.quote(awk)}",
            what=f"{awk} (or env) is not in {self.name} (add an install command)",
        )

    def image_exists(self) -> bool:
        return self.tag == HOST or self._engine_run("image", "inspect", self.tag) == 0

    def _export_binary(self) -> None:
        """Copy the binary of the image (at /awk) to the awk of a host platform.

        A stamp file next to the binary holds the tag of the image it comes from: the binary
        is copied again when the image changes (the Containerfile or its arguments), and only
        then. An up-to-date binary needs no container engine.
        """
        target = Path(self.awk_argv[0])
        stamp = target.with_name(f".{target.name}.image")
        if target.exists() and stamp.exists() and stamp.read_text() == self.tag:
            return

        self.build_image()
        target.parent.mkdir(parents=True, exist_ok=True)
        name = f"{self.container_name}-export"
        self._engine_run("rm", "--force", name)
        # the container is created (not started) only to copy the binary out of it
        self._engine_run(
            "create", "--name", name, self.tag, "/awk", what=f"[{self.name}] cannot create {name}"
        )
        try:
            self._engine_run(
                "cp", f"{name}:/awk", str(target), what=f"[{self.name}] cannot copy to {target}"
            )
        finally:
            self._engine_run("rm", "--force", name)
        stamp.write_text(self.tag)

    def remove_container(self, keep_container: bool = False) -> None:
        """Remove a container at once (Send SIGKILL because sh as PID 1 ignores SIGTERM)."""
        if not keep_container:
            self._engine_run("kill", self.container_name)  # send SIGKILL directly
            self._engine_run("rm", "--force", self.container_name)

    def build_image(self) -> None:
        if self.build and not self.image_exists():
            build_args = [f"--build-arg={key}={value}" for key, value in self.args.items()]
            # the default context is (ROOT / platform.build).parent (man podman-build)
            self._engine_run(
                "build",
                "--file",
                str(ROOT / self.build),
                "--tag",
                self.tag,
                *build_args,
                what=f"[{self.name}] cannot build {self.build}",
            )

    def _engine_run(self, *args: str, what: str | None = None) -> int:
        try:
            proc = subprocess.run([self.engine, *args], capture_output=True, text=True, check=False)
        except OSError as error:
            raise PlatformError(f"cannot run the container engine: {error}") from None
        if what is not None and proc.returncode:
            raise PlatformError(f"{what}\n{proc.stdout}{proc.stderr}".rstrip())
        return proc.returncode


def extended(name: str, tables: dict[str, dict[str, object]]) -> dict[str, object]:
    """Return the table `name` with the keys of the table it extends (`extends = "other"`).

    Its own keys replace those of the other table, which can itself extend another one.
    """
    table, chain = dict(tables[name]), [name]
    while "extends" in table:
        base = table.pop("extends")
        if not isinstance(base, str) or base not in tables:
            raise PlatformError(f"[{name}] extends {base!r}: not a platform")
        if base in chain:
            raise PlatformError(f"[{name}] extends itself: {' -> '.join([*chain, base])}")
        chain.append(base)
        table = dict(tables[base]) | table
    return table


def load(
    platform_names: tuple[str, ...],
    path: Path = PLATFORMS,
    engine: str = ENGINE,
    with_explicit: bool = False,
) -> dict[str, Platform]:
    """Return the (validated) platforms of a TOML file that match platform_names.

    A name can be a shell-style pattern (e.g. "debian*", or "*" for all of them); a name
    that matches no platform is an error. A pattern does not match a platform with
    `explicit = true`, unless with_explicit is true. `engine` is the container engine of
    every platform.
    """
    try:
        raw_tables = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise PlatformError(f"cannot read {path}: {error}") from None
    tables = {name: extended(name, raw_tables) for name in raw_tables}

    def matches(name: str, pattern: str) -> bool:
        if name == pattern:
            return True
        return fnmatchcase(name, pattern) and (with_explicit or not tables[name].get("explicit"))

    unknown = [p for p in platform_names if not any(matches(name, p) for name in tables)]
    if unknown:
        raise PlatformError(f"not a platform of {path.name}: {', '.join(unknown)}")
    return {
        name: Platform.from_table(name, table, engine)
        for name, table in tables.items()
        if any(matches(name, p) for p in platform_names)
    }


def get_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)

    list_parser = sub.add_parser("list", help="print the names of the platforms")
    list_parser.add_argument("--ci", action="store_true", help="only those with ci = true")
    list_parser.add_argument("--json", action="store_true", help="as JSON, with `build`")

    image_parser = sub.add_parser("image", help="print the image of a platform")
    image_parser.add_argument("name")

    return parser.parse_args()


def main() -> int:
    args = get_args()
    try:
        platforms = load(("*",), with_explicit=True)
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
    except PlatformError as error:
        sys.exit(f"ERROR: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
