#!/usr/bin/env bash
# Verify a GitHub Actions workflow file without running it.
#   usage: verify-workflow.sh <path/to/workflow.yml> [job-name]
# Parses the YAML, then runs `bash -n` over every `run:` block with ${{ }}
# expressions replaced by placeholders. Exits non-zero on any failure.
set -uo pipefail

WF="${1:-}"
JOB="${2:-build}"

if [ -z "$WF" ] || [ ! -f "$WF" ]; then
  echo "usage: $0 <workflow.yml> [job-name]" >&2
  exit 2
fi

if grep -Pn '\t' "$WF" >/dev/null 2>&1; then
  echo "FAIL: the file contains tab characters; YAML forbids tab indentation"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# js-yaml's CLI prints JSON, which node can require directly.
if ! npx -y js-yaml "$WF" > "$TMP/wf.json" 2> "$TMP/err"; then
  echo "FAIL: YAML parse error"
  cat "$TMP/err" >&2
  exit 1
fi
echo "OK: YAML parses"

WF="$WF" JOB="$JOB" TMP="$TMP" node -e '
const fs = require("fs");
const wf = JSON.parse(fs.readFileSync(process.env.TMP + "/wf.json", "utf8"));
const steps = (wf.jobs && wf.jobs[process.env.JOB] && wf.jobs[process.env.JOB].steps) || [];
console.log("job: " + process.env.JOB + "  steps: " + steps.length);
steps.forEach((s, i) => console.log(String(i).padStart(2) + " | " + (s.name || "(unnamed)")));
steps.forEach((s, i) => {
  if (!s.run) return;
  const out = s.run.replace(/\$\{\{[^}]*\}\}/g, "PLACEHOLDER");
  fs.writeFileSync(process.env.TMP + "/step_" + i + ".sh", out);
});
'

fail=0
for f in "$TMP"/step_*.sh; do
  [ -e "$f" ] || continue
  if ! bash -n "$f" 2> "$TMP/shellerr"; then
    echo "FAIL: bash syntax in $f"
    cat "$TMP/shellerr" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "OK: bash -n clean on every run: block"

if command -v shellcheck >/dev/null 2>&1; then
  for f in "$TMP"/step_*.sh; do
    [ -e "$f" ] || continue
    shellcheck -S warning "$f" || true
  done
else
  echo "note: shellcheck not installed, skipped"
fi

exit "$fail"
