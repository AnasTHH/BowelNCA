#!/usr/bin/env bash
# Check commit messages and identities before they become public. Rejects
# private AI-assistant links and session trailers, secret-like strings,
# private identifiers from a local pattern file kept outside the repository,
# and author/committer e-mail addresses that are not no-reply addresses.
# Output names only the commit and the rule; the matched text is never
# printed.
#
# Usage:
#   scripts/check_commit_messages.sh <rev-list arguments>   e.g. origin/main..HEAD
#   scripts/check_commit_messages.sh --commits FILE         one commit ID per line
#   scripts/check_commit_messages.sh --message-file FILE    (commit-msg hook)
#
# Exit status: 0 pass, 1 findings, 3 internal error (Git or scanner failure).
# Private patterns: see scripts/lib/publication_checks.sh and SECURITY.md.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/publication_checks.sh
. "$script_dir/lib/publication_checks.sh"

noreply_re='(@users\.noreply\.github\.com|^noreply@github\.com|^noreply@anthropic\.com)$'
fail=0
report() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }
tmp="$(mktemp -d)" || pc_die 'mktemp failed'
trap 'rm -rf "$tmp"' EXIT

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
pc_load_patterns "$root" || fail=1

check_text() {  # $1 = label, $2 = file
  local hits h
  pc_grep -qaE -- "$PC_AI_LINK_RE" "$2" && report 'private AI-assistant link or session trailer' "$1"
  pc_grep -qaE -- "$PC_SECRET_RE" "$2" && report 'secret-like string' "$1"
  hits="$(pc_private_hits "$2")" || pc_die 'private pattern scan failed'
  for h in $hits; do report "private identifier (pattern #$h)" "$1"; done
  return 0
}

case "${1:-}" in
  --message-file)
    [ -f "${2:-}" ] || { echo "usage: $0 --message-file FILE" >&2; exit 2; }
    check_text 'commit message' "$2"
    exit "$fail" ;;
  --commits)
    [ -f "${2:-}" ] || { echo "usage: $0 --commits FILE" >&2; exit 2; }
    cp -- "$2" "$tmp/commits" || pc_die 'cannot read the commit list' ;;
  '')
    echo "usage: $0 <rev-list arguments> | --commits FILE | --message-file FILE" >&2; exit 2 ;;
  *)
    git rev-list "$@" > "$tmp/commits" 2>/dev/null || pc_die 'git rev-list failed' ;;
esac

count=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  full="$(git rev-parse --verify --quiet "${c}^{commit}")" || pc_die "not a commit (${c:0:12})"
  short="${full:0:12}"; count=$((count + 1))
  git log -1 --format=%B "$full" > "$tmp/msg" 2>/dev/null || pc_die "git log failed (commit $short)"
  check_text "commit $short message" "$tmp/msg"
  for who in ae ce; do
    email="$(git log -1 --format="%$who" "$full" 2>/dev/null)" || pc_die "git log failed (commit $short)"
    [[ "$email" =~ $noreply_re ]] \
      || report "$( [ "$who" = ae ] && echo author || echo committer ) e-mail is not a no-reply address" "commit $short"
  done
done < "$tmp/commits"

[ "$fail" -ne 0 ] || printf 'PASS: %d commit(s) checked\n' "$count"
exit "$fail"
