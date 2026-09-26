#!/usr/bin/env bash
# Bulk-delete old GitHub Actions runs.
#
#   ./scripts/gh-purge-runs.sh                  # delete every completed run
#   ./scripts/gh-purge-runs.sh --keep 5         # also keep the 5 newest completed
#   ./scripts/gh-purge-runs.sh --dry-run        # list what would be deleted
#
# Only `completed` runs are touched — an `in_progress` run is the live runner,
# and deleting it kills the server.
#
# gh run delete <id> is not promptable: with an explicit run-id it deletes
# directly, so every deletion below is a real, immediate one. Use --dry-run first.
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
KEEP=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep)    KEEP="${2:?--keep needs a number}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "repo=$REPO keep_newest_completed=$KEEP dry_run=$DRY_RUN"

# Newest first (run ids increase monotonically), then drop the first $KEEP.
ids=$(gh run list --repo "$REPO" --status completed --limit 500 \
        --json databaseId --jq 'sort_by(-.databaseId) | .[].databaseId')

n=0
for id in $ids; do
  if [ "$n" -lt "$KEEP" ]; then
    n=$((n + 1))
    continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would delete $id"
  else
    gh run delete "$id" --repo "$REPO"
    echo "deleted $id"
  fi
done

remaining=$(gh run list --repo "$REPO" --limit 100 --json databaseId --jq 'length')
echo "remaining runs: $remaining"
