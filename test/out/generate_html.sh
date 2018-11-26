#!/usr/bin/env bash

set -euo pipefail

echo "Generating visual testsuite file (HTML for the browser)"
cd "$(git rev-parse --show-toplevel)/test/out"

FILE=README.html

cat << EOF > "$FILE"
<!DOCTYPE html>
<!-- This file was auto-generated by generate_readme.sh -->
<html lang="en">
    <head>
        <meta charset="utf-8">
        <title>Generative Art – Visual Testsuite</title>
    </head>
    <body>
        <h1>Generative Art – Visual Testsuite</h1>
        <p>This file contains the SVG files generated by the visual testsuite to glance over quickly.</p>
EOF

for image in $(find . -name "*.svg" | sort); do
    echo ""
    echo "<div><img src=\"$image\"/></div>"
done >> "$FILE"


cat << EOF >> "$FILE"
</body>
</html>
EOF
