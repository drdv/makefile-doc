# Awk script for Makefile docs

This branch reproduces some bugs I've found with awk executables.

+ help: `make -f Makefile.bugs MAKEFILE_LIST=Makefile.bugs`
+ bug `mawk-20241225`: `yes | make -f Makefile.bugs mawk-20241225`
+ bug `mawk-20250102`: `yes | make -f Makefile.bugs mawk-20250102`
