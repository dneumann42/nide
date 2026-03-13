#!/bin/bash
# Test nimsuggest goto definition

FILE="$1"
LINE="${2:-1}"
COL="${3:-0}"

echo "Testing: $FILE:$LINE:$COL"
echo "---"

printf "def %s:%s:%s\n" "$FILE" "$LINE" "$COL" | nimsuggest --stdin --refresh "$FILE" | grep -v "^usage" | grep -v "^type" | grep -v "^$" | head -1
