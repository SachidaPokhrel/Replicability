#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"

CANONICAL="$ROOT/CHECKSUMS.txt"
GENERATED="$ROOT/CHECKSUMS.generated.txt"

[[ -s "$CANONICAL" ]] || {
    echo "ERROR: Canonical CHECKSUMS.txt is missing."
    exit 1
}

# The raw public inputs are intentionally not committed to GitHub.  Therefore
# verification is meaningful only after setup_and_run.sh or run.sh has
# regenerated the input files and outputs.
missing=0
while read -r hash file; do
    [[ -n "${file:-}" ]] || continue
    if [[ ! -e "$file" ]]; then
        echo "MISSING: $file"
        missing=1
    fi
done < "$CANONICAL"

if [[ "$missing" -ne 0 ]]; then
    echo
    echo "ERROR: Required files are missing."
    echo "Run the analysis first:"
    echo "  bash setup_and_run.sh"
    exit 2
fi

echo "Checking regenerated files against canonical SHA-256 values..."
sha256sum -c "$CANONICAL"

echo
if [[ -s "$GENERATED" ]]; then
    echo "The current run also produced:"
    echo "  CHECKSUMS.generated.txt"
fi

echo "REPRODUCIBILITY CHECK PASSED"
