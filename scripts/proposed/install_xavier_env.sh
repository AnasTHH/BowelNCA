#!/usr/bin/env bash
# PROPOSED - NOT APPROVED. Xavier research environment installer (proposed Stage 1A).
#
#   install_xavier_env.sh --stage core [--check-only]
#   install_xavier_env.sh --stage sci  [--check-only]
#
# Two distinct, versioned virtual environments, each with its own approval:
#   core  ${ROOT}/venvs/xavier-jp516-py38-torch21-core-v1
#         NVIDIA JetPack 5 PyTorch wheel + hash-locked runtime deps + CUDA smoke test.
#   sci   ${ROOT}/venvs/xavier-jp516-py38-torch21-sci-v1
#         A NEW venv with core + scientific stack, CUDA smoke test and scientific
#         import checks. Requires a passing core record. Never modifies the core venv.
# Rollback of either stage deletes only that stage's venv and its record.
#
# APPROVAL TOKENS ARE NOT AUTHENTICATION OR AUTHORIZATION. They are a guard
# against accidental execution. Before running, a human must confirm that the
# reference exists in docs/DECISIONS.md, that it approves this stage, and that
# BOWELNCA_REVIEWED_COMMIT is the exact commit that was reviewed. The script
# checks only that the checkout equals that commit and is clean.
#
# Environment:
#   BOWELNCA_CORE_APPROVAL   D<nn>-YYYY-MM-DD-<initials> (both stages; for sci it
#                            must equal the reference recorded by the core install)
#   BOWELNCA_SCI_APPROVAL    same format (sci stage only)
#   BOWELNCA_REVIEWED_COMMIT 40-hex commit that was reviewed (both stages)
#
# Never uses sudo, never touches system packages, power or clock settings,
# and never writes outside /data/bowelnca. Every destination is checked to be
# canonical (no symlinks), inside the workspace, on the workspace filesystem
# and owned by the research account. A lock prevents concurrent runs. A
# failed run removes exactly what this invocation created and keeps private
# diagnostics under /data/bowelnca/reports/diag-*.
#
# These are FILESYSTEM SAFEGUARDS against mistakes and accidental damage. They
# are NOT a security sandbox: package code still runs as the research account
# with its normal permissions. The real controls are the OS account separation
# (D21), hash-locked binary-only installs and human review.
set -euo pipefail
umask 077
export LC_ALL=C

TORCH_WHEEL="torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl"
TORCH_URL="https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/${TORCH_WHEEL}"
TORCH_SHA256="5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe"
EXPECTED_L4T="R35 (release), REVISION: 6.4"
TEGRA_RELEASE_FILE="/etc/nv_tegra_release"
CUDA_HOME_DIR="/usr/local/cuda"
PYTHON3="/usr/bin/python3"
CURL="/usr/bin/curl"
ROOT="/data/bowelnca"
EXPECTED_MOUNT="/data"
EXPECTED_FSTYPE="ext4"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_DIR="${REPO_DIR}/env/xavier"
SMOKE_PY="${REPO_DIR}/scripts/proposed/xavier_smoke_test.py"
VERSIONS_PY="${REPO_DIR}/scripts/proposed/verify_installed_versions.py"
MANIFEST="${REPO_DIR}/env/xavier/dependency-manifest.json"
SMOKE_TIMEOUT_S=300
# shellcheck source=../lib/workspace_checks.sh
. "${REPO_DIR}/scripts/lib/workspace_checks.sh"

# Run state (globals so the EXIT trap can see them).
STAGE=""
VENV=""
DL_DIR=""
DIAG_DIR=""
CREATED=()
SUCCESS=0
PRE_FAILS=0

log()   { printf '[install] %s\n' "$*"; }
abort() { printf '[install] ABORT: %s\n' "$*" >&2; exit 1; }
ws_pass() { log "ok: $1"; }
ws_warn() { log "warning: $1"; }
ws_fail() { printf '[install] FAIL: %s\n' "$1" >&2; PRE_FAILS=$((PRE_FAILS + 1)); }

venv_path() { printf '%s/venvs/xavier-jp516-py38-torch21-%s-v1\n' "$ROOT" "$1"; }

