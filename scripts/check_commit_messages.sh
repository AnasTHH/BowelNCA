#!/usr/bin/env bash
# Check commit messages and identities in a revision range before they become
# public. Rejects private AI-assistant links and session trailers, secret-like
# strings, private identifiers from a local pattern file kept outside the
# repository, and author/committer e-mail addresses that are not no-reply
# addresses. Output names only the commit and the rule; the matched text is
# never printed.
#
# Usage: scripts/check_commit_messages.sh <rev-list arguments | --message-file FILE>
#   e.g. scripts/check_commit_messages.sh origin/main..HEAD
# Private patterns: as in scripts/check_repo_policy.sh.
set -euo pipefail

ai_link_re='claude\.ai/(code/)?(session|project|artifact|chat|share)|Claude''-Session:'
secret_re='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{32,}|hf_[A-Za-z0-9]{30,}|tskey-[A-Za-z0-9-]{10,})'
noreply_re='(@users\.noreply\.github\.com|^noreply@github\.com|^noreply@anthropic\.com)$'
private_patterns="${BOWELNCA_PRIVATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/bowelnca/private-patterns.txt}"
fail=0
report() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }

patterns=()
if [ -f "$private_patterns" ]; then
  while IFS= read -r pat || [ -n "$pat" ]; do
    case "$pat" in ''|'#'*) continue ;; esac
    patterns+=("$pat")
  done < "$private_patterns"
elif [ "${BOWELNCA_REQUIRE_PRIVATE_PATTERNS:-0}" = 1 ]; then
  report 'private pattern file required but not found (see SECURITY.md)' '(pattern file)'
fi

check_text() {  # $1 = label, stdin = text
  local label="$1" text i
  text="$(cat)"
  grep -qIE -- "$ai_link_re" <<<"$text" && report 'private AI-assistant link or session trailer' "$label"
  grep -qIE -- "$secret_re" <<<"$text" && report 'secret-like string' "$label"
  for i in "${!patterns[@]}"; do
    grep -qIE -- "${patterns[$i]}" <<<"$text" && report "private identifier (pattern #$((i + 1)))" "$label"
  done
  return 0
}

if [ "${1:-}" = "--message-file" ]; then
  [ -f "${2:-}" ] || { echo "usage: $0 --message-file FILE" >&2; exit 2; }
  check_text 'commit message' < "$2"
else
  [ "$#" -gt 0 ] || { echo "usage: $0 <rev-list arguments>" >&2; exit 2; }
  mapfile -t commits < <(git rev-list "$@")
  for c in "${commits[@]}"; do
    short="${c:0:12}"
    check_text "commit $short message" < <(git log -1 --format=%B "$c")   # not a pipe: report must run in this shell
    for who in ae ce; do
      email="$(git log -1 --format="%$who" "$c")"
      grep -qE "$noreply_re" <<<"$email" \
        || report "$( [ "$who" = ae ] && echo author || echo committer ) e-mail is not a no-reply address" "commit $short"
    done
  done
  [ "$fail" -ne 0 ] || printf 'PASS: %d commit(s) in range\n' "${#commits[@]}"
fi
exit "$fail"
