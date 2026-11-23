"""Shared pytest configuration: which awk to test, and how to run it."""

from collections.abc import Iterator

import platforms
import pytest

DEFAULT_PLATFORM = "host-awk"  # without --platform: the awk of this machine

PLATFORMS = pytest.StashKey[list[platforms.Platform]]()


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("makefile-doc")
    group.addoption(
        "--platform",
        action="append",
        default=[],
        metavar="NAME",
        help=f"platform of test/containers.toml whose awk to test: a name or a pattern, "
        f"e.g., 'debian*' (can be repeated; default: {DEFAULT_PLATFORM})",
    )
    group.addoption(
        "--engine",
        default=platforms.ENGINE,
        metavar="ENGINE",
        help=f"container engine (default: {platforms.ENGINE})",
    )
    group.addoption("--update", action="store_true", help="rewrite the expected outputs")
    group.addoption(
        "--new-parser",
        action="store_true",
        help="trace cases: trace the new parser (parser.awk) instead of the current one",
    )


def pytest_configure(config: pytest.Config) -> None:
    names = tuple(config.getoption("platform")) or (DEFAULT_PLATFORM,)
    try:
        loaded_platforms = list(platforms.load(names, engine=config.getoption("engine")).values())
    except platforms.PlatformError as error:
        raise pytest.UsageError(str(error)) from None
    if config.getoption("update") and len(loaded_platforms) != 1:
        raise pytest.UsageError("--update rewrites the expected outputs: give one platform")
    config.stash[PLATFORMS] = loaded_platforms


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "awk" in metafunc.fixturenames:
        loaded_platforms = metafunc.config.stash[PLATFORMS]
        metafunc.parametrize(
            "awk",
            loaded_platforms,
            ids=lambda platform: platform.name,
            indirect=True,
            scope="session",
        )


def pytest_report_header(config: pytest.Config) -> str:
    """Show the platforms of the run (and the engine, if one of them is a container)."""
    loaded_platforms = config.stash[PLATFORMS]
    header = "platforms: " + ", ".join(p.name for p in loaded_platforms)
    if not all(p.host for p in loaded_platforms):
        header += f" (engine: {loaded_platforms[0].engine})"
    return header


@pytest.fixture(scope="session")
def awk(
    request: pytest.FixtureRequest,
    tmp_path_factory: pytest.TempPathFactory,
) -> Iterator[platforms.Awk]:
    """The awk of a platform (the parameter), which runs in its container if it has one."""
    platform: platforms.Platform = request.param
    try:
        with platform.run(tmp_path_factory.getbasetemp()) as awk:
            yield awk
    except platforms.PlatformError as error:
        pytest.fail(str(error), pytrace=False)
