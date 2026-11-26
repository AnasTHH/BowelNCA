#!/usr/bin/env bash
# PROPOSED - NOT APPROVED. Xavier research environment installer (Stage 0 proposal).
#
# Creates an UNPRIVILEGED Python 3.8 virtual environment on the NVMe research
# workspace with NVIDIA's JetPack 5.1.x PyTorch wheel and hash-locked
# dependencies, then runs a bounded CUDA smoke test. It never uses sudo,
# never touches system packages, never changes power/clock settings, and
# never writes outside $BOWELNCA_ROOT (default /data/bowelnca).
#
# Modes:
#   --check-only        Run the read-only precondition checks and print the plan.
#                       Downloads and installs nothing. Needs no approval token.
#   (default)           Install core runtime + smoke test. Refuses to run unless
#                       BOWELNCA_INSTALL_APPROVAL is set to a recorded approval
#                       reference (format: D<nn>-YYYY-MM-DD-<initials>).
#   --with-sci          Also install the scientific stack. Additionally requires
#                       BOWELNCA_SCI_APPROVAL (same format).
#
# Fail-closed: `set -euo pipefail`; every precondition aborts on failure; the
# PyTorch wheel is SHA-256 verified before any virtualenv exists; every pip
# install uses --require-hashes --no-deps --only-binary=:all: against the
# committed lock files, so pip can neither resolve unpinned packages nor
# replace NVIDIA's torch with a PyPI build; a failed run removes the venv it
# created.
#
# Rollback: see docs/XAVIER_ENVIRONMENT.md ("Rollback").
set -euo pipefail
umask 077

readonly TORCH_WHEEL="torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl"
readonly TORCH_URL="https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/${TORCH_WHEEL}"
readonly TORCH_SHA256="5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe"
readonly EXPECTED_L4T="R35 (release), REVISION: 6.4"
readonly MIN_FREE_GIB=10

ROOT="${BOWELNCA_ROOT:-/data/bowelnca}"
VENV="${ROOT}/venvs/xavier-jp516-py38-torch21"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_DIR="${REPO_DIR}/env/xavier"
DL_DIR=""
CREATED_VENV=0

log()   { printf '[install] %s\n' "$*"; }
abort() { printf '[install] ABORT: %s\n' "$*" >&2; exit 1; }

# verify_sha256 FILE EXPECTED: delete FILE and abort unless its SHA-256 matches.
verify_sha256() {
  local file="$1" expected="$2"
  if ! printf '%s  %s\n' "$expected" "$file" | sha256sum --check --strict --status -; then
    rm -f -- "$file"
    abort "SHA-256 mismatch for $(basename "$file"); file deleted, nothing installed"
  fi
  log "SHA-256 verified: $(basename "$file")"
}

valid_approval() { [[ "$1" =~ ^D[0-9]{2}-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z]{2,4}$ ]]; }

check_preconditions() {
  log "Checking preconditions (read-only)"
  [ "$(id -u)" -ne 0 ] || abort "must not run as root"
  [ "$(uname -m)" = "aarch64" ] || abort "not aarch64"
  grep -qF "$EXPECTED_L4T" /etc/nv_tegra_release 2>/dev/null || abort "L4T is not ${EXPECTED_L4T} (JetPack 5.1.6)"
  command -v python3 >/dev/null || abort "python3 missing"
  python3 -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 8) else 1)' || abort "python3 is not 3.8"
  python3 -c 'import ensurepip, venv' 2>/dev/null \
    || abort "python3 venv/ensurepip unavailable (would need an APPROVED privileged 'apt-get install python3.8-venv')"
  [ -x /usr/local/cuda/bin/nvcc ] || abort "/usr/local/cuda/bin/nvcc missing"
  /usr/local/cuda/bin/nvcc --version | grep -q 'release 11.4' || abort "CUDA toolkit is not 11.4"
  ldconfig -p 2>/dev/null | grep -q 'libopenblas.so.0' \
    || abort "libopenblas.so.0 missing (would need an APPROVED privileged 'apt-get install libopenblas-dev')"
  [ -d "$ROOT" ] || abort "workspace $ROOT missing"
  [ "$(stat -c %u "$ROOT")" = "$(id -u)" ] || abort "workspace not owned by current user"
  [ "$(stat -c %a "$ROOT")" = "700" ] || abort "workspace mode is not 700"
  [ "$(stat -c %d "$ROOT")" != "$(stat -c %d /)" ] || abort "workspace is on the root filesystem; refusing (eMMC protection)"
  local free_gib
  free_gib=$(df -BG --output=avail "$ROOT" | tail -n 1 | tr -dc '0-9')
  [ "${free_gib:-0}" -ge "$MIN_FREE_GIB" ] || abort "less than ${MIN_FREE_GIB} GiB free on workspace filesystem"
  [ ! -e "$VENV" ] || abort "$VENV already exists; refusing to overwrite (see rollback)"
  for f in requirements-xavier-bootstrap.lock requirements-xavier-core.lock requirements-xavier-sci.lock; do
    [ -r "${LOCK_DIR}/$f" ] || abort "lock file missing: $f"
  done
  grep -q "sha256:${TORCH_SHA256}" "${LOCK_DIR}/requirements-xavier-core.lock" \
    || abort "torch hash in core lock does not match the pinned SHA-256"
  log "All preconditions passed"
}