# verify_sha256 FILE EXPECTED: delete FILE and abort unless its SHA-256 matches.
verify_sha256() {
  local file="$1" expected="$2"
  if ! printf '%s  %s\n' "$expected" "$file" | sha256sum --check --strict --status -; then
    rm -f -- "$file"
    abort "SHA-256 mismatch for $(basename "$file"); file deleted, nothing installed"
  fi
  log "SHA-256 verified: $(basename "$file")"
}

valid_approval() { [[ "${1:-}" =~ ^D[0-9]{2}-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z]{2,4}$ ]]; }

approval_notice() {
  log "NOTE: approval references are an accidental-execution guard, not authentication."
  log "      A human must have confirmed the reference in docs/DECISIONS.md and the reviewed commit."
}

check_tokens() {
  valid_approval "${BOWELNCA_CORE_APPROVAL:-}" \
    || abort "NOT APPROVED: set BOWELNCA_CORE_APPROVAL=D<nn>-YYYY-MM-DD-<initials> from a recorded decision"
  if [ "$STAGE" = "sci" ]; then
    valid_approval "${BOWELNCA_SCI_APPROVAL:-}" \
      || abort "NOT APPROVED: --stage sci also needs BOWELNCA_SCI_APPROVAL from its own recorded decision"
  fi
  [[ "${BOWELNCA_REVIEWED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] \
    || abort "NOT APPROVED: set BOWELNCA_REVIEWED_COMMIT to the full 40-hex commit that was reviewed"
}

check_reviewed_commit() {
  local head dirty
  head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)" || abort "repository commit unreadable"
  [ "$head" = "${BOWELNCA_REVIEWED_COMMIT}" ] \
    || abort "checkout is at $head, not the reviewed commit ${BOWELNCA_REVIEWED_COMMIT}"
  dirty="$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" || abort "git status failed"
  [ -z "$dirty" ] || abort "checkout has local modifications or untracked files; refusing"
  log "checkout equals the reviewed commit and is clean"
}

# Read-only host, toolchain, account and workspace checks.
check_host() {
  local out libs ldc f
  [ "$(uname -m)" = "aarch64" ] || abort "not aarch64"
  [ -r "$TEGRA_RELEASE_FILE" ] && grep -qF "$EXPECTED_L4T" "$TEGRA_RELEASE_FILE" \
    || abort "L4T is not ${EXPECTED_L4T} (JetPack 5.1.6)"
  [ -x "$PYTHON3" ] || abort "$PYTHON3 missing"
  [ -x "$CURL" ] || abort "$CURL missing"
  clean_env "$PYTHON3" -I -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 8) else 1)' || abort "$PYTHON3 is not 3.8"
  clean_env "$PYTHON3" -I -c 'import ensurepip, venv' 2>/dev/null \
    || abort "python3 venv/ensurepip unavailable (would need an APPROVED privileged 'apt-get install python3.8-venv')"
  [ -x "${CUDA_HOME_DIR}/bin/nvcc" ] || abort "${CUDA_HOME_DIR}/bin/nvcc missing"
  # Capture first, then match: no pipe, so no SIGPIPE under pipefail.
  out="$("${CUDA_HOME_DIR}/bin/nvcc" --version 2>/dev/null)" || abort "nvcc --version failed"
  grep -q 'release 11\.4' <<<"$out" || abort "CUDA toolkit is not 11.4"
  ldc="$(command -v ldconfig || printf '/sbin/ldconfig')"
  libs="$("$ldc" -p 2>/dev/null)" || libs=""
  grep -qF 'libopenblas.so.0' <<<"$libs" \
    || abort "libopenblas.so.0 missing (would need an APPROVED privileged 'apt-get install libopenblas-dev')"
  for f in requirements-xavier-bootstrap.lock requirements-xavier-core.lock requirements-xavier-sci.lock; do
    [ -r "${LOCK_DIR}/$f" ] || abort "lock file missing: $f"
  done
  grep -q "sha256:${TORCH_SHA256}" "${LOCK_DIR}/requirements-xavier-core.lock" \
    || abort "torch hash in core lock does not match the pinned SHA-256"
  grep -q "sha256:${TORCH_SHA256}" "${LOCK_DIR}/requirements-xavier-sci.lock" \
    || abort "torch hash in sci lock does not match the pinned SHA-256"
  [ -r "$SMOKE_PY" ] || abort "smoke test missing"
  [ -r "$VERSIONS_PY" ] || abort "installed-version verifier missing"
  [ -r "$MANIFEST" ] || abort "dependency manifest missing"
  grep -q "\"sha256\": \"${TORCH_SHA256}\"" "$MANIFEST" || abort "torch hash in dependency manifest does not match the pinned SHA-256"
}

