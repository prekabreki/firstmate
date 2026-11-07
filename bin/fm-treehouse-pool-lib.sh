#!/usr/bin/env bash
# fm-treehouse-pool-lib.sh - detect a Treehouse pool that belongs to another
# clone of the same repository. No source-time side effects.
#
# Treehouse keys a pool on the repository rather than on the clone path, so a
# second clone of one repository (a project clone under projects/ beside the
# captain's own clone elsewhere, say) can resolve to a pool whose slots are
# worktrees of the FIRST clone. A worktree leased from that pool is the other
# clone's copy: work done there lands in the other clone's object store and its
# isolation, trust, and landed-work checks all answer for the wrong project.
#
# Ownership is a resolved-path comparison of Git common directories, so a
# symlinked home, project, or pool prefix never reads as a mismatch.
#
# These helpers only read. They never lease, return, prune, or destroy a slot and
# never touch the owning clone; clearing the pool is the captain's call, made from
# the owning clone with the remedy fm_treehouse_foreign_pool_message names.
#
# Consumers: bin/fm-spawn.sh (refuses before any endpoint, record, or lease, and
# again on a freshly leased slot) and bin/fm-treehouse-pool-owner.sh (the
# project-add intake warning).

# Set by fm_treehouse_slot_foreign_owner and fm_treehouse_pool_foreign_owner when
# they find a foreign slot; empty otherwise.
FM_TREEHOUSE_FOREIGN_POOL=
FM_TREEHOUSE_FOREIGN_SLOT=
FM_TREEHOUSE_FOREIGN_OWNER=
# Set by fm_treehouse_pool_foreign_owner when the pool could not be read.
FM_TREEHOUSE_POOL_ERROR=

# The physical path of a work tree's Git common directory.
fm_treehouse_common_dir_real() {  # <work-tree>
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ -n "$common" ] || return 1
  CDPATH='' cd -- "$common" 2>/dev/null && pwd -P
}

# True when <slot> sits in a Treehouse pool layout (<pool>/<n>/<repo>, with
# <pool>/treehouse-state.json a regular file) and its common git dir is not the
# project's. Sets FM_TREEHOUSE_FOREIGN_POOL, FM_TREEHOUSE_FOREIGN_SLOT, and
# FM_TREEHOUSE_FOREIGN_OWNER (the owning clone: the work tree holding a `.git`
# common dir, or the common dir itself for a bare repository). Anything that
# cannot be resolved is not reported as foreign.
fm_treehouse_slot_foreign_owner() {  # <project-dir> <slot>
  local project=$1 slot=$2 slot_real pool project_common slot_common
  FM_TREEHOUSE_FOREIGN_POOL=
  FM_TREEHOUSE_FOREIGN_SLOT=
  FM_TREEHOUSE_FOREIGN_OWNER=
  slot_real=$(CDPATH='' cd -- "$slot" 2>/dev/null && pwd -P) || return 1
  pool=${slot_real%/*}
  pool=${pool%/*}
  [ -n "$pool" ] && [ -f "$pool/treehouse-state.json" ] && [ ! -L "$pool/treehouse-state.json" ] || return 1
  project_common=$(fm_treehouse_common_dir_real "$project") || return 1
  slot_common=$(fm_treehouse_common_dir_real "$slot_real") || return 1
  [ "$project_common" != "$slot_common" ] || return 1
  FM_TREEHOUSE_FOREIGN_POOL=$pool
  FM_TREEHOUSE_FOREIGN_SLOT=$slot_real
  case "$slot_common" in
    */.git) FM_TREEHOUSE_FOREIGN_OWNER=${slot_common%/.git} ;;
    *) FM_TREEHOUSE_FOREIGN_OWNER=$slot_common ;;
  esac
  return 0
}

# Read the project's pool with `treehouse status --json`, which takes no lease
# (it does create the empty pool state a first `treehouse get` would), and check
# every listed slot with fm_treehouse_slot_foreign_owner.
# Returns 0 when a slot belongs to another clone (the FM_TREEHOUSE_FOREIGN_*
# values describe the first one found), 1 when no listed slot does, including an
# empty pool, and 2 when the pool cannot be read (FM_TREEHOUSE_POOL_ERROR says
# why). Slot paths are read from the JSON's "path" strings; a path whose JSON
# form needs escaping cannot be resolved and is skipped like any unresolvable one.
# shellcheck disable=SC2034 # FM_TREEHOUSE_POOL_ERROR is read by the sourcing caller.
fm_treehouse_pool_foreign_owner() {  # <project-dir>
  local project=$1 listing paths path
  FM_TREEHOUSE_FOREIGN_POOL=
  FM_TREEHOUSE_FOREIGN_SLOT=
  FM_TREEHOUSE_FOREIGN_OWNER=
  FM_TREEHOUSE_POOL_ERROR=
  if [ ! -d "$project" ]; then
    FM_TREEHOUSE_POOL_ERROR="'$project' is not a directory"
    return 2
  fi
  if ! command -v treehouse >/dev/null 2>&1; then
    FM_TREEHOUSE_POOL_ERROR="treehouse is not on PATH"
    return 2
  fi
  if ! listing=$( (CDPATH='' cd -- "$project" && treehouse status --json) 2>/dev/null); then
    FM_TREEHOUSE_POOL_ERROR="'treehouse status --json' failed in '$project'"
    return 2
  fi
  case "${listing#"${listing%%[![:space:]]*}"}" in
    '['*) ;;
    *)
      FM_TREEHOUSE_POOL_ERROR="'treehouse status --json' in '$project' did not print a JSON array"
      return 2
      ;;
  esac
  paths=$(printf '%s\n' "$listing" | grep -oE '"path"[[:space:]]*:[[:space:]]*"[^"\\]*"' |
    sed -E 's/^"path"[[:space:]]*:[[:space:]]*"//; s/"$//') || paths=
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    fm_treehouse_slot_foreign_owner "$project" "$path" && return 0
  done <<< "$paths"
  return 1
}

# The one statement of the mismatch and its remedy, for refusals and warnings.
# Call after a foreign-owner check returned 0.
fm_treehouse_foreign_pool_message() {  # <project-dir>
  local project=$1
  printf "Treehouse pool '%s' belongs to another clone of this repository: its slot '%s' is a worktree of '%s', not of '%s', so a worktree leased from it would be that other clone's copy. Treehouse keys a pool on the repository, not the clone, so only the captain clears it, from the owning clone: preview with (cd '%s' && treehouse destroy '%s' --all), then rerun that with --yes to remove its disposable slots; the next spawn then builds the pool from '%s'. Firstmate never destroys the pool or touches the other clone" \
    "$FM_TREEHOUSE_FOREIGN_POOL" "$FM_TREEHOUSE_FOREIGN_SLOT" "$FM_TREEHOUSE_FOREIGN_OWNER" "$project" \
    "$FM_TREEHOUSE_FOREIGN_OWNER" "$FM_TREEHOUSE_FOREIGN_POOL" "$project"
}
