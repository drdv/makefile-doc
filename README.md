# Awk script for Makefile docs

The `makefile-doc.awk` is a POSIX-compliant extension of a simple `awk` one-liner I have
been using for years (I think it was based on [this
gist](https://gist.github.com/prwhite/8168133)). I simply needed a bit more
functionality and this turned out to be a nice small project with Awk.

## How to use

### Make available on the fly

Define the first target of your `Makefile` (or if it is not the first target, set
`.DEFAULT_GOAL := help`) as:

``` make
help: ## show this help
	@test -f .external/makefile-doc.awk || \
	wget --quiet -P .external github.com/drdv/makefile-doc/releases/latest/download/makefile-doc.awk
	@awk -f .external/makefile-doc.awk $(MAKEFILE_LIST)
```

This will download the awk script on the fly (if it doesn't exist in `.external`). As an
alternative of `wget` you could use `curl`:

```
curl -sLO --create-dirs --output-dir .external github.com/drdv/makefile-doc/releases/latest/download/makefile-doc.awk
```

### Manual installation

Define the first target of your `Makefile` as:

``` make
help: ## show help
	@awk -f makefile-doc.awk $(MAKEFILE_LIST)
```

Manually download and place the `makefile-doc.awk` script on your `AWKPATH`.

## Docs syntax

``` make
## doc of a CLA variable the user might want to know about
MY_VARIABLE = 42

## top doc line 1
## line 2
target1:

target2: ## inline doc (ignored if there are top docs as well)
```

I refer to targets / variables as anchors (for docs/sections).

+ Docs of anchors start with tokens `##` or `##!` or `##%` (they can be both above an
  anchor or inline).

+ To emphasize anchors that are "special" in some way, start their docs with `##!` (this
  changes their color).

+ To indicate that an anchor is deprecated, start its docs with `##%` (this changes its
  color and allows to filter it out, see the `DEPRECATED` flag below).

+ Multi-line docs can be added above an anchor, inline docs are ignored when top docs
  are present. Only the first line in a multi-line doc need to include a token with an
  emphasis (i.e., `##!` or `##%`).

+ Sections can be defined using `##@`. All lines in a multi-line section should start
  with `##@` (empty lines are ignored). There should be at least one anchor (possibly a
  hidden deprecated one) after a section for it to be displayed.

* [Double-colon](https://www.gnu.org/software/make/manual/html_node/Double_002dColon.html)
  target are displayed using the format `target-name:target-index` and for each index
  there can be a dedicated documentation (if necessary).

+ See `test/Makefile*` for examples.

**Note**: in general, using inline comments with variables is not a good idea because
["trailing space characters are not stripped from variable
value"](https://www.gnu.org/software/make/manual/html_node/Simple-Assignment.html).

## Parameters

The following parameters can be passed to `awk` using `-v var=value`

+ `VARS`: (default: `1`) Show documented variables, set to 0 to disable.
+ `PADDING`: (default: `" "`) Padding symbol between anchor name and its docs.
+ `DEPRECATED`: (default: `1`) If `0`, hide deprecated anchors, show them otherwise.
+ `OFFSET`: Number of spaces to offset descriptions from anchors (2 by default).
+ `CONNECTED`: If `1` (the default), docs above an anchor cannot include an empty line.
  If `0`, docs split by empty lines are joined.
+ `COLOR_DEFAULT`: (default: blue) Color for anchors whose docs start with `##`.
+ `COLOR_ATTENTION`: (default: red) Color for anchors whose docs start with `##!`.
+ `COLOR_DEPRECATED`: (default: yellow) Color for anchors whose docs start with `##%`.
+ `COLOR_WARNING`: (default: magenta) Color for warnings.
+ `COLOR_SECTION`: (default: green) Color for sections.
+ `COLOR_BACKTICKS`: (default: 0, i.e., disabled) used for text in backticks in
  descriptions, set e.g., to 1 to display it in bold.

Colors are specified using the parameter in ANSI escape codes, e.g., the parameter for
blue is the 34 in `\033[34m`.

Cloning this repository (at tag `v0.1`) and running `make` outputs:
![makefile-doc.awk](img/example.png)

## Dependencies

+ `awk`, tested with:
  + [gawk](https://www.gnu.org/software/gawk) `5.2.2`, `5.1.0` (with `--posix` flag)
  + [nawk](https://github.com/onetrueawk/awk) tag `20240728`
  + [mawk](https://invisible-island.net/mawk) `1.3.4 20240905` (with  `-W posix` flag)
  + [busybox awk](https://www.busybox.net/) `1.35.0`
  + [wak](https://github.com/raygard/wak) `v24.10`
+ `GNU Make`

## Running the tests

Execute `make test` (this uses the system's default `awk`). To test with a custom
`awk`, use:

+ `make test AWK=mawk`
+ `make test AWK=nawk`
+ ...

Note that the makefiles in `./test` are not meant to be used manually, they are part of
the tests.