check_workspace() {
  PRE_FAILS=0
  ws_check_account separated
  ws_check_layout "$ROOT" separated
  [ -d "$ROOT" ] && ws_check_mount "$ROOT" "$EXPECTED_MOUNT" "$EXPECTED_FSTYPE"
  [ -d "$ROOT" ] && ws_check_free "$ROOT" "$WS_MIN_FREE_BYTES"
  [ "$PRE_FAILS" -eq 0 ] || abort "$PRE_FAILS workspace/account precondition(s) failed (separated layout, D21, is required)"
}

# Checks that must hold while the lock is held.
check_destinations() {
  local d rec
  PRE_FAILS=0
  for d in "$VENV" "$ROOT/tmp" "$ROOT/reports"; do ws_check_dest "$ROOT" "$d"; done
  [ "$PRE_FAILS" -eq 0 ] || abort "destination containment failed"
  [ ! -e "$VENV" ] && [ ! -L "$VENV" ] || abort "$VENV already exists; refusing to overwrite (see rollback)"
  if [ "$STAGE" = "sci" ]; then
    rec="$(core_record_for "${BOWELNCA_CORE_APPROVAL}")" \
      || abort "no passing core record for ${BOWELNCA_CORE_APPROVAL}; install and validate core first"
    log "core prerequisite satisfied by record $(basename "$rec")"
  fi
}

# core_record_for REF: print a passing core record that used approval REF.
core_record_for() {
  local ref="$1" r
  for r in "$ROOT"/reports/env-core-*.txt; do
    [ -f "$r" ] && [ ! -L "$r" ] || continue
    grep -qx 'stage: core' "$r" && grep -qx "approval_core: ${ref}" "$r" && grep -qx 'result: pass' "$r" \
      && { printf '%s\n' "$r"; return 0; }
  done
  return 1
}

# The lock file is validated before it is opened: an existing path must be a
# research-owned regular file with one link (no symlink, dangling symlink,
# directory, FIFO or device). A new one is created exclusively (noclobber).
# After opening, the descriptor must point at exactly that path.
acquire_lock() {
  local lf="$ROOT/tmp/.bowelnca-install.lock"
  PRE_FAILS=0
  ws_check_regular_file "$ROOT" "$lf"
  [ "$PRE_FAILS" -eq 0 ] || abort "install lock file failed validation; refusing"
  if [ ! -e "$lf" ]; then
    ( set -C; : > "$lf" ) 2>/dev/null || abort "cannot create install lock exclusively"
  fi
  PRE_FAILS=0
  ws_check_regular_file "$ROOT" "$lf"
  [ "$PRE_FAILS" -eq 0 ] || abort "install lock file failed validation; refusing"
  exec 9>>"$lf" || abort "cannot open install lock"
  [ "$(readlink -f "/proc/${BASHPID}/fd/9")" = "$lf" ] || abort "install lock descriptor does not point at the lock file"
  flock -n 9 || abort "another installation is running (lock held); refusing"
  log "install lock acquired"
}

