# This branch reproduces some bugs I've found

+ help: `make -f Makefile.bugs MAKEFILE_LIST=Makefile.bugs`
+ bug `mawk-20241225`: `yes | make -f Makefile.bugs mawk-20241225`
+ bug `mawk-20250102`: `yes | make -f Makefile.bugs mawk-20250102`
+ bug `make-20250102`: `make -f Makefile.bugs make-20250102`
  + [results-make-20250102.zip](https://github.com/drdv/makefile-doc/actions/runs/12587496128/artifacts/2380111039)
