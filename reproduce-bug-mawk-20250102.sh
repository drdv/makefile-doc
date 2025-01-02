#!/usr/bin/env bash

string1='unexport override private      export X = 1'
string2='unexport override private       export X = 1'
regex='^ *( *(override|unexport|export|private) *){0,4} *[^.#][a-zA-Z0-9_-]* *(=|:=|::=|:::=)'

mawk="./test/bin/mawk"
mawk_version=$($mawk --version | $mawk '/^mawk/ {print $2 " " $3}') # 1.3.4 20240905

printf " regex: %s\n" "$regex"
printf "script: echo \"...\" | mawk /regex/{ print \$0 }\n\n"

printf "============================================================\n"
printf "string1: %s\n" "\"$string1\""
printf "============================================================\n\n"
printf "[%7s, %15s] %s\n\n" "$mawk" "$mawk_version" "$(echo "$string1" | $mawk "/$regex/{ print \$0 }")"


printf "============================================================\n"
printf "string2: %s\n" "\"$string2\""
printf "============================================================\n\n"
printf "[%7s, %15s] %s\n\n" "$mawk" "$mawk_version" "$(echo "$string2" | $mawk "/$regex/{ print \$0 }")"
