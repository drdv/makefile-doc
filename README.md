# Awk script for Makefile docs

[![CI](https://github.com/drdv/makefile-doc/actions/workflows/main.yml/badge.svg)](https://github.com/drdv/makefile-doc/actions/workflows/main.yml)

The `makefile-doc.awk` script can be used to extract documentation from a Makefile. It
is simply a more elaborate, POSIX-compliant, version of
[this](https://gist.github.com/prwhite/8168133) one-liner. An example of the generated
documentation can be seen [here](https://drdv.github.io/blog/202511-makefile-doc).

## How to use

### Make available on the fly

Define the first target of your `Makefile` (or if it is not the first target, set
`.DEFAULT_GOAL := help`) as:

```Makefile
help: URL := github.com/drdv/makefile-doc/releases/latest/download/makefile-doc.awk
help: DIR := $(HOME)/.local/share/makefile-doc
help: SCR := $(DIR)/makefile-doc.awk
help: ## show this help
	@test -f $(SCR) || wget -q -P $(DIR) $(URL)
	@awk -f $(SCR) $(MAKEFILE_LIST)
```

This will download the awk script on the fly (if it doesn't exist in
`~/.local/share/makefile-doc`). As an alternative of `wget` you could use `curl`:

```bash
curl -sLO --create-dirs --output-dir $(DIR) $(URL)
```

### Manual installation

Define the first target of your `Makefile` as:

```Makefile
help: ## show help
	@awk -f makefile-doc.awk $(MAKEFILE_LIST)
```

Manually download and place the `makefile-doc.awk` script on your `AWKPATH`.

## Docs syntax

```Makefile
## doc of a CLA variable the user might want to know about
MY_VARIABLE = 42

## top doc line 1
## line 2
target1:

target2: ## inline doc (ignored if there are top docs as well)
```

We refer to targets / variables as anchors (for docs/sections).

+ Docs of anchors start with tokens `##` or `##!` or `##%` (they can be both above an
  anchor or inline).

+ To emphasize anchors that are "special" in some way, start their docs with `##!` (this
  changes their color).

+ To indicate that an anchor is deprecated, start its docs with `##%` (this changes its
  color and allows to filter it out, see the `DEPRECATED` flag below).

+ Multi-line docs can be added above an anchor, inline docs are ignored when top docs
  are present. Only the first line of a multi-line doc needs to include a token with an
  emphasis (i.e., `##!` or `##%`).

+ Sections can be defined using `##@`. All lines in a multi-line section should start
  with `##@` (empty lines are ignored). There should be at least one anchor (possibly a
  hidden deprecated one) after a section for it to be displayed.

* [Double-colon](https://www.gnu.org/software/make/manual/html_node/Double_002dColon.html)
  targets are displayed using the format `target-name~index` and for each index
  there can be a dedicated documentation.

* [Grouped](https://www.gnu.org/software/make/manual/html_node/Multiple-Targets.html)
  targets are displayed with a `&` at the end, e.g., `t1 t2 t3&`. Double-colon grouped
  targets are handled as well.

+ See `test/Makefile*` for examples.

**Note**: in general, using inline comments with variables is not a good idea because
["trailing space characters are not stripped from variable
value"](https://www.gnu.org/software/make/manual/html_node/Simple-Assignment.html).

## Options

The following options can be passed to `awk` using `-v option=value` (possible values
are given in `{...}`, `(.)` shows the default)

+ `OUTPUT_FORMAT`: `{(ANSI), HTML, LATEX}`
+ `EXPORT_THEME`: see [Export to HTML and Latex](#export-to-html-and-latex)
+ `SUB`, `DSUB`: see [Substitutions](#substitutions)
+ `TARGETS_REGEX`: regex to use for matching targets
+ `VARIABLES_REGEX`: regex to use for matching variables
* `VARS`: `{0, (1)}` show documented variables
* `PADDING`: `{(" "), ".", ...}` a single padding character between anchors and docs
* `DEPRECATED`: `{0, (1)}` show deprecated anchors
* `OFFSET`: `{0, 1, (2), ...}` number of spaces to offset docs from anchors
+ `RECIPEPREFIX`: should have the same value as the `.RECIPEPREFIX` from your `Makefile`
+ Colors:
  + `COLOR_DEFAULT`: (`34`: blue) for anchors whose docs start with `##`
  + `COLOR_ATTENTION`: (`31`: red) for anchors whose docs start with `##!`
  + `COLOR_DEPRECATED`: (`33`: yellow) for anchors whose docs start with `##%`
  + `COLOR_WARNING`: (`35`: magenta) currently not used
  + `COLOR_SECTION`: (`32`: green) for sections
  + `COLOR_BACKTICKS`: (`0`, disabled) used for text in backticks in docs

  Colors are specified using the parameter in [ANSI escape
  codes](https://en.wikipedia.org/wiki/ANSI_escape_code#Select_Graphic_Rendition_parameters),
  e.g., the parameter for blue is the 34 in `\033[34m`. The supported parameters are: 0,
  1, 3, 4, 9, 30-37, 40-47, 90-97, 100-107.

Running `awk -f makefile-doc.awk` outputs help with values of options.

## Substitutions

Sometimes it is necessary to document a target specified in terms of a variable or an
expression. In such cases it might be useful to replace the actual target name with a
label and (space separated) list of values. This can be achieved by setting `-v
SUB` equal to `NAME[:LABEL]:[VALUES][;...]`. For example, executing `make` with
```Makefile
NOTES := my-budget trip-info misc
OPEN_NOTES := $(addprefix open-,$(NOTES))

help: VFLAG := -v SUB='$$(OPEN_NOTES):open-:$(NOTES)'
help: ## Show this help
	@awk $(VFLAG) -f makefile-doc.awk $(MAKEFILE_LIST)

## Notes:
$(OPEN_NOTES):
```

produces

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

The same mechanism can be used for documenting variables. In addition to a name, label
and values, a substitution may contain optional parameters:
`[<p1:v1,...>]NAME[:LABEL]:[VALUES]` that can be used to control the way values are
shown. The supported parameters are:

+ `L:0/L:1` values are displayed starting from the current/next line
+ `M:0/M:1` single/multi-line display
+ `N`       max number of values to display (-1, the default, means no limit)
+ `S`       value-separator
+ `P`       prefix (added to each value)
+ `I`       initial string, e.g., `{`
+ `T`       termination string, e.g., `}`

See the `Makefile` of this project and the test recipes in
`test/recipes/test-substitution-*` for examples.

The option `DSUB` performs substitutions in the original descriptions. The expected
format is `NAME:VALUES`. For example, using `-v DSUB='$$(DEPS):$(DEPS)'`, the target

```Makefile
DEPS := x y
## Prerequisites: $(DEPS)
t: $(DEPS)
````
would be documented as:
````
t    Prerequisites: x y
````

## Export to HTML and Latex

We use
[Solarized](https://github.com/altercation/solarized?tab=readme-ov-file#the-values) dark
as the default theme for exporting ANSI colors to HTML/Latex. This can easily be
customised. The following is an example of how to use the
[Dracula](https://github.com/dracula/dracula-theme?tab=readme-ov-file#color-palette)
theme instead:

```Makefile
BG_FG := BG:000000,FG:AAAAAA
DRACULA := 30:21222c,31:ff5555,32:50fa7b,33:f1fa8c,34:bd93f9,35:ff79c6,36:8be9fd,37:f8f8f2,90:6272a4,91:ff6e6e,92:69ff94,93:ffffa5,94:d6acff,95:ff92df,96:a4ffff,97:ffffff,$(BG_FG)

help: ## show this help
	@awk \
		-v EXPORT_THEME=$(DRACULA) \
		-v OUTPUT_FORMAT=html \
		-f makefile-doc.awk $(MAKEFILE_LIST)
```
The format expected by the option `EXPORT_THEME` is `ANSI_COLOR_PARAMETER:HEX_COLOR[,...]` (where the `HEX_COLOR` is defined
without `#`). Foreground/background can be set using the tokens `FG/BG`. Unspecified colors remain at their default values.

## Dependencies

+ `awk`, tested with (on fedora, ubuntu, macos):
  + [gawk](https://www.gnu.org/software/gawk) `5.2.2`, `5.1.0` (with `--posix` flag)
  + [nawk](https://github.com/onetrueawk/awk) tag `20240728`
  + [mawk](https://invisible-island.net/mawk) `1.3.4 20240905` (with  `-W posix` flag)
  + [busybox awk](https://www.busybox.net/) `1.35.0`
  + [wak](https://github.com/raygard/wak) `v24.10`
  + [goawk](https://github.com/benhoyt/goawk) `v1.29.1`
+ `GNU Make`
  + version 3.81 works fine for documentation generation
  + I run the tests with version 4.3

## Running the tests

Execute `make test utest` (this uses the system's default `awk`). To test with a custom
`awk`, use:

+ `make test utest AWK=mawk`
+ `make test utest AWK=nawk`
+ `make test utest AWK=bawk` (binaries are not available for macos)
+ `make test utest AWK=wak`
+ `make test utest AWK=goawk`

You need a standard build environment. To compile `nawk` ensure that `bison` is
installed (`dnf install bison`). For `goawk` you need `golang` (`dnf install golang`).