# clean_env CMD...: run CMD with a controlled environment. Inherited
# PYTHONPATH, PYTHONHOME, PIP_TARGET, PIP_PREFIX, PIP_USER, PIP_INDEX_URL and
# every other variable are dropped (only an HTTPS proxy, if set, is passed on);
# pip reads no configuration files (PIP_CONFIG_FILE=/dev/null).
clean_env() {
  local -a extra=()
  [ -n "${HTTPS_PROXY:-}" ] && extra+=("HTTPS_PROXY=${HTTPS_PROXY}")
  env -i \
    PATH=/usr/bin:/bin LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    HOME="${DL_DIR:-/nonexistent}" TMPDIR="${ROOT}/tmp" \
    PIP_CONFIG_FILE=/dev/null PIP_NO_CACHE_DIR=1 PIP_NO_INPUT=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONNOUSERSITE=1 "${extra[@]}" \
    "$@"
}

# track PATH: remember a path this invocation created (for rollback).
track() { CREATED+=("$1"); }

cleanup() {
  local rc=$? i
  [ -n "$DL_DIR" ] && rm -rf -- "$DL_DIR"
  if [ "$SUCCESS" -ne 1 ] && [ "${#CREATED[@]}" -gt 0 ]; then
    for ((i = ${#CREATED[@]} - 1; i >= 0; i--)); do
      ws_is_within "${CREATED[$i]}" "$ROOT" && rm -rf -- "${CREATED[$i]}"
    done
    printf '[install] failed (exit %s); removed %d path(s) created by this run\n' "$rc" "${#CREATED[@]}" >&2
  fi
  if [ "$SUCCESS" -ne 1 ] && [ -n "$DIAG_DIR" ] && [ -d "$DIAG_DIR" ]; then
    printf '[install] diagnostics kept privately in %s (do not publish)\n' "$DIAG_DIR" >&2
  fi
}

# Lock file without the torch entry (torch is installed from the verified local wheel).
lock_without_torch() {
  awk '/^torch @/ {skip=1; next} skip && /^[[:space:]]/ {next} {skip=0; print}' "$1"
}

# Environment hook sourced by the venv's activate. Caches live INSIDE the venv,
# so removing the venv removes everything the environment ever cached.
write_env_hook() {
  local hook="${VENV}/bin/bowelnca-env.sh" d
  {
    cat <<EOF
# BowelNCA research environment (sourced by activate). Nothing in ~/.bashrc.
export CUDA_HOME="${CUDA_HOME_DIR}"
case ":\${PATH}:" in *":\${CUDA_HOME}/bin:"*) ;; *) export PATH="\${CUDA_HOME}/bin:\${PATH}" ;; esac
case ":\${LD_LIBRARY_PATH:-}:" in *":\${CUDA_HOME}/lib64:"*) ;; *) export LD_LIBRARY_PATH="\${CUDA_HOME}/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}" ;; esac
export TMPDIR="${ROOT}/tmp"
export XDG_CACHE_HOME="\${VIRTUAL_ENV}/.cache/xdg"
export TORCH_HOME="\${VIRTUAL_ENV}/.cache/torch"
export TORCH_EXTENSIONS_DIR="\${VIRTUAL_ENV}/.cache/torch_extensions"
export MPLCONFIGDIR="\${VIRTUAL_ENV}/.cache/matplotlib"
export PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_INPUT=1 PYTHONNOUSERSITE=1
EOF
  } > "$hook" || return 1
  [ -s "$hook" ] || return 1
  for d in xdg torch torch_extensions matplotlib; do
    mkdir -p -- "${VENV}/.cache/$d" || return 1
    [ -d "${VENV}/.cache/$d" ] || return 1
  done
  [ -f "${VENV}/bin/activate" ] && [ ! -L "${VENV}/bin/activate" ] || return 1
  # shellcheck disable=SC2016  # expanded when activate runs
  printf '\n. "${VIRTUAL_ENV}/bin/bowelnca-env.sh"\n' >> "${VENV}/bin/activate" || return 1
  # shellcheck disable=SC2016
  grep -qF '. "${VIRTUAL_ENV}/bin/bowelnca-env.sh"' "${VENV}/bin/activate" || return 1
}

# run_scoped CMD...: run CMD in a clean environment through the venv's activate,
# i.e. exactly the environment later research runs will use.
run_scoped() {
  env -i HOME="${HOME:-/nonexistent}" LANG=C.UTF-8 PATH=/usr/bin:/bin \
    bash --noprofile --norc -c '. "$1/bin/activate" && shift && exec "$@"' _ "$VENV" "$@"
}

