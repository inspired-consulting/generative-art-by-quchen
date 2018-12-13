#!/usr/bin/env bash

# Cairo has nondeterministic SVG output, because one of the generated IDs are
# regenerated arbitrarily between runs. This shows up in Git as a change every
# time the testsuite is run, so we use this script to normalize the generated
# files.

set -euo pipefail
echo "Normalizing SVG so output is deterministic and doesn’t confuse Git"
cd "$(git rev-parse --show-toplevel)"
for image in $(find . -name "*.svg" | sort); do
    ID="$(basename -s .svg "$image")"
    perl -pi -e "s/^<g id=\"surface(\\d+)\">\$/<g id=\"$ID\">/" "$image"
    i=0
    for surface in $(cat "$image" | grep -Eo 'surface([0-9]+)' | sort -u); do
        perl -pi -e "s/$surface/surface_$i/g" "$image"
        i=$((i+1))
    done
done
