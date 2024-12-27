#!/usr/bin/env bash

string='maybe-bug::'
regex='^ *\${0,1}[^.#][ a-zA-Z0-9_\/%.(){}-]+ *:{1,2}( |$)'

macosawk_version="20200816" # checked manually on macos 15.2                              # 20200816
gawk_version=$(./test/bin/gawk --version | awk 'NR==1 {print substr($3,1,length($3)-1)}') # 5.2.2
nawk_version=$(./test/bin/nawk --version | awk '{print $3}')                              # 20240728
wak_version=$(./test/bin/wak --version | awk '{print $2, substr($3,1,8)}')                # 24.10 20241008
bawk_version="1.35.0-x86_64" # no --version flag!                                         # 1.35.0-x86_64
mawk_version=$(./test/bin/mawk --version | awk '/^mawk/ {print $2 " " $3}')               # 1.3.4 20240905

echo "============================================================"
printf "string: %s\n" "$string"
printf " regex: %s\n" "$regex"
echo "============================================================"
echo "versions:"
echo "============================================================"
printf "[%7s] %s\n" mac-awk "$macosawk_version"
printf "[%7s] %s\n" gawk "$gawk_version"
printf "[%7s] %s\n" nawk "$nawk_version"
printf "[%7s] %s\n" wak "$wak_version"
printf "[%7s] %s\n" bawk "$bawk_version"
printf "[%7s] %s\n" mawk "$mawk_version"
echo "============================================================"
echo "results:"
echo "============================================================"
awk_executables="gawk nawk wak bawk mawk"
printf "[%7s] %s\n" mac-awk "maybe-bug::" # verified manually
for awk_current in $awk_executables; do
    printf "[%7s] %s\n" $awk_current $(echo $string | ./test/bin/$awk_current "/$regex/ { print \$0 }")
done
echo "============================================================"
