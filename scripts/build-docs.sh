#!/bin/bash
# Build all documentation

set -e

echo "=== Generating Nim API docs ==="
nim doc --project --index:on --outdir:docs/api src/nim_typestates.nim

echo "=== Building MkDocs site ==="
source .venv/bin/activate
mkdocs build

echo "=== Done ==="
echo "API docs: docs/api/nim_typestates.html"
echo "Site: site/index.html"