# Keep every cache, temp file and build artefact on the NVMe workspace.
scoped_env() {
  export TMPDIR="${ROOT}/tmp"
  export PIP_CACHE_DIR="${ROOT}/cache/pip"
  export XDG_CACHE_HOME="${ROOT}/cache/xdg"
  export TORCH_HOME="${ROOT}/cache/torch"
  export TORCH_EXTENSIONS_DIR="${ROOT}/cache/torch_extensions"
  export MPLCONFIGDIR="${ROOT}/cache/matplotlib"
  export PYTHONPYCACHEPREFIX="${ROOT}/cache/pycache"
  export PIP_NO_INPUT=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONNOUSERSITE=1
  mkdir -p "$TMPDIR" "$PIP_CACHE_DIR" "$XDG_CACHE_HOME" "$TORCH_HOME" \
           "$TORCH_EXTENSIONS_DIR" "$MPLCONFIGDIR" "$PYTHONPYCACHEPREFIX"
}

# Lock file without the torch entry (torch is installed from the verified local wheel).
lock_without_torch() {
  awk '/^torch @/ {skip=1; next} skip && /^[[:space:]]/ {next} {skip=0; print}' "$1"
}

write_env_hook() {
  cat > "${VENV}/bin/bowelnca-env.sh" <<EOF
# Sourced by this venv's activate script. Scoped to the research environment;
# nothing is written to ~/.bashrc. Open a new shell after 'deactivate'.
export CUDA_HOME=/usr/local/cuda
export PATH="\${CUDA_HOME}/bin:\${PATH}"
export LD_LIBRARY_PATH="\${CUDA_HOME}/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export TMPDIR="${ROOT}/tmp"
export PIP_CACHE_DIR="${ROOT}/cache/pip"
export XDG_CACHE_HOME="${ROOT}/cache/xdg"
export TORCH_HOME="${ROOT}/cache/torch"
export TORCH_EXTENSIONS_DIR="${ROOT}/cache/torch_extensions"
export MPLCONFIGDIR="${ROOT}/cache/matplotlib"
export PYTHONPYCACHEPREFIX="${ROOT}/cache/pycache"
export PYTHONNOUSERSITE=1
EOF
  printf '\n. "${VIRTUAL_ENV}/bin/bowelnca-env.sh"\n' >> "${VENV}/bin/activate"
}

smoke_test() {
  log "CUDA smoke test (bounded; not a benchmark)"
  timeout 300 env CUDA_HOME=/usr/local/cuda "${VENV}/bin/python" - <<'PY'
import sys, torch
print("torch", torch.__version__, "| CUDA build", torch.version.cuda, "| cuDNN", torch.backends.cudnn.version())
assert torch.version.cuda == "11.4", "unexpected CUDA build"
assert torch.cuda.is_available(), "CUDA not available"
print("device", torch.cuda.get_device_name(0), "| capability", torch.cuda.get_device_capability(0))
# 1. Tensor functionality: GPU result must match CPU result.
a = torch.arange(1024 * 1024, dtype=torch.float32).reshape(1024, 1024) / 1e6
ref = a @ a.T
got = (a.cuda() @ a.cuda().T).cpu()
assert torch.allclose(ref, got, rtol=1e-3, atol=1e-2), "GPU/CPU matmul mismatch"
print("tensor check: OK")
# 2. Memory allocation smoke: 256 MiB, write, read back, release.
free0, total = torch.cuda.mem_get_info()
x = torch.ones(64 * 1024 * 1024, dtype=torch.float32, device="cuda")  # 256 MiB
torch.cuda.synchronize()
assert float(x.sum().item()) == float(x.numel()), "allocation readback mismatch"
peak = torch.cuda.max_memory_allocated()
del x
torch.cuda.empty_cache()
free1, _ = torch.cuda.mem_get_info()
print("alloc check: OK | peak_allocated_MiB %.1f | free_before_MiB %.0f | free_after_MiB %.0f | total_MiB %.0f"
      % (peak / 2**20, free0 / 2**20, free1 / 2**20, total / 2**20))
PY
}

