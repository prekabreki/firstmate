#!/usr/bin/env bash
# Warn at project-add intake when a clone's Treehouse pool already belongs to
# another clone of the same repository (bin/fm-treehouse-pool-lib.sh owns the
# detection and the remedy wording). Prints exactly one line to stdout:
#   ok: <why no listed slot is foreign>                       exit 0
#   warning: <mismatch, owning clone, and the captain's remedy> exit 1
#   unknown: <why the pool could not be read>                  exit 3
# A missing argument or a directory that is not a git work tree exits 2 with an
# error on stderr.
#
# READ ONLY. It runs `treehouse status --json` in the clone, which takes no
# lease, and never leases, returns, or destroys a slot or touches the owning
# clone. bin/fm-spawn.sh refuses the same mismatch on its own, so this is an
# early notice for the captain, not a gate.
# Usage: fm-treehouse-pool-owner.sh <clone-dir>
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bin/fm-treehouse-pool-lib.sh
. "$SCRIPT_DIR/fm-treehouse-pool-lib.sh"

case "${1:-}" in
  -h|--help)
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  '')
    echo "usage: fm-treehouse-pool-owner.sh <clone-dir>" >&2
    exit 2
    ;;
esac
DIR=$1
if [ ! -d "$DIR" ] || ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $DIR is not a git work tree" >&2
  exit 2
fi
DIR=$(CDPATH='' cd -- "$DIR" && pwd -P)

fm_treehouse_pool_foreign_owner "$DIR"
case $? in
  0)
    printf 'warning: %s\n' "$(fm_treehouse_foreign_pool_message "$DIR")"
    exit 1
    ;;
  1)
    printf "ok: no slot in the Treehouse pool for '%s' belongs to another clone\n" "$DIR"
    exit 0
    ;;
  *)
    printf 'unknown: could not read the Treehouse pool: %s\n' "$FM_TREEHOUSE_POOL_ERROR"
    exit 3
    ;;
esac
