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
echo "results:"
echo "============================================================"

declare -A awk_executables
awk_executables["gawk"]="$gawk_version"
awk_executables["nawk"]="$nawk_version"
awk_executables["wak"]="$wak_version"
awk_executables["bawk"]="$bawk_version"
awk_executables["mawk"]="$mawk_version"

printf "[%7s %15s] %s\n" "mac-awk" "$macosawk_version" "$string"
for k in "${!awk_executables[@]}"; do
    awk="$k"
    ver="${awk_executables[$k]}"
    printf "[%7s %15s] %s\n" "$awk" "$ver" $(echo $string | ./test/bin/"$awk" "/$regex/ { print \$0 }")
done
echo "============================================================"
