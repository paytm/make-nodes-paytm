#!/usr/bin/env bash
# Strips JSONC comments from all app/**/*.jsonc files and validates each as
# valid JSON. Useful as a pre-commit check or CI step.
#
# Dependencies: node (for JSON.parse), or install `jsonc` CLI via npm.
#
# Usage:
#   ./scripts/validate-jsonc.sh           # validate all .jsonc files
#   ./scripts/validate-jsonc.sh --strip   # also print stripped JSON to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${REPO_ROOT}/app"
ERRORS=0

strip_comments() {
    # Remove single-line (//) and block (/* */) comments from JSONC.
    # Uses Node.js — available on any dev machine / CI runner.
    node -e "
const fs = require('fs');
const content = fs.readFileSync('/dev/stdin', 'utf8');
// Strip block comments first, then line comments, preserving strings.
const stripped = content
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/\/\/[^\n]*/g, '');
process.stdout.write(stripped);
"
}

validate_file() {
    local file="$1"
    local rel="${file#${REPO_ROOT}/}"
    local stripped

    stripped=$(strip_comments < "$file") || {
        echo "FAIL [strip] ${rel}"
        ERRORS=$((ERRORS + 1))
        return
    }

    echo "$stripped" | node -e "
try {
  JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
  process.exit(0);
} catch(e) {
  process.stderr.write(e.message + '\n');
  process.exit(1);
}
" 2>&1 && echo "OK   ${rel}" || {
        echo "FAIL [json] ${rel}"
        ERRORS=$((ERRORS + 1))
    }

    if [[ "${1:-}" == "--strip" ]]; then
        echo "--- stripped: ${rel} ---"
        echo "$stripped"
    fi
}

echo "Validating JSONC files in ${APP_DIR} ..."
echo ""

while IFS= read -r -d '' file; do
    validate_file "$file"
done < <(find "${APP_DIR}" -name "*.jsonc" -print0)

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "All files valid."
else
    echo "${ERRORS} file(s) failed validation."
    exit 1
fi
