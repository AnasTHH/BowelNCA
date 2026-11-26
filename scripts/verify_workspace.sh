#!/usr/bin/env bash
# Non-destructive verification of the Xavier research workspace.
#
# Default: read-only checks (ownership, mode, mount, filesystem, free space,
# root-filesystem protection, risky group membership).
# --write-test: additionally writes ONE temporary 1 MiB file inside
# $BOWELNCA_ROOT/tmp, verifies it by checksum and deletes it.
#
# Never uses sudo, never changes ownership or permissions, never touches
# anything outside $BOWELNCA_ROOT, and prints no usernames, hostnames,
# device names or addresses (results are PASS/WARN/FAIL plus sizes and modes).
#
# Env: BOWELNCA_ROOT (default /data/bowelnca)
#      BOWELNCA_EXPECTED_MOUNT (default /data)
set -uo pipefail
export LC_ALL=C

ROOT="${BOWELNCA_ROOT:-/data/bowelnca}"
EXPECTED_MOUNT="${BOWELNCA_EXPECTED_MOUNT:-/data}"
SUBDIRS=(workspace venvs datasets derived checkpoints experiments reports cache tmp)
fails=0
warns=0
pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

write_test=0
for arg in "$@"; do
  case "$arg" in
    --write-test) write_test=1 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

printf 'BowelNCA workspace verification, UTC %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
uid="$(id -u)"
[ "$uid" -ne 0 ] && pass "running as an unprivileged user" || fail "running as root (not required)"

# 1. Workspace root
if [ -d "$ROOT" ]; then
  pass "workspace root exists"
  [ "$(stat -c %u "$ROOT")" = "$uid" ] && pass "workspace root owned by current user" || fail "workspace root not owned by current user"
  mode="$(stat -c %a "$ROOT")"
  [ "$mode" = "700" ] && pass "workspace root mode 700" || fail "workspace root mode is $mode (expected 700)"
else
  fail "workspace root missing"
fi

# 2. Subdirectories
for d in "${SUBDIRS[@]}"; do
  p="$ROOT/$d"
  if [ -d "$p" ]; then
    if [ "$(stat -c %u "$p")" = "$uid" ]; then pass "subdir $d exists, owned by current user (mode $(stat -c %a "$p"))"
    else fail "subdir $d not owned by current user"; fi
  else
    fail "subdir $d missing"
  fi
done

# 3. Mount and filesystem (device names are not printed)
if [ -d "$ROOT" ] && command -v findmnt >/dev/null 2>&1; then
  target="$(findmnt -no TARGET -T "$ROOT" 2>/dev/null)"
  fstype="$(findmnt -no FSTYPE -T "$ROOT" 2>/dev/null)"
  [ "$target" = "$EXPECTED_MOUNT" ] && pass "workspace is on mount $EXPECTED_MOUNT ($fstype)" \
    || fail "workspace mount is '$target' (expected $EXPECTED_MOUNT)"
  if [ "$EXPECTED_MOUNT" != "/" ]; then
    [ "$(stat -c %d "$ROOT")" != "$(stat -c %d /)" ] && pass "workspace is NOT on the root filesystem" \
      || fail "workspace is on the root filesystem"
  fi
  if [ -d "$EXPECTED_MOUNT" ] && [ "$EXPECTED_MOUNT" != "/" ]; then
    # Owner's mount must keep its ownership; the research account must not own it.
    [ "$(stat -c %u "$EXPECTED_MOUNT")" != "$uid" ] && pass "$EXPECTED_MOUNT is not owned by the research account (mode $(stat -c %a "$EXPECTED_MOUNT"))" \
      || warn "$EXPECTED_MOUNT is owned by the research account; confirm with the device owner"
  fi
else
  warn "findmnt unavailable or workspace missing; mount not verified"
fi

# 4. Free space (GiB)
if [ -d "$ROOT" ]; then
  ws_free="$(df -BG --output=avail "$ROOT" | tail -n 1 | tr -dc '0-9')"
  printf 'INFO  workspace filesystem free: %s GiB\n' "${ws_free:-?}"
  [ "${ws_free:-0}" -ge 10 ] && pass "at least 10 GiB free for the environment" || fail "less than 10 GiB free on workspace filesystem"
fi
root_free="$(df -BG --output=avail / | tail -n 1 | tr -dc '0-9')"
printf 'INFO  root filesystem free: %s GiB\n' "${root_free:-?}"
[ "${root_free:-0}" -ge 3 ] && pass "root filesystem has at least 3 GiB headroom" || warn "root filesystem below 3 GiB free"

# 5. Root-filesystem protection: research caches should not grow under HOME.
for c in .cache/pip .cache/torch .cache/matplotlib .local/lib; do
  if [ -e "$HOME/$c" ]; then
    size="$(du -sm "$HOME/$c" 2>/dev/null | cut -f1)"
    warn "HOME/$c exists on the root filesystem (${size:-?} MiB); research caches belong under the workspace"
  fi
done
pass "home-directory cache scan complete"

# 6. Risky group membership (names of the checked groups only)
groups_now=" $(id -nG) "
for g in docker sudo admin lxd disk; do
  case "$groups_now" in
    *" $g "*) warn "account is in group '$g' (privileged/root-equivalent); see docs/XAVIER_ACCESS_AND_SECURITY.md" ;;
  esac
done
for g in video render; do
  case "$groups_now" in
    *" $g "*) printf 'INFO  account is in group %s (GPU device access)\n' "$g" ;;
  esac
done

# 7. Optional write test, confined to $ROOT/tmp
if [ "$write_test" -eq 1 ]; then
  if [ -d "$ROOT/tmp" ] && [ -w "$ROOT/tmp" ]; then
    f="$(mktemp "$ROOT/tmp/write-test.XXXXXX")"
    head -c 1048576 /dev/urandom > "$f"
    sum1="$(sha256sum "$f" | cut -d' ' -f1)"
    sync
    sum2="$(sha256sum "$f" | cut -d' ' -f1)"
    fmode="$(stat -c %a "$f")"
    rm -f -- "$f"
    [ "$sum1" = "$sum2" ] && [ ! -e "$f" ] && pass "write test: 1 MiB written, verified and removed (file mode $fmode)" \
      || fail "write test failed"
  else
    fail "write test: $ROOT/tmp missing or not writable"
  fi
fi

printf '\nSummary: %d FAIL, %d WARN. No permissions, ownership or system settings were changed.\n' "$fails" "$warns"
[ "$fails" -eq 0 ]
