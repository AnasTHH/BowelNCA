#!/usr/bin/env bash
# Non-destructive verification of the Xavier research workspace.
#
#   bash scripts/verify_workspace.sh [--layout interim|separated] [--write-test]
#
# --layout interim    (default) current state: research account owns the
#                     workspace (mode 700). Privileged groups are WARN.
# --layout separated  target state proposed in D21: administrator-owned root
#                     (750) and datasets (read-only to research), research-owned
#                     700 subdirectories, no privileged groups (FAIL otherwise).
# --write-test        after ALL read-only checks pass, write ONE 1 MiB temporary
#                     file in /data/bowelnca/tmp, fsync that file only, verify
#                     its size and checksum, and remove it. Skipped (FAIL) if any
#                     earlier check failed. The file is removed on any exit.
#
# Never uses sudo; never changes ownership, permissions or system settings;
# writes nothing except the single temporary file above; prints no usernames,
# hostnames, device names or addresses.
set -uo pipefail
export LC_ALL=C

ROOT="/data/bowelnca"
EXPECTED_MOUNT="/data"
EXPECTED_FSTYPE="ext4"
ROOTFS_MIN_FREE_BYTES=$((3 * 1024 * 1024 * 1024))
WRITE_TEST_BYTES=1048576
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/workspace_checks.sh
. "$LIB_DIR/workspace_checks.sh"

fails=0
warns=0
WT_FILE=""
ws_pass() { printf 'PASS  %s\n' "$1"; }
ws_warn() { printf 'WARN  %s\n' "$1"; warns=$((warns + 1)); }
ws_fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

cleanup_write_test() {
  if [ -n "$WT_FILE" ]; then rm -f -- "$WT_FILE"; WT_FILE=""; fi
}

# write_test: called only when every read-only check passed.
write_test() {
  local dir="$ROOT/tmp" src_sum dst_sum size f
  ws_check_dest "$ROOT" "$dir"
  [ "$fails" -eq 0 ] || { ws_fail "write test: aborted before writing (tmp not contained)"; return 0; }
  if ! WT_FILE="$(mktemp -- "$dir/write-test.XXXXXX")"; then
    WT_FILE=""; ws_fail "write test: could not create temporary file"; return 0
  fi
  # One pipeline; pipefail makes any failed stage (read, tee/write) fail it.
  if ! src_sum="$(dd if=/dev/urandom bs="$WRITE_TEST_BYTES" count=1 iflag=fullblock status=none \
                  | tee -- "$WT_FILE" | sha256sum | cut -d' ' -f1)"; then
    cleanup_write_test; ws_fail "write test: write failed; temporary file removed"; return 0
  fi
  # fsync this one file (coreutils >= 8.24); never a global sync.
  if ! sync -- "$WT_FILE"; then
    cleanup_write_test; ws_fail "write test: fsync failed; temporary file removed"; return 0
  fi
  size="$(stat -c %s -- "$WT_FILE" 2>/dev/null || printf 0)"
  dst_sum="$(sha256sum -- "$WT_FILE" 2>/dev/null | cut -d' ' -f1)"
  f="$WT_FILE"
  cleanup_write_test
  if [ -e "$f" ]; then ws_fail "write test: temporary file not removed"; return 0; fi
  if [ "$size" != "$WRITE_TEST_BYTES" ]; then ws_fail "write test: wrote $size bytes (expected $WRITE_TEST_BYTES)"; return 0; fi
  if [ -z "$src_sum" ] || [ "$src_sum" != "$dst_sum" ]; then ws_fail "write test: checksum mismatch"; return 0; fi
  ws_pass "write test: exactly $WRITE_TEST_BYTES bytes written, fsynced, verified and removed"
}

main() {
  local layout="interim" do_write=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --write-test) do_write=1 ;;
      --layout) shift; layout="${1:-}" ;;
      --layout=*) layout="${1#--layout=}" ;;
      *) printf 'unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
    shift
  done
  case "$layout" in interim|separated) ;; *) printf 'unknown layout: %s\n' "$layout" >&2; return 2 ;; esac

  trap cleanup_write_test EXIT
  trap 'cleanup_write_test; exit 130' INT TERM

  printf 'BowelNCA workspace verification (layout: %s), UTC %s\n' "$layout" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ws_check_account "$layout"
  ws_check_layout "$ROOT" "$layout"
  if [ -d "$ROOT" ]; then
    ws_check_mount "$ROOT" "$EXPECTED_MOUNT" "$EXPECTED_FSTYPE"
    # The device owner's mount keeps its ownership (never the research account).
    if [ -d "$EXPECTED_MOUNT" ] && [ "$EXPECTED_MOUNT" != "/" ]; then
      if [ "$(ws_owner_uid "$EXPECTED_MOUNT")" != "$(ws_current_uid)" ]; then
        ws_pass "$EXPECTED_MOUNT is not owned by the research account"
      else ws_fail "$EXPECTED_MOUNT is owned by the research account; its ownership must stay with the device owner"; fi
    fi
    ws_check_free "$ROOT" "$WS_MIN_FREE_BYTES"
  fi
  local rb
  if rb="$(ws_avail_bytes /)"; then
    printf 'INFO  root filesystem free: %s bytes\n' "$rb"
    if [ "$rb" -ge "$ROOTFS_MIN_FREE_BYTES" ]; then ws_pass "root filesystem has at least 3 GiB headroom"
    else ws_warn "root filesystem below 3 GiB free"; fi
  fi
  # Research caches must not grow under HOME (root filesystem).
  local c size
  for c in .cache/pip .cache/torch .cache/matplotlib .local/lib; do
    if [ -n "${HOME:-}" ] && [ -e "$HOME/$c" ]; then
      size="$(du -sm -- "$HOME/$c" 2>/dev/null | cut -f1)"
      ws_warn "HOME/$c exists on the root filesystem (${size:-?} MiB); research caches belong under the workspace"
    fi
  done
  local g groups_now
  groups_now=" $(ws_user_groups) "
  for g in video render; do
    case "$groups_now" in *" $g "*) printf 'INFO  account is in group %s (GPU device access)\n' "$g" ;; esac
  done

  if [ "$do_write" -eq 1 ]; then
    if [ "$fails" -eq 0 ]; then write_test
    else ws_fail "write test: SKIPPED because $fails read-only check(s) failed; nothing was written"; fi
  fi

  printf '\nSummary: %d FAIL, %d WARN. No permissions, ownership or system settings were changed.\n' "$fails" "$warns"
  [ "$fails" -eq 0 ]
}

if [ "${BOWELNCA_SOURCE_ONLY:-0}" != "1" ]; then
  main "$@"
fi
