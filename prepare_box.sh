#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"
[[ -s CHECKSUMS.txt ]] || { echo 'ERROR: run analysis first'; exit 1; }
[[ -s GITHUB_REPO.txt ]] || { echo 'ERROR: GITHUB_REPO.txt missing'; exit 1; }
! grep -q REPLACE_WITH GITHUB_REPO.txt || { echo 'ERROR: add your real public GitHub URL to GITHUB_REPO.txt'; exit 1; }
rm -rf box_submission
mkdir -p box_submission/outputs
cp GITHUB_REPO.txt CHECKSUMS.txt box_submission/
find outputs -maxdepth 1 -type f ! -name '.gitkeep' -exec cp {} box_submission/outputs/ \;
echo 'Created box_submission/'
