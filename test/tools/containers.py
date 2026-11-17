"""Run the tests on the platforms of test/containers.toml, in containers.

usage: containers.py list [--json]
       containers.py run NAME [--engine ENGINE] [--no-build] [PYTEST_ARG ...]

`run` builds the image of the platform and runs pytest in it, on the repository mounted
read-only. With --no-build the image is used as it is (CI restores it from its cache).
See test/README.md.
"""

import argparse
import json
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PLATFORMS = ROOT / "test/containers.toml"
CONTAINERFILE = "test/Containerfile"  # the common part of every image
KEYS = {"image", "build", "awk", "install"}
PYTEST = ["uv", "run", "--frozen", "--no-sync", "pytest"]
TESTS = ["test/test_integration.py", "test/test_unit.py"]


def load(path: Path = PLATFORMS) -> dict[str, dict[str, str]]:
    """Return the platforms of a file, checked."""
    platforms = tomllib.loads(path.read_text())
    for name, platform in platforms.items():
        if unknown := set(platform) - KEYS:
            raise ValueError(f"[{name}]: unknown key {sorted(unknown)[0]}")
        if ("image" in platform) == ("build" in platform):
            raise ValueError(f"[{name}]: give either image or build")
        if not platform.get("awk"):
            raise ValueError(f"[{name}]: awk is missing")
    return platforms


def commands(name: str, platform: dict[str, str], engine: str, args: list[str]) -> list[list[str]]:
    """Return the commands of the engine that build the image of a platform and run pytest."""
    cmds = []
    base = platform.get("image")
    if base is None:  # build the base image first
        base = f"localhost/makefile-doc-base:{name}"
        cmds.append([engine, "build", "--file", platform["build"], "--tag", base, "."])
    image = f"localhost/makefile-doc-test:{name}"
    cmds.append(
        [engine, "build", "--file", CONTAINERFILE, "--tag", image]
        + ["--build-arg", f"BASE={base}", "--build-arg", f"INSTALL={platform.get('install', '')}"]
        + ["."]
    )
    # `Z`: let the container read the repository on a host with SELinux
    cmds.append(
        [engine, "run", "--rm", "--volume", f"{ROOT}:/src:ro,Z"]
        + ["--env", f"AWK={platform['awk']}", image, *PYTEST, *TESTS, *args]
    )
    return cmds


def run(name: str, engine: str, build_image: bool, args: list[str]) -> int:
    platforms = load()
    if name not in platforms:
        sys.exit(f"ERROR: {name}: not a platform of {PLATFORMS.relative_to(ROOT)}")
    *builds, test = commands(name, platforms[name], engine, args)
    if not build_image:
        builds = []
    else:
        print(f"[{name}] building the image", flush=True)
    for build in builds:  # show the output of a build only if it fails
        proc = subprocess.run(build, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if proc.returncode:
            sys.stdout.write(proc.stdout.decode(errors="replace"))
            sys.exit(f"ERROR: [{name}] {' '.join(build[:2])} failed")
    return subprocess.run(test, cwd=ROOT).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)
    list_parser = sub.add_parser("list", help="print the names of the platforms")
    list_parser.add_argument("--json", action="store_true", help="as a JSON list")
    run_parser = sub.add_parser("run", help="run the tests on a platform")
    run_parser.add_argument("name")
    run_parser.add_argument("--engine", default="podman", help="podman (default) or docker")
    run_parser.add_argument("--no-build", action="store_true", help="use the image as it is")
    args, pytest_args = parser.parse_known_args()
    try:
        if args.command == "list":
            names = list(load())
            print(json.dumps(names) if args.json else "\n".join(names))
            return 0
        return run(args.name, args.engine, not args.no_build, pytest_args)
    except (OSError, ValueError) as error:
        sys.exit(f"ERROR: {error}")


if __name__ == "__main__":
    sys.exit(main())
