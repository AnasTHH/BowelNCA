# shellcheck shell=bash
# Shared, read-only workspace checks for scripts/verify_workspace.sh and
# scripts/proposed/install_xavier_env.sh. Sourced, never executed directly.
#
# The caller defines three reporting functions before calling ws_check_*:
#   ws_pass MSG, ws_warn MSG, ws_fail MSG
# Messages never contain usernames, hostnames, device names or addresses.
#
# Every system query goes through a small ws_* function so the regression
# tests can substitute synthetic identities and mounts. The tests exercise
# control flow; they do not prove the real system calls are correct.
#
# Layouts (docs/XAVIER_ACCESS_AND_SECURITY.md, D20 and D21):
#   interim    current state: the research account owns the whole workspace
#              (mode 700) and still holds sudo. Allowed for verification and
#              the write test only; never for installation.
#   separated  target state (D21, proposed): an administrator account owns the
#              workspace root (mode 750, group = research group) and datasets/
#              (read-only to research); research-owned subdirectories are 700;
#              the research account is in no privileged group.

# shellcheck disable=SC2034  # used by the scripts that source this library
WS_MIN_FREE_BYTES=$((10 * 1024 * 1024 * 1024))
WS_EXEC_SUBDIRS=(workspace venvs derived checkpoints experiments reports cache tmp)
WS_PRIVILEGED_GROUPS=(sudo admin wheel docker lxd libvirt disk)

# --- system queries (overridable in tests) -----------------------------------
ws_current_uid()   { id -u; }
ws_user_gids()     { id -G; }
ws_user_groups()   { id -nG; }
ws_owner_uid()     { stat -c %u -- "$1"; }
ws_owner_gid()     { stat -c %g -- "$1"; }
ws_mode()          { stat -c %a -- "$1"; }
ws_dev()           { stat -c %d -- "$1"; }
ws_writable()      { [ -w "$1" ]; }
ws_mount_target()  { findmnt -n -o TARGET -T "$1" 2>/dev/null; }
ws_mount_fstype()  { findmnt -n -o FSTYPE -T "$1" 2>/dev/null; }
ws_all_mount_targets() { findmnt -r -n -o TARGET; }
# Free bytes available to an unprivileged user (statfs: f_bavail * f_bsize).
ws_avail_bytes() {
  local a s
  read -r a s < <(stat -f -c '%a %S' -- "$1") || return 1
  printf '%s\n' "$((a * s))"
}