smoke_test() {
  local out="$1"
  local -a args=(--stage "$STAGE" --cuda-home "$CUDA_HOME_DIR" --out "$out")
  [ "$STAGE" = "sci" ] && args+=(--sci-lock "${LOCK_DIR}/requirements-xavier-sci.lock")
  log "CUDA smoke test in the scoped research environment (bounded; not a benchmark)"
  run_scoped timeout "$SMOKE_TIMEOUT_S" python "$SMOKE_PY" "${args[@]}" || abort "smoke test failed"
}

install_stage() {
  local py stamp record smoke_json lock_hashes smoke_line freeze versions body
  local -a pipi

  # Private diagnostics (never committed; deliberately kept after a failure).
  stamp="$(date -u +%Y%m%dT%H%M%SZ)" || abort "date failed"
  local diag="${ROOT}/reports/diag-${STAGE}-${stamp}"
  PRE_FAILS=0; ws_check_dest "$ROOT" "$diag"
  [ "$PRE_FAILS" -eq 0 ] && [ ! -e "$diag" ] && [ ! -L "$diag" ] || abort "diagnostics directory unavailable"
  mkdir -m 700 -- "$diag" || abort "cannot create diagnostics directory"
  DIAG_DIR="$diag"

  DL_DIR="$(mktemp -d "${ROOT}/tmp/torch-dl.XXXXXX")" || abort "cannot create download directory"
  # 1. Download and verify the wheel BEFORE any environment exists.
  clean_env "$CURL" -fL --proto '=https' --tlsv1.2 --retry 3 -o "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_URL" \
    || abort "download failed"
  verify_sha256 "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_SHA256"

  # 2. Fresh versioned venv, created in a controlled environment (-I: isolated mode).
  track "$VENV"
  clean_env "$PYTHON3" -I -m venv "$VENV" || abort "venv creation failed"
  py="${VENV}/bin/python"
  pipi=(clean_env "$py" -I -m pip install --require-hashes --no-deps --only-binary=:all:
        --no-cache-dir --no-input --disable-pip-version-check --log "${DIAG_DIR}/pip.log")

  # 3. Hash-locked installs. Each step is checked explicitly (|| abort), so a
  # failure aborts even if a caller disabled errexit.
  "${pipi[@]}" -r "${LOCK_DIR}/requirements-xavier-bootstrap.lock" || abort "pip bootstrap failed"
  if [ "$STAGE" = "core" ]; then
    "${pipi[@]}" -r <(lock_without_torch "${LOCK_DIR}/requirements-xavier-core.lock") || abort "core dependency install failed"
  else
    # The sci lock is a superset of core (constrained by it), so one install covers both.
    "${pipi[@]}" -r <(lock_without_torch "${LOCK_DIR}/requirements-xavier-sci.lock") || abort "scientific stack install failed"
  fi
  "${pipi[@]}" -r <(printf 'torch @ file://%s --hash=sha256:%s\n' "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_SHA256") \
    || abort "torch install failed"
  clean_env "$py" -I -m pip check || abort "pip check failed"

  # 4. Scoped environment hook, then the smoke test through it.
  write_env_hook || abort "could not write the environment hook"
  smoke_json="${DIAG_DIR}/smoke.json"
  smoke_test "$smoke_json"

  # 5. Collect every piece of evidence first; each must succeed.
  lock_hashes="$(cd "$LOCK_DIR" && sha256sum requirements-xavier-bootstrap.lock requirements-xavier-core.lock requirements-xavier-sci.lock)" \
    || abort "could not hash the lock files"
  [ "$(grep -c '^[0-9a-f]\{64\}  ' <<<"$lock_hashes")" = "3" ] || abort "lock hashes incomplete"
  [ -f "$smoke_json" ] && [ ! -L "$smoke_json" ] || abort "smoke result missing"
  smoke_line="$(tr -d '\n' < "$smoke_json")" || abort "could not read the smoke result"
  grep -q '"result": "pass"' <<<"$smoke_line" || abort "smoke result is not a pass"
  # Version check through importlib.metadata against the manifest (PEP 440
  # normalized). pip freeze is evidence only: a wheel installed from a local
  # file is listed as a PEP 610 direct reference ("torch @ file:///..."), not
  # "torch==<version>", so freeze text is not parsed for versions.
  versions="$(clean_env "$py" -I "$VERSIONS_PY" --manifest "$MANIFEST" --stage "$STAGE")" \
    || abort "installed versions do not match the dependency manifest: ${versions:-no output}"
  grep -q '"result": "pass"' <<<"$versions" || abort "installed-version check did not pass"
  freeze="$(clean_env "$py" -I -m pip freeze --all)" || abort "pip freeze failed"
  [ -n "$freeze" ] || abort "pip freeze returned nothing"

  body="$(
    printf 'stage: %s\n' "$STAGE"
    printf 'venv: %s\n' "$VENV"
    printf 'approval_core: %s\n' "${BOWELNCA_CORE_APPROVAL}"
    if [ "$STAGE" = "sci" ]; then printf 'approval_sci: %s\n' "${BOWELNCA_SCI_APPROVAL}"; fi
    printf 'reviewed_commit: %s\n' "${BOWELNCA_REVIEWED_COMMIT}"
    printf 'l4t: %s\n' "$EXPECTED_L4T"
    printf 'torch_wheel_sha256: %s\n' "$TORCH_SHA256"
    sed 's/^/lock_sha256: /' <<<"$lock_hashes"
    printf 'smoke: %s\n' "$smoke_line"
    printf 'installed_versions: %s\n' "$versions"
    sed 's/^/freeze: /' <<<"$freeze"
    printf 'diagnostics: %s\n' "$DIAG_DIR"
  )" || abort "could not assemble the environment record"

  # 6. Record: validated destination, exclusive create, "result: pass" last.
  record="${ROOT}/reports/env-${STAGE}-${stamp}.txt"
  PRE_FAILS=0; ws_check_dest "$ROOT" "$record"
  [ "$PRE_FAILS" -eq 0 ] && [ ! -e "$record" ] && [ ! -L "$record" ] \
    || abort "record destination exists, is a symlink, or is not contained"
  ( set -C; printf '%s\n' "$body" > "$record" ) || abort "could not create the environment record exclusively"
  track "$record"
  printf 'result: pass\n' >> "$record" || abort "could not finish the environment record"
  [ "$(tail -n 1 "$record")" = "result: pass" ] || abort "environment record incomplete"
  SUCCESS=1
  log "Environment record written to ${record}"
  log "Diagnostics (private, do not publish): ${DIAG_DIR}"
  log "Done. Activate with: . ${VENV}/bin/activate"
}

