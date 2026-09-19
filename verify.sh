#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"
[[ -s CHECKSUMS.txt ]] || { echo 'ERROR: CHECKSUMS.txt missing'; exit 1; }
sha256sum -c CHECKSUMS.txt