# --- predicates ----------------------------------------------------------------
# A path is canonical when it exists, is absolute, is not a symlink and no
# component of it is a symlink (realpath of it is itself).
ws_is_canonical() {
  local p="$1" r
  case "$p" in /*) ;; *) return 1 ;; esac
  [ -e "$p" ] && [ ! -L "$p" ] || return 1
  r="$(realpath -e -- "$p" 2>/dev/null)" || return 1
  [ "$r" = "$p" ]
}

# True when PATH is ROOT or strictly inside ROOT (string check on canonical paths).
ws_is_within() {
  local p="$1" root="$2"
  [ "$p" = "$root" ] && return 0
  case "$p" in "$root"/*) return 0 ;; esac
  return 1
}

ws_in_gid_list() {
  local gid="$1" g
  for g in $(ws_user_gids); do [ "$g" = "$gid" ] && return 0; done
  return 1
}

# --- composite checks ------------------------------------------------------------
# ws_check_account LAYOUT: unprivileged process; privileged groups are a FAIL
# in the separated layout and a WARN in the interim layout.
ws_check_account() {
  local layout="$1" g groups_now
  if [ "$(ws_current_uid)" -ne 0 ]; then ws_pass "running as an unprivileged user"
  else ws_fail "running as root (never required)"; fi
  groups_now=" $(ws_user_groups) "
  for g in "${WS_PRIVILEGED_GROUPS[@]}"; do
    case "$groups_now" in
      *" $g "*)
        if [ "$layout" = "separated" ]; then
          ws_fail "research account is in privileged group '$g' (D21 requires none)"
        else
          ws_warn "account is in privileged group '$g' (interim layout; separation pending, D21)"
        fi ;;
    esac
  done
}

# ws_check_mount ROOT EXPECTED_MOUNT EXPECTED_FSTYPE
ws_check_mount() {
  local root="$1" mnt="$2" fstype="$3" target fs t
  target="$(ws_mount_target "$root")"
  fs="$(ws_mount_fstype "$root")"
  if [ -n "$target" ] && [ "$target" = "$mnt" ]; then ws_pass "workspace is on mount $mnt"
  else ws_fail "workspace mount is '${target:-unknown}' (expected $mnt)"; fi
  if [ "$fs" = "$fstype" ]; then ws_pass "workspace filesystem is $fstype"
  else ws_fail "workspace filesystem is '${fs:-unknown}' (expected $fstype)"; fi
  if [ "$mnt" != "/" ] && [ -e / ]; then
    if [ "$(ws_dev "$root")" != "$(ws_dev /)" ]; then ws_pass "workspace is not on the root filesystem"
    else ws_fail "workspace is on the root filesystem (eMMC protection)"; fi
  fi
  # No other filesystem may be mounted inside the workspace. If the mount
  # table cannot be read (or is empty), fail closed.
  local targets
  if ! targets="$(ws_all_mount_targets)" || [ -z "$targets" ]; then
    ws_fail "could not enumerate mounts; nested-mount check failed closed"
    return 0
  fi
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    case "$t" in "$root"/*) ws_fail "another filesystem is mounted inside the workspace"; return 0 ;; esac
  done <<<"$targets"
  ws_pass "no nested mounts inside the workspace"
}

# ws_check_layout ROOT LAYOUT
ws_check_layout() {
  local root="$1" layout="$2" uid d p mode
  uid="$(ws_current_uid)"
  if ! ws_is_canonical "$root" || [ ! -d "$root" ]; then
    ws_fail "workspace root missing, not a directory, or reached through a symlink"
    return 0
  fi
  ws_pass "workspace root exists and is canonical"
  mode="$(ws_mode "$root")"
  case "$layout" in
    interim)
      if [ "$(ws_owner_uid "$root")" = "$uid" ]; then ws_pass "workspace root owned by the research account (interim)"
      else ws_fail "workspace root not owned by the research account (interim layout expected)"; fi
      if [ "$mode" = "700" ]; then ws_pass "workspace root mode 700"
      else ws_fail "workspace root mode is $mode (interim layout expects 700)"; fi
      ;;
    separated)
      if [ "$(ws_owner_uid "$root")" != "$uid" ]; then ws_pass "workspace root owned by the administrator account, not research"
      else ws_fail "workspace root owned by the research account (separated layout expects the administrator)"; fi
      if ws_in_gid_list "$(ws_owner_gid "$root")"; then ws_pass "workspace root group grants research traversal"
      else ws_fail "workspace root group is not a research-account group"; fi
      if [ "$mode" = "750" ]; then ws_pass "workspace root mode 750"
      else ws_fail "workspace root mode is $mode (separated layout expects 750)"; fi
      if ws_writable "$root"; then ws_fail "workspace root is writable by the research account"
      else ws_pass "workspace root is not writable by the research account"; fi
      ;;
    *) ws_fail "unknown layout '$layout'"; return 0 ;;
  esac

  # Research-owned execution subdirectories.
  for d in "${WS_EXEC_SUBDIRS[@]}"; do
    p="$root/$d"
    if ! ws_is_canonical "$p" || [ ! -d "$p" ]; then
      ws_fail "subdir $d missing, not a directory, or a symlink"; continue
    fi
    if [ "$(ws_owner_uid "$p")" != "$uid" ]; then ws_fail "subdir $d not owned by the research account"; continue; fi
    mode="$(ws_mode "$p")"
    if [ "$mode" = "700" ]; then ws_pass "subdir $d owned by research, mode 700"
    else ws_fail "subdir $d mode is $mode (expected 700)"; fi
    if [ "$(ws_dev "$p")" != "$(ws_dev "$root")" ]; then ws_fail "subdir $d is on a different filesystem"; fi
  done

  # datasets/: read-only to research in the separated layout.
  p="$root/datasets"
  if ! ws_is_canonical "$p" || [ ! -d "$p" ]; then
    ws_fail "subdir datasets missing, not a directory, or a symlink"
  elif [ "$layout" = "separated" ]; then
    if [ "$(ws_owner_uid "$p")" != "$uid" ]; then ws_pass "datasets owned by the administrator account"
    else ws_fail "datasets owned by the research account (must be administrator-owned)"; fi
    if ws_writable "$p"; then ws_fail "datasets is writable by the research account"
    else ws_pass "datasets is read-only to the research account"; fi
    case "$(ws_mode "$p")" in
      750|550) ws_pass "datasets mode $(ws_mode "$p")" ;;
      *) ws_fail "datasets mode is $(ws_mode "$p") (expected 750 or 550)" ;;
    esac
  else
    ws_warn "datasets is research-writable in the interim layout; no data may be transferred before D21"
  fi
}

# ws_check_free ROOT MIN_BYTES
ws_check_free() {
  local root="$1" min="$2" b
  if ! b="$(ws_avail_bytes "$root")"; then ws_fail "could not read free space"; return 0; fi
  printf 'INFO  workspace filesystem free: %s bytes\n' "$b"
  if [ "$b" -ge "$min" ]; then ws_pass "at least $min bytes free on the workspace filesystem"
  else ws_fail "less than $min bytes free on the workspace filesystem"; fi
}

# ws_check_dest ROOT PATH: an installer destination must be canonical, inside
# ROOT, on ROOT's filesystem and owned by the research account. A destination
# that does not exist yet is checked through its nearest existing ancestor.
ws_check_dest() {
  local root="$1" p="$2" probe rel
  rel="${p#"$root"}"; rel="${rel:-/}"
  case "$p" in /*) ;; *) ws_fail "destination $p is not absolute"; return 0 ;; esac
  case "$p" in *"/../"*|*"/./"*|*/..|*/.) ws_fail "destination $p contains . or .. components"; return 0 ;; esac
  ws_is_within "$p" "$root" || { ws_fail "destination $p is outside the workspace"; return 0; }
  probe="$p"
  while [ ! -e "$probe" ] && [ ! -L "$probe" ]; do probe="$(dirname -- "$probe")"; done
  if ! ws_is_canonical "$probe"; then ws_fail "destination ROOT$rel passes through a symlink"; return 0; fi
  ws_is_within "$probe" "$root" || { ws_fail "destination ROOT$rel resolves outside the workspace"; return 0; }
  if [ "$(ws_dev "$probe")" != "$(ws_dev "$root")" ]; then ws_fail "destination ROOT$rel is on a different filesystem"; return 0; fi
  if [ "$probe" != "$root" ] && [ "$(ws_owner_uid "$probe")" != "$(ws_current_uid)" ]; then
    ws_fail "destination ROOT$rel is not owned by the research account"; return 0
  fi
  ws_pass "destination ROOT$rel contained in the workspace"
}

# ws_check_regular_file ROOT PATH: an existing file the installer will open or
# append to must be a regular file (not a symlink, dangling symlink, directory,
# FIFO or device), inside ROOT, research-owned, with a single hard link.
ws_check_regular_file() {
  local root="$1" p="$2" rel
  rel="${p#"$root"}"
  if [ -L "$p" ]; then ws_fail "ROOT$rel is a symlink"; return 0; fi
  if [ ! -e "$p" ]; then ws_pass "ROOT$rel absent"; return 0; fi
  if [ ! -f "$p" ]; then ws_fail "ROOT$rel is not a regular file"; return 0; fi
  if [ "$(ws_owner_uid "$p")" != "$(ws_current_uid)" ]; then ws_fail "ROOT$rel is not owned by the research account"; return 0; fi
  if [ "$(stat -c %h -- "$p")" != "1" ]; then ws_fail "ROOT$rel has extra hard links"; return 0; fi
  ws_check_dest "$root" "$p"
}
