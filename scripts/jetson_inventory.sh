#!/usr/bin/env bash
# Stage 0: read-only inventory. No sudo, installs, network calls or host changes.
set -u

say() { printf '\n== %s ==\n' "$1"; }
print_file() { if [ -r "$1" ]; then cat "$1"; else printf 'unavailable: %s\n' "$1"; fi; }
run_if_found() {
  local command_name="$1"
  shift
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" "$@" || printf '%s returned an error\n' "$command_name"
  else
    printf '%s not installed\n' "$command_name"
  fi
}

printf 'NCA Stage 0 READ-ONLY inventory, UTC: '
date -u '+%Y-%m-%dT%H:%M:%SZ'
say 'Jetson model'
if [ -r /proc/device-tree/model ]; then tr -d '\000' < /proc/device-tree/model; printf '\n'; else printf 'model not readable\n'; fi
say 'System'
uname -srm
printf 'OS release: '
if [ -r /etc/os-release ]; then . /etc/os-release; printf '%s %s\n' "${NAME:-unknown}" "${VERSION_ID:-unknown}"; else printf 'unavailable\n'; fi
say 'L4T / Jetson release'
print_file /etc/nv_tegra_release
say 'Python and machine architecture'
run_if_found python3 --version
run_if_found uname -m
say 'CUDA compiler'
run_if_found nvcc --version
say 'Memory and swap'
run_if_found free -h
say 'Storage'
run_if_found df -h / /home
say 'Current power mode (query only)'
if command -v nvpmodel >/dev/null 2>&1; then nvpmodel -q 2>&1 || printf 'nvpmodel query unavailable to current user\n'; else printf 'nvpmodel not installed\n'; fi
say 'GPU telemetry tool availability'
for tool in tegrastats jtop jetson_clocks docker; do
  if command -v "$tool" >/dev/null 2>&1; then printf '%s: available\n' "$tool"; else printf '%s: absent\n' "$tool"; fi
done
say 'PyTorch/CUDA smoke (only if torch already installed)'
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import platform
print('arch:', platform.machine())
try:
    import torch
    print('torch:', torch.__version__)
    print('torch CUDA build:', torch.version.cuda)
    available = torch.cuda.is_available()
    print('torch.cuda.is_available:', available)
    if available:
        try:
            print('GPU:', torch.cuda.get_device_name(0))
            free, total = torch.cuda.mem_get_info()
            print('GPU CUDA allocator free/total bytes:', free, total)
        except Exception as exc:
            print('GPU-detail warning:', type(exc).__name__, str(exc))
except Exception as exc:
    print('torch import unavailable:', type(exc).__name__, str(exc))
PY
else
  printf 'python3 unavailable\n'
fi
say 'End of read-only inventory'
printf 'No sudo or system mutation was attempted. Redact logs before sharing.\n'