main() {
  local check_only=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check-only) check_only=1 ;;
      --stage) shift; STAGE="${1:-}" ;;
      --stage=*) STAGE="${1#--stage=}" ;;
      *) abort "unknown argument: $1" ;;
    esac
    shift
  done
  case "$STAGE" in core|sci) ;; *) abort "choose --stage core or --stage sci" ;; esac
  VENV="$(venv_path "$STAGE")"

  approval_notice
  if [ "$check_only" -eq 0 ]; then
    check_tokens
    check_reviewed_commit
  fi
  check_host
  check_workspace
  if [ "$check_only" -eq 1 ]; then
    [ ! -e "$VENV" ] || log "warning: $VENV already exists; an install would refuse"
    log "Plan: stage ${STAGE}; venv ${VENV}; torch from NVIDIA jp/v512 (SHA-256 pinned); deps from env/xavier/*.lock"
    log "check-only: nothing written, downloaded or installed"
    return 0
  fi

  trap cleanup EXIT
  acquire_lock
  check_destinations
  log "Approval references: core=${BOWELNCA_CORE_APPROVAL}${BOWELNCA_SCI_APPROVAL:+ sci=${BOWELNCA_SCI_APPROVAL}}; reviewed commit ${BOWELNCA_REVIEWED_COMMIT}"
  install_stage
}

if [ "${BOWELNCA_SOURCE_ONLY:-0}" != "1" ]; then
  main "$@"
fi