main() {
  local mode="install" with_sci=0
  for arg in "$@"; do
    case "$arg" in
      --check-only) mode="check" ;;
      --with-sci) with_sci=1 ;;
      *) abort "unknown argument: $arg" ;;
    esac
  done

  if [ "$mode" = "install" ]; then
    valid_approval "${BOWELNCA_INSTALL_APPROVAL:-}" \
      || abort "NOT APPROVED: set BOWELNCA_INSTALL_APPROVAL=D<nn>-YYYY-MM-DD-<initials> from a recorded decision"
    if [ "$with_sci" -eq 1 ]; then
      valid_approval "${BOWELNCA_SCI_APPROVAL:-}" || abort "NOT APPROVED: --with-sci needs BOWELNCA_SCI_APPROVAL"
    fi
  fi

  check_preconditions
  if [ "$mode" = "check" ]; then
    log "Plan: venv ${VENV}; torch from NVIDIA jp/v512 (SHA-256 pinned); deps from env/xavier/*.lock"
    log "check-only: nothing downloaded or installed"
    return 0
  fi

  log "Approval reference: ${BOWELNCA_INSTALL_APPROVAL}"
  scoped_env
  DL_DIR="$(mktemp -d "${ROOT}/tmp/torch-dl.XXXXXX")"
  cleanup() {
    local rc=$?
    [ -n "$DL_DIR" ] && rm -rf -- "$DL_DIR"
    if [ "$rc" -ne 0 ] && [ "$CREATED_VENV" -eq 1 ]; then
      rm -rf -- "$VENV"
      printf '[install] failed (exit %s); removed partially created %s\n' "$rc" "$VENV" >&2
    fi
  }
  trap cleanup EXIT

  # 1. Download and verify the wheel BEFORE any environment exists.
  curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_URL"
  verify_sha256 "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_SHA256"

  # 2. Virtual environment on the NVMe workspace.
  CREATED_VENV=1
  python3 -m venv "$VENV"
  local py="${VENV}/bin/python"
  local pipi=("$py" -m pip install --require-hashes --no-deps --only-binary=:all:)

  # 3. Hash-locked installs (pip bootstrap, core deps, verified torch wheel).
  "${pipi[@]}" -r "${LOCK_DIR}/requirements-xavier-bootstrap.lock"
  "${pipi[@]}" -r <(lock_without_torch "${LOCK_DIR}/requirements-xavier-core.lock")
  "${pipi[@]}" -r <(printf 'torch @ file://%s --hash=sha256:%s\n' "${DL_DIR}/${TORCH_WHEEL}" "$TORCH_SHA256")
  if [ "$with_sci" -eq 1 ]; then
    log "Scientific stack approval reference: ${BOWELNCA_SCI_APPROVAL}"
    "${pipi[@]}" -r <(lock_without_torch "${LOCK_DIR}/requirements-xavier-sci.lock")
  fi
  "$py" -m pip check

  # 4. Scoped CUDA PATH and caches; smoke test.
  write_env_hook
  smoke_test

  # 5. Environment record (no usernames or hostnames).
  local stamp record
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  record="${ROOT}/reports/env-${stamp}.txt"
  {
    printf 'approval: %s\n' "${BOWELNCA_INSTALL_APPROVAL}"
    printf 'repo_commit: %s\n' "$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'l4t: %s\n' "$EXPECTED_L4T"
    sha256sum "${LOCK_DIR}"/requirements-xavier-*.lock | sed "s|${LOCK_DIR}/||"
    "$py" -m pip freeze --all
  } > "$record"
  log "Environment record written to ${record}"
  log "Done. Activate with: . ${VENV}/bin/activate"
}

if [ "${BOWELNCA_SOURCE_ONLY:-0}" != "1" ]; then
  main "$@"
fi
