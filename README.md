# makefile-doc

[![CI][ci-badge]][ci]

Generate `make help` from comments in your Makefile.

`makefile-doc.awk` is a single awk script with no dependencies other than `awk`. It reads
your Makefiles and prints the targets and variables you documented, with sections, colors,
and optional export to HTML and LaTeX.

```Makefile
help: ## Show this help
	@awk -f makefile-doc.awk $(MAKEFILE_LIST)

## Number of parallel jobs
JOBS := 4

##@
##@ --- Build ---
##@

## Compile the project
build:

## Run the tests
## (set `JOBS` to run them in parallel)
test: build

##@
##@ --- Release ---
##@

##! Publish the release (cannot be undone)
publish: test

##% Use `publish` instead
upload:
```

Running `make` prints:

```
-----------------------
Available targets:
-----------------------
help      Show this help

 --- Build ---

build     Compile the project
test      Run the tests
          (set `JOBS` to run them in parallel)

 --- Release ---

publish   Publish the release (cannot be undone)
upload    Use `publish` instead

-----------------------
Command-line arguments:
-----------------------
JOBS      Number of parallel jobs
-----------------------
```

In a terminal the names are colored: blue by default, red for `publish` (`##!`), yellow for
the deprecated `upload` (`##%`), green for the sections. A colored example can be seen
[here](https://drdv.github.io/blog/202511-makefile-doc).

The script started as a more elaborate version of
[this one-liner](https://gist.github.com/prwhite/8168133).

**Contents:** [Install](#install) ·
[Writing docs](#writing-docs) ·
[Options](#options) ·
[Substitutions](#substitutions) ·
[Export to HTML and LaTeX](#export-to-html-and-latex) ·
[Limitations](#limitations) ·
[Development](#development)

## Install

### Download on first use

Define the first target of your `Makefile` (or if it is not the first target, set
`.DEFAULT_GOAL := help`) as:

```Makefile
help: VER := v1.8
help: URL := https://github.com/drdv/makefile-doc/releases/download/$(VER)/makefile-doc.awk
help: SCR := $(HOME)/.local/share/makefile-doc/makefile-doc-$(VER).awk
help: ## show this help
	@test -f $(SCR) || { mkdir -p $(dir $(SCR)) && \
		curl -fsSL -o $(SCR).tmp $(URL) && mv $(SCR).tmp $(SCR); }
	@awk -f $(SCR) $(MAKEFILE_LIST)
```

This downloads version `VER` of the awk script on first use (into
`~/.local/share/makefile-doc`) and reuses it afterwards. To upgrade, change `VER`:
the new version is downloaded next to the old one.

### Manual installation

Download `makefile-doc.awk` from the
[releases](https://github.com/drdv/makefile-doc/releases), place it in a directory of your
choice and define the first target of your `Makefile` as:

```Makefile
help: ## show this help
	@awk -f /path/to/makefile-doc.awk $(MAKEFILE_LIST)
```

If your awk supports `AWKPATH` (e.g., gawk), you can use it to locate the script without
its full path.

## Writing docs

Docs are comments that start with one of four tokens. Targets and variables are called
*anchors* below: they are what docs and sections are attached to.

| Token | Meaning                             | Default color |
|-------|-------------------------------------|---------------|
| `##`  | doc of a target or a variable       | blue          |
| `##!` | doc of an anchor that needs care    | red           |
| `##%` | doc of a deprecated anchor          | yellow        |
| `##@` | section title                       | green         |

```Makefile
## doc of a variable the user might want to set on the command line
MY_VARIABLE = 42

## doc above a target, line 1
## line 2
target1:

target2: ## inline doc
```

### Docs of targets and variables

- A doc is placed **above** its anchor (one or more lines) or **inline**, after it[^inline].
  If both are present, the doc above is used.
- In a multi-line doc, only the first line needs the `##!` or `##%` token; the other
  lines can start with `##`.
- Deprecated anchors (`##%`) can be hidden with `-v DEPRECATED=0`.
- Between a doc and its anchor there can be blank lines, comments, conditionals (`ifeq`
  ... `endif`) and lines of special targets such as `.PHONY: target` or `.ONESHELL:`.
- Any other line discards the doc above it: `include`, `vpath`, `define`, `export` without
  an assignment, a function call such as `$(info ...)`, and a comment banner (a line of
  three or more `#` only, e.g., `###`).
- On a target line, a `##` after an inline recipe (`target: ; command ## text`) is part
  of the recipe, not a doc.
- Docs and sections can be indented with spaces or tabs. In a rule, a line that starts
  with the recipe prefix (a tab by default) is a recipe line, not a doc.

### Sections

- A section is one or more lines that start with `##@`. Every line of a multi-line
  section needs the token; blank lines between them are ignored.
- A section is displayed above the next documented anchor, so it needs at least one after
  it (a hidden deprecated one is enough).
- A section is not displayed if all the anchors of its kind (all targets, or all
  variables) are hidden.

### Special kinds of targets

- [Double-colon](https://www.gnu.org/software/make/manual/html_node/Double_002dColon.html)
  targets are displayed as `target-name~index`, and each rule can have its own doc.
- [Grouped](https://www.gnu.org/software/make/manual/html_node/Multiple-Targets.html)
  targets are displayed with a `&` at the end, e.g., `t1 t2 t3&` (also in double-colon
  form).
- Targets and variables documented inside a `define` block are displayed (e.g., for canned
  recipes).

See `test/fixtures/Makefile.*` for many more examples.

## Options

Options are passed to `awk` with `-v OPTION=value`:

```Makefile
help: ## show this help
	@awk -v DEPRECATED=0 -v PADDING=. -f makefile-doc.awk $(MAKEFILE_LIST)
```

| Option            | Values (default)           | Meaning                                   |
|-------------------|----------------------------|-------------------------------------------|
| `VARS`            | `0`, (`1`)                 | show documented variables                 |
| `DEPRECATED`      | `0`, (`1`)                 | show deprecated anchors                   |
| `PADDING`         | one character (space)      | fills the gap between anchors and docs    |
| `OFFSET`          | `0`, `1`, (`2`), ...       | number of spaces between anchors and docs |
| `COLOR`           | `0`, (`1`)                 | `0` turns off all colors                  |
| `OUTPUT_FORMAT`   | (`ANSI`), `HTML`, `LATEX`  | see [export](#export-to-html-and-latex)   |
| `EXPORT_THEME`    | see below                  | colors of the HTML and LaTeX output       |
| `SUB`, `DSUB`     | see below                  | see [Substitutions](#substitutions)       |
| `RECIPEPREFIX`    | one character (tab)        | the `.RECIPEPREFIX` of your Makefile      |
| `TARGETS_REGEX`   | a regex                    | replaces the regex that matches targets   |
| `VARIABLES_REGEX` | a regex                    | replaces the regex that matches variables |

`COLOR` defaults to `0` when the environment variable `NO_COLOR` is set to a non-empty
value (see [no-color.org](https://no-color.org)).

An invalid value is an error: all the invalid options are reported, nothing else is
printed and the exit status is 1.

Running `awk -f makefile-doc.awk` without a Makefile prints the options with their current
values.

### Colors

| Option             | Default       | Used for                              |
|--------------------|---------------|---------------------------------------|
| `COLOR_DEFAULT`    | `34` (blue)   | anchors whose docs start with `##`    |
| `COLOR_ATTENTION`  | `31` (red)    | anchors whose docs start with `##!`   |
| `COLOR_DEPRECATED` | `33` (yellow) | anchors whose docs start with `##%`   |
| `COLOR_SECTION`    | `32` (green)  | sections                              |
| `COLOR_BACKTICKS`  | `0` (off)     | text in backticks in docs             |

A color is the parameter of an [ANSI escape
code](https://en.wikipedia.org/wiki/ANSI_escape_code#Select_Graphic_Rendition_parameters),
e.g., the `34` in `\033[34m` for blue. The supported parameters are `0`, `1`, `3`, `4`,
`9`, `30`-`37`, `40`-`47`, `90`-`97` and `100`-`107`.

## Substitutions

### `SUB`: rename an anchor and list its values

A target is sometimes defined through a variable or an expression. `SUB` replaces the
name that is displayed with a label and adds a list of values to the docs. Its format is
`NAME[:LABEL]:[VALUES]`, where `VALUES` are separated by spaces; several substitutions
are separated by `;`. For example, running `make` with

```Makefile
NOTES := my-budget trip-info misc
OPEN_NOTES := $(addprefix open-,$(NOTES))

help: VFLAG := -v SUB='$$(OPEN_NOTES):open-:$(NOTES)'
help: ## Show this help
	@awk $(VFLAG) -f makefile-doc.awk $(MAKEFILE_LIST)

## Notes:
$(OPEN_NOTES):
```

prints

```
-----------------------
Available targets:
-----------------------
help    Show this help
open-   Notes:
        my-budget
        trip-info
        misc
-----------------------
```

Variables can be substituted in the same way.

Only the first two colons are separators, so values can contain colons (e.g., URLs). With
two or more colons, the text between the first two is always the label:

| `SUB`       | Displayed name | Values |
|-------------|----------------|--------|
| `t:a b`     | `t`            | `a b`  |
| `t:new:a b` | `new`          | `a b`  |
| `t:t:/a:b`  | `t`            | `/a:b` |
| `t:/a:b`    | `/a`           | `b`    |

To give a value with a colon without renaming the anchor, repeat its name as the label
(third row).

### `SUB` parameters

A substitution can start with parameters that control how the values are displayed:
`<p1:v1,...>NAME[:LABEL]:[VALUES]`.

| Parameter | Meaning                                                  | Default |
|-----------|----------------------------------------------------------|---------|
| `L`       | `0`: values start on the line of the doc, `1`: on the next | `1`     |
| `M`       | `0`: all values on one line, `1`: one value per line       | `1`     |
| `N`       | maximum number of values to display (`-1`: no limit)       | `-1`    |
| `S`       | separator added after each value but the last              | none    |
| `P`       | prefix added to each value                                 | none    |
| `I`       | initial string, e.g., `{`                                  | none    |
| `T`       | termination string, e.g., `}`                              | none    |

For example, `-v SUB='<L:0,M:0,I:{,T:},S:\\,>t:a b c'` displays `t   doc {a, b, c}`.

- In a parameter, only the first colon is a separator: `S::` sets the separator to a
  colon and `P:x:y` the prefix to `x:y`.
- A comma in a parameter value is written `\,`; on the command line the backslash has to
  be doubled (`\\,`).
- A parameter value cannot contain `>`, which ends the parameters.

See the `Makefile` of this project and `test/integration/sub-*.test` for more examples.

### `DSUB`: replace text in docs

`DSUB` replaces text in the docs themselves. Its format is `NAME:VALUES`; everything after
the first colon is the value, so it can contain colons. For example, with
`-v DSUB='$$(DEPS):$(DEPS)'`, the target

```Makefile
DEPS := x y
## Prerequisites: $(DEPS)
t: $(DEPS)
```

is documented as

```
t   Prerequisites: x y
```

Several substitutions are separated by `;` and applied in the order given. If a name
appears more than once, the last value is used. Values cannot contain newlines.

## Export to HTML and LaTeX

`-v OUTPUT_FORMAT=html` and `-v OUTPUT_FORMAT=latex` print the documentation as HTML or
LaTeX. The HTML output is a fragment to paste into a page: a `<style>` element followed by
a `<div class="makefile-doc">`; the names of all its classes start with `makefile-doc`.

The ANSI colors are mapped to the
[Solarized](https://github.com/altercation/solarized?tab=readme-ov-file#the-values) dark
palette by default.

`EXPORT_THEME` changes this mapping. Its format is `ANSI_COLOR_PARAMETER:HEX_COLOR[,...]`,
with the hex color written without `#`. The tokens `FG` and `BG` set the foreground and
the background. Colors that are not listed keep their default. For example, to use the
[Dracula](https://github.com/dracula/dracula-theme?tab=readme-ov-file#color-palette) theme:

```Makefile
DRACULA := 30:21222c,31:ff5555,32:50fa7b,33:f1fa8c,34:bd93f9,35:ff79c6,36:8be9fd,37:f8f8f2
DRACULA := $(DRACULA),90:6272a4,91:ff6e6e,92:69ff94,93:ffffa5,94:d6acff,95:ff92df,96:a4ffff
DRACULA := $(DRACULA),97:ffffff,BG:000000,FG:AAAAAA

help: ## show this help
	@awk \
		-v EXPORT_THEME=$(DRACULA) \
		-v OUTPUT_FORMAT=html \
		-f makefile-doc.awk $(MAKEFILE_LIST)
```

`EXPORT_THEME` has no effect on the output in the terminal.

## Limitations

`makefile-doc` finds targets and variable assignments with awk regular expressions. It is
not a GNU Make parser, so some valid constructs are not recognized.

### Targets

- **An escaped `#` in a target name is not handled.**
  ```makefile
  foo\#bar:
  ```
  GNU Make treats the `#` as part of the name; the regex always excludes it.

- **An escaped `:` in a target name is not handled.**
  ```makefile
  foo\:bar:
  ```
  The escaped colon is taken for the rule separator.

- **A colon inside a reference in a target name is not handled.**
  ```makefile
  $(SRCS:.c=.o):
  ```
  The target (here with a substitution reference) is not recognized.

Escaped spaces are displayed as written: `foo\ bar:` is shown as `foo\ bar`, which is how
the target is invoked (`make foo\ bar`).

### Variables

- Names are not expanded (by design): `$(PREFIX)_FLAGS := -O2` is displayed as
  `$(PREFIX)_FLAGS`.
- Multi-line variables (`define NAME` ... `endef`) cannot be documented: `define` discards
  the doc above it.

### Non-ASCII names

Alignment assumes ASCII names. With awks that count bytes (mawk, busybox awk), a non-ASCII
target, variable or `SUB` label is misaligned by a few spaces, and `PADDING` must be an
ASCII character.

## Development

### Supported awk implementations

The script is tested on Fedora, Ubuntu and macOS with:

| awk                                              | Version                                  |
|--------------------------------------------------|------------------------------------------|
| [gawk](https://www.gnu.org/software/gawk)        | `5.1` to `5.3` (also with `--posix`)     |
| [mawk](https://invisible-island.net/mawk)        | `1.3.4 20260302` (also with `-W posix`)  |
| [nawk](https://github.com/onetrueawk/awk)        | `20240728`                               |
| [busybox awk](https://www.busybox.net/)          | `1.35.0`                                 |
| [wak](https://github.com/raygard/wak)            | `v24.10`                                 |
| [goawk](https://github.com/benhoyt/goawk)        | `v1.30.0`                                |

Generating the documentation works with GNU Make 3.81 or later.

### Running the tests

The development `Makefile` needs GNU Make 4.0 or later and Python 3.11 or later (standard
library only). `make help` lists its targets.

| Command                         | What it runs                                         |
|---------------------------------|------------------------------------------------------|
| `make test@awk utest@awk`       | integration and unit tests with the system's `awk`   |
| `make test@mawk utest@mawk`     | the same with another awk (see `make help`)          |
| `make test@all utest@all`       | the same with every supported awk                    |
| `make lint`                     | lints the awk code and the Python test tools         |
| `make check`                    | `lint` and all the tests with the system's `awk`     |

`make lint` needs `gawk` and [uv](https://docs.astral.sh/uv). The awk implementations
other than `awk` and `gawk` are downloaded and built into
`test/bin/` on first use. This needs a standard build environment, plus `bison` for nawk
and Go for goawk (e.g., `dnf install bison golang`). The busybox binary is available for
Linux only.

See [test/README.md](test/README.md) for the test format and for how to report and fix
bugs.

### Performance

Time to document two large real Makefiles, with docs added on every 5th target or variable
(`make bench@all`, best of 5 runs, makefile-doc v1.8, Intel Core i7-13700H, Fedora 43,
November 2026):

| awk           | GCC Makefile.in (69k lines) | Linux Makefile (2k lines) |
|---------------|----------------------------:|--------------------------:|
| mawk 20260302 |               127 ms (1.0×) |             8.4 ms (1.0×) |
| gawk 5.3.2    |               249 ms (2.0×) |            18.8 ms (2.2×) |
| goawk 1.30.0  |               312 ms (2.5×) |            13.9 ms (1.7×) |
| nawk 20240728 |               522 ms (4.1×) |            31.5 ms (3.7×) |
| wak 24.10     |             2104 ms (16.6×) |            115 ms (13.7×) |
| bawk 1.35.0   |             3187 ms (25.1×) |            176 ms (21.0×) |

## License

[Apache-2.0](LICENSE)

[^inline]: Inline docs on variables need care, because in GNU Make
    ["trailing space characters are not stripped from variable
    values"](https://www.gnu.org/software/make/manual/html_node/Simple-Assignment.html):
    the spaces before the `##` become part of the value.

[ci-badge]: https://github.com/drdv/makefile-doc/actions/workflows/main.yml/badge.svg
[ci]: https://github.com/drdv/makefile-doc/actions/workflows/main.yml
