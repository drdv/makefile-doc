# Awk script for Makefile docs

I extended a simple `awk` one-liner I have been using for years (I think it was based on
[this gist](https://gist.github.com/prwhite/8168133)). Every step of the way I asked
myself whether I should switch to writing it in python but I never did ... in the end I
have a somewhat working version in `awk`.

## How to use

Define the first target of your `Makefile` to be:

``` make
help: ## show help
	@awk -f makefile-doc.awk $(MAKEFILE_LIST)
```

or if it is not the first target, set `.DEFAULT_GOAL := help`. Add the location of the
`makefile-doc.awk` script to the `AWKPATH` env variable, or explicitly use `@awk -f
/path/to/makefile-doc.awk $(MAKEFILE_LIST)` in the `help` target.

## Docs syntax

``` make
## top doc line 1
## line 2
t1:

t2: ## inline doc (ignored if there are top docs as well)
```

+ Docs of targets start with tokens `##` or `##!` or `##%` (they can be both above a
  target or inline).

+ To emphasize targets that are "special" in some way, start their docs with `##!` (this
  changes the target's color).

+ To indicate that a target is deprecated, start its docs with `##%` (this changes the
  target's color).

+ Multi-line docs can be added above a target, inline docs are ignored when top docs are
  present. Only the first line in a multi-line doc should include a token with an
  emphasis, the remaining lines should simply use `##`.

* A detail: there could be spaces both before and/or after tokens in docs above a
  target, however, it is mandatory to have at least one space before and after a token
  for inline docs.

	``` make
    ##! this is recommended
       ## but this is possible
    ##so is this
    t1:

    t2: ##! at least one space before the token and one space after is required
    ```

+ Sections can be defined using `##@` (which should appear at the beginning of the
  line). All lines in a multi-line section should start with `##@` (empty lines are
  ignored). There should be at least one target (possibly hidden deprecated one) after a
  section for it to be displayed.

+ See `test/Makefile` for examples.

## Parameters

The following parameters are recognised and can be passed to `awk` using `-v var=value`

+ `HEADER`: (default: `1`) If `1`, display header and footer.
+ `DEPRECATED`: (default: `1`) If `0`, hide deprecated targets, show them otherwise.
+ `PADDING`: (default: `" "`) Padding symbol between target name and its docs.
+ `CONNECTED`: (default: `1`) If `1`, docs above a target cannot include an empty line.
  If `0`, docs split by empty lines are joined.
+ `COLOR_DEFAULT`: (default: blue) Color for targets whose docs start with `##`.
+ `COLOR_ATTENTION`: (default: red) Color for targets whose docs start with `##!`.
+ `COLOR_DEPRECATED`: (default: yellow) Color for targets whose docs start with `##%`.
+ `COLOR_WARNING`: (default: magenta) Color for warnings.
+ `COLOR_SECTION`: (default: green) Color for sections.

Colors are specified using the parameter in ANSI escape codes, e.g., the parameter for
blue is the 34 in `\033[34m`.

## Dependencies

+ `awk`, I have tested with:
  + [gawk](https://www.gnu.org/software/gawk) `5.2.2`, `5.1.0`
  + [nawk](https://github.com/onetrueawk/awk) tag `20240728`
  + [mawk](https://invisible-island.net/mawk) `1.3.4 20240905`
+ `make`

## Running the tests

Execute `make test` (I use ad hoc tests as I don't want other dependencies).

Note that `Makefile` and `Makefile.inc` in `./test` are not meant to be used manually,
they are a part of the tests.

## Code

[Github](https://github.com/drdv/makefile-doc).
