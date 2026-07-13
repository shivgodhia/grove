#!/usr/bin/env bash
# Extracts the guided-setup install prompt from README.md into install-prompt.txt
# so the landing page and README share a single source of truth.
# The prompt in README.md is the first fenced block delimited by four backticks (````).
set -euo pipefail
cd "$(dirname "$0")/.."
awk '
  /^````/ { fence++; if (fence==1) {inblock=1; next}; if (fence==2) exit }
  inblock { print }
' README.md > landing-page/install-prompt.txt
lines=$(wc -l < landing-page/install-prompt.txt | tr -d ' ')
if [ "$lines" -lt 20 ]; then
  echo "ERROR: extracted prompt is only $lines lines — extraction likely failed" >&2
  exit 1
fi
echo "Wrote landing-page/install-prompt.txt ($lines lines)"
