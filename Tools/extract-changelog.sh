#!/bin/zsh

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <changelog-path> <version>" >&2
    exit 1
fi

changelog_path="$1"
version="$2"

if [[ ! -f "$changelog_path" ]]; then
    echo "Missing changelog: $changelog_path" >&2
    exit 1
fi

awk -v version="$version" '
/^## \[/ {
    heading = $0
    sub(/^## \[/, "", heading)
    sub(/\].*$/, "", heading)

    if (in_section) {
        exit
    }

    if (heading == version) {
        in_section = 1
    }
}

in_section {
    print
}
' "$changelog_path"
