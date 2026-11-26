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
# failed run removes exactly what this invocation created.
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
ROOT="/data/bowelnca"
EXPECTED_MOUNT="/data"
EXPECTED_FSTYPE="ext4"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_DIR="${REPO_DIR}/env/xavier"
SMOKE_PY="${REPO_DIR}/scripts/proposed/xavier_smoke_test.py"
SMOKE_TIMEOUT_S=300
# shellcheck source=../lib/workspace_checks.sh
. "${REPO_DIR}/scripts/lib/workspace_checks.sh"

# Run state (globals so the EXIT trap can see them).
STAGE=""
VENV=""
DL_DIR=""
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
  "$PYTHON3" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 8) else 1)' || abort "$PYTHON3 is not 3.8"
  "$PYTHON3" -c 'import ensurepip, venv' 2>/dev/null \
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

acquire_lock() {
  exec 9>>"$ROOT/tmp/.bowelnca-install.lock" || abort "cannot open install lock"
  flock -n 9 || abort "another installation is running (lock held); refusing"
  log "install lock acquired"
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
}

# Lock file without the torch entry (torch is installed from the verified local wheel).
lock_without_torch() {
  awk '/^torch @/ {skip=1; next} skip && /^[[:space:]]/ {next} {skip=0; print}' "$1"
}

# Environment hook sourced by the venv's activate. Caches live INSIDE the venv,
# so removing the venv removes everything the environment ever cached.
write_env_hook() {
  cat > "${VENV}/bin/bowelnca-env.sh" <<EOF
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
  mkdir -p "${VENV}/.cache/xdg" "${VENV}/.cache/torch" "${VENV}/.cache/torch_extensions" "${VENV}/.cache/matplotlib"
  # shellcheck disable=SC2016  # expanded when activate runs
  printf '\n. "${VIRTUAL_ENV}/bin/bowelnca-env.sh"\n' >> "${VENV}/bin/activate"
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
  local py stamp record smoke_json
  local -a pipi
  # Install-time env: no pip cache, no user site, temp on the NVMe.
  export TMPDIR="${ROOT}/tmp" PIP_NO_CACHE_DIR=1 PIP_NO_INPUT=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONNOUSERSITE=1

  DL_DIR="$(mktemp -d "${ROOT}/tmp/torch-dl.XXXXXX")" || abort "cannot create download directory"
  # 1. Download and verify the wheel BEFORE any environment exists.
  curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_URL" \
    || abort "download failed"
  verify_sha256 "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_SHA256"

  # 2. Fresh versioned venv.
  track "$VENV"
  "$PYTHON3" -m venv "$VENV" || abort "venv creation failed"
  py="${VENV}/bin/python"
  pipi=("$py" -m pip install --require-hashes --no-deps --only-binary=:all:)

  # 3. Hash-locked installs.
  # Each step is checked explicitly (|| abort), so failures abort even if a
  # caller disabled errexit.
  "${pipi[@]}" -r "${LOCK_DIR}/requirements-xavier-bootstrap.lock" || abort "pip bootstrap failed"
  if [ "$STAGE" = "core" ]; then
    "${pipi[@]}" -r <(lock_without_torch "${LOCK_DIR}/requirements-xavier-core.lock") || abort "core dependency install failed"
  else
    # The sci lock is a superset of core (constrained by it), so one install covers both.
    "${pipi[@]}" -r <(lock_without_torch "${LOCK_DIR}/requirements-xavier-sci.lock") || abort "scientific stack install failed"
  fi
  "${pipi[@]}" -r <(printf 'torch @ file://%s --hash=sha256:%s\n' "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_SHA256") \
    || abort "torch install failed"
  "$py" -m pip check || abort "pip check failed"

  # 4. Scoped environment hook, then the smoke test through it.
  write_env_hook || abort "could not write the environment hook"
  smoke_json="${DL_DIR}/smoke.json"
  smoke_test "$smoke_json"

  # 5. Environment record (no usernames or hostnames). "result: pass" is written last.
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  record="${ROOT}/reports/env-${STAGE}-${stamp}.txt"
  [ ! -e "$record" ] || abort "record $record already exists"
  track "$record"
  {
    printf 'stage: %s\n' "$STAGE"
    printf 'venv: %s\n' "$VENV"
    printf 'approval_core: %s\n' "${BOWELNCA_CORE_APPROVAL}"
    [ "$STAGE" = "sci" ] && printf 'approval_sci: %s\n' "${BOWELNCA_SCI_APPROVAL}"
    printf 'reviewed_commit: %s\n' "${BOWELNCA_REVIEWED_COMMIT}"
    printf 'l4t: %s\n' "$EXPECTED_L4T"
    printf 'torch_wheel_sha256: %s\n' "$TORCH_SHA256"
    (cd "$LOCK_DIR" && sha256sum requirements-xavier-*.lock) | sed 's/^/lock_sha256: /'
    printf 'smoke: %s\n' "$(tr -d '\n' < "$smoke_json")"
    "$py" -m pip freeze --all | sed 's/^/freeze: /'
    printf 'result: pass\n'
  } > "$record" || abort "could not write the environment record"
  grep -qx 'result: pass' "$record" || abort "environment record incomplete"
  SUCCESS=1
  log "Environment record written to ${record}"
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
