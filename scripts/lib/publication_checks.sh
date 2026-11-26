# shellcheck shell=bash
# Shared helpers for scripts/check_repo_policy.sh and
# scripts/check_commit_messages.sh. Sourced, never executed directly.
#
# Contract:
#   - Findings are printed as "FAIL <rule>: <safe reference>" by the caller.
#   - Internal errors (a Git command, a file read or a scanner fails) print
#     "ERROR <what>" and exit 3, so a failure can never look like a pass.
#   - Private pattern values are never printed; patterns are referred to by
#     number (#1 is the first non-comment line).

[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "ERROR bash 4 or newer is required" >&2; exit 3; }

pc_die() { printf 'ERROR %s\n' "$1" >&2; exit 3; }

# pc_grep ARGS...: grep that returns 0 (match) or 1 (no match) and exits 3 on
# any other status (invalid regular expression, unreadable input, ...).
pc_grep() {
  local rc=0
  grep "$@" 2>/dev/null || rc=$?
  [ "$rc" -le 1 ] || pc_die "scanner error (grep exit $rc)"
  return "$rc"
}

# Secret-like strings shared by both checkers.
# shellcheck disable=SC2034  # used by the sourcing scripts
PC_SECRET_RE='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{32,}|hf_[A-Za-z0-9]{30,}|tskey-[A-Za-z0-9-]{10,})'
# Private AI-assistant links (project, session, artifact, chat, share pages)
# and session trailers. Public product pages are allowed.
# shellcheck disable=SC2034
PC_AI_LINK_RE='claude\.ai/(code/)?(session|project|artifact|chat|share)|Claude''-Session:'

pc_stat_mode()  { stat -c %a -- "$1" 2>/dev/null || stat -f %Lp -- "$1" 2>/dev/null; }
pc_stat_owner() { stat -c %u -- "$1" 2>/dev/null || stat -f %u -- "$1" 2>/dev/null; }

# pc_load_patterns REPO_ROOT
# Loads private patterns into PC_PATTERNS. Location:
#   $BOWELNCA_PRIVATE_PATTERNS, else
#   ${XDG_CONFIG_HOME:-$HOME/.config}/bowelnca/private-patterns.txt
# Returns 1 (after printing FAIL lines) if the file is required but missing,
# cannot be resolved or read, is not a regular file owned by the current user,
# is accessible by group or others, lives inside REPO_ROOT, contains an
# invalid expression or one that matches empty text, or (when required)
# contains no patterns. Sets PC_PATTERNS_STATUS to "none" or "loaded".
pc_load_patterns() {
  local root="$1" file real root_real mode owner pat n=0 rc bad=0
  PC_PATTERNS=()
  PC_PATTERNS_STATUS=none
  file="${BOWELNCA_PRIVATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/bowelnca/private-patterns.txt}"
  if [ ! -e "$file" ] && [ ! -L "$file" ]; then
    if [ "${BOWELNCA_REQUIRE_PRIVATE_PATTERNS:-0}" = 1 ]; then
      printf 'FAIL private pattern file required but not found (see SECURITY.md): (pattern file)\n'; return 1
    fi
    return 0
  fi
  real="$(realpath -- "$file" 2>/dev/null)" && [ -e "$real" ] \
    || { printf 'FAIL private pattern file cannot be resolved: (pattern file)\n'; return 1; }
  [ -f "$real" ] || { printf 'FAIL private pattern file is not a regular file: (pattern file)\n'; return 1; }
  [ -r "$real" ] || { printf 'FAIL private pattern file is not readable: (pattern file)\n'; return 1; }
  if [ -n "$root" ]; then
    root_real="$(realpath -- "$root" 2>/dev/null)" || pc_die 'cannot resolve the repository root'
    case "$real/" in
      "$root_real"/*) printf 'FAIL private pattern file must live outside the repository: (pattern file)\n'; return 1 ;;
    esac
  fi
  owner="$(pc_stat_owner "$real")" || pc_die 'cannot read the pattern file owner'
  [ "$owner" = "$(id -u)" ] || { printf 'FAIL private pattern file must be owned by the current user: (pattern file)\n'; return 1; }
  mode="$(pc_stat_mode "$real")" || pc_die 'cannot read the pattern file mode'
  if (( (8#$mode) & 8#077 )); then
    printf 'FAIL private pattern file must not be accessible by group or others (chmod 600): (pattern file)\n'; return 1
  fi
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="${pat%$'\r'}"
    case "$pat" in ''|'#'*) continue ;; esac
    n=$((n + 1))
    rc=0; grep -qE -- "$pat" </dev/null 2>/dev/null || rc=$?
    if [ "$rc" -gt 1 ]; then printf 'FAIL invalid private pattern #%d: (pattern file)\n' "$n"; bad=1; continue; fi
    if grep -qE -- "$pat" <<<'' 2>/dev/null; then
      printf 'FAIL private pattern #%d matches empty text: (pattern file)\n' "$n"; bad=1; continue
    fi
    PC_PATTERNS+=("$pat")
  done < "$real" || pc_die 'cannot read the private pattern file'
  [ "$bad" -eq 0 ] || return 1
  if [ "$n" -eq 0 ] && [ "${BOWELNCA_REQUIRE_PRIVATE_PATTERNS:-0}" = 1 ]; then
    printf 'FAIL private pattern file contains no patterns: (pattern file)\n'; return 1
  fi
  PC_PATTERNS_STATUS=loaded   # read by the sourcing scripts
  export PC_PATTERNS_STATUS
  return 0
}

# pc_private_hits TEXT-FILE: prints the numbers of the patterns that match.
pc_private_hits() {
  local i
  for i in "${!PC_PATTERNS[@]}"; do
    if pc_grep -qaE -- "${PC_PATTERNS[$i]}" "$1"; then printf '%d\n' "$((i + 1))"; fi
  done
}

# pc_private_hits_str STRING: as above, for a short string such as a path.
pc_private_hits_str() {
  local i
  for i in "${!PC_PATTERNS[@]}"; do
    if pc_grep -qaE -- "${PC_PATTERNS[$i]}" <<<"$1"; then printf '%d\n' "$((i + 1))"; fi
  done
}
