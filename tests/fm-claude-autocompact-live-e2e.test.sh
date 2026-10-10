#!/usr/bin/env bash
# tests/fm-claude-autocompact-live-e2e.test.sh - default-on drift guard proving
# the INSTALLED claude still accepts the --autocompact window bin/fm-spawn.sh
# passes every interactive Claude worker launch, over exactly the range
# config/crew-autocompact admits (docs/configuration.md "Claude auto-compact
# window").
#
# Why this file exists: --autocompact is a vendor-emitted launch flag. A release
# that drops it, or narrows the range it accepts, would make every Claude worker
# launch die at argument parsing. The guard asks the real CLI to validate the
# flag's argument without starting a session: claude validates option arguments
# before honouring --version, so `claude --autocompact <n> --version` exits 0 for
# an accepted value and refuses an out-of-range one, submitting no prompt and
# spending no tokens. An unknown option does NOT refuse beside --version, so the
# out-of-range refusals are what prove the flag is recognized at all; each one
# must name --autocompact. An absent claude is reported explicitly, and a pass
# that checked nothing is refused when the guard was requested.
#
# The portable counterpart, tests/fm-spawn-dispatch-profile.test.sh, pins the
# launch command and config validation against a fake pane; this guard pins the
# CLI's flag surface.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate default-on FM_CLAUDE_AUTOCOMPACT_LIVE

REQUESTED=0
case "${FM_CLAUDE_AUTOCOMPACT_LIVE:-}${FM_LIVE:-}" in *1*) REQUESTED=1 ;; esac

if ! command -v claude >/dev/null 2>&1; then
  if [ "$REQUESTED" -eq 1 ]; then
    fail "the claude auto-compact guard was requested but claude is not installed"
  fi
  printf 'skip: live: claude is not installed, so its --autocompact surface was not checked\n'
  exit 0
fi

GUARD_TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-claude-autocompact.XXXXXX") || fail "could not create a scratch directory"
trap 'rm -rf "$GUARD_TMP"' EXIT
version=$(cd "$GUARD_TMP" && claude --version 2>/dev/null | head -1 || true)

# The tracked default and both ends of the range fm-spawn admits must parse.
for value in 200000 100000 1000000; do
  out=$(cd "$GUARD_TMP" && claude --autocompact "$value" --version 2>&1) \
    || fail "claude $version refuses --autocompact $value, which config/crew-autocompact admits: $out"
done
pass "claude $version accepts --autocompact 200000 and the range ends 100000 and 1000000"

# Just outside that range must refuse, naming the flag.
for value in 99999 1000001; do
  if out=$(cd "$GUARD_TMP" && claude --autocompact "$value" --version 2>&1); then
    fail "claude $version accepted --autocompact $value; either the flag is no longer recognized or its range widened beyond what config/crew-autocompact validates"
  fi
  assert_contains "$out" "--autocompact" "claude $version refused --autocompact $value without naming the flag"
done
pass "claude $version refuses --autocompact 99999 and 1000001, so the flag is recognized with fm-spawn's range"
printf '# claude auto-compact live guard checked: claude\n'
