#!/usr/bin/env bash

string1='unexport override private      export X = 1'
string2='unexport override private       export X = 1'
regex='^ *( *(override|unexport|export|private) *){0,4} *[^.#][a-zA-Z0-9_-]* *(=|:=|::=|:::=)'

gawk_version=$(./test/bin/gawk --version | awk 'NR==1 {print substr($3,1,length($3)-1)}') # 5.2.2
nawk_version=$(./test/bin/nawk --version | awk '{print $3}')                              # 20240728
wak_version=$(./test/bin/wak --version | awk '{print $2, substr($3,1,8)}')                # 24.10 20241008
bawk_version="1.35.0-x86_64" # no --version flag!                                         # 1.35.0-x86_64
mawk_version=$(./test/bin/mawk --version | awk '/^mawk/ {print $2 " " $3}')               # 1.3.4 20240905

declare -A awk_executables
awk_executables["gawk"]="$gawk_version"
awk_executables["nawk"]="$nawk_version"
awk_executables["wak"]="$wak_version"
awk_executables["bawk"]="$bawk_version"
awk_executables["mawk"]="$mawk_version"

printf "============================================================\n"
printf "regex: %s\n" "$regex"
printf "script: echo \"...\" | mawk /regex/{ print \$0 }\n"
printf "============================================================\n"
printf "results:\n"
printf "============================================================\n"

printf "\nstring1: %s\n" "\"$string1\""
for k in "${!awk_executables[@]}"; do
    awk="$k"
    ver="${awk_executables[$k]}"
    printf "    [%4s, %14s] %s\n" "$awk" "$ver" "$(echo "$string1" | ./test/bin/"$awk" "/$regex/{ print \$0 }")"
done

printf "\nstring2: %s\n" "\"$string2\""
for k in "${!awk_executables[@]}"; do
    awk="$k"
    ver="${awk_executables[$k]}"
    printf "    [%4s, %14s] %s\n" "$awk" "$ver" "$(echo "$string2" | ./test/bin/"$awk" "/$regex/{ print \$0 }")"
done
printf "============================================================\n"
