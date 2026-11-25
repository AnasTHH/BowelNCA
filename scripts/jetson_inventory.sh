#!/usr/bin/env bash
# Stage 0: read-only inventory. No sudo, installs, network calls or host changes.
#
# Safety properties (enforced by tests/test_inventory_readonly.sh in CI):
#   - never invokes sudo, package managers, pip install, nvpmodel -m,
#     jetson_clocks (only checks whether it exists), systemctl, or any writer;
#   - never prints hostname, usernames, IP/MAC addresses or home paths;
#   - parses /etc/os-release instead of sourcing (executing) it;
#   - the only GPU touch is an optional, already-installed torch import that
#     creates and releases a CUDA context; no kernels are trained or benchmarked.
# Output goes to stdout only. Review and redact before sharing.
set -u
export LC_ALL=C

say() { printf '\n== %s ==\n' "$1"; }
print_file() { if [ -r "$1" ]; then cat "$1"; else printf 'unavailable: %s\n' "$1"; fi; }
run_if_found() {
  local command_name="$1"
  shift
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" "$@" 2>&1 || printf '%s returned an error\n' "$command_name"
  else
    printf '%s not installed\n' "$command_name"
  fi
}
os_release_field() {
  # Read KEY="value" from /etc/os-release without executing the file.
  sed -n "s/^$1=//p" /etc/os-release 2>/dev/null | head -n 1 | tr -d '"'
}

printf 'NCA Stage 0 READ-ONLY inventory, UTC: '
date -u '+%Y-%m-%dT%H:%M:%SZ'
if [ "$(id -u)" -eq 0 ]; then
  printf 'WARNING: running as root is not required and not recommended for Stage 0.\n'
fi

say 'Jetson model'
if [ -r /proc/device-tree/model ]; then tr -d '\000' < /proc/device-tree/model; printf '\n'; else printf 'model not readable\n'; fi
if [ -r /proc/device-tree/compatible ]; then printf 'compatible: '; tr '\000' ' ' < /proc/device-tree/compatible; printf '\n'; fi

say 'System'
uname -srm
if [ -r /etc/os-release ]; then
  printf 'OS release: %s %s\n' "$(os_release_field NAME)" "$(os_release_field VERSION_ID)"
else
  printf 'OS release: unavailable\n'
fi

say 'L4T / Jetson release'
print_file /etc/nv_tegra_release

say 'JetPack and NVIDIA library packages (dpkg query only)'
if command -v dpkg-query >/dev/null 2>&1; then
  for pkg in nvidia-jetpack nvidia-l4t-core cuda-toolkit-11-4 cuda-runtime-11-4 libcudnn8 tensorrt libnvinfer8 python3-libnvinfer; do
    dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' "$pkg" 2>/dev/null || printf '%s not installed\n' "$pkg"
  done
else
  printf 'dpkg-query not installed\n'
fi

say 'Python and machine architecture'
run_if_found python3 -c 'import sys, platform; print(sys.version.replace("\n", " ")); print("abi tag: cp%d%d" % sys.version_info[:2]); print("machine:", platform.machine())'
run_if_found python3 -m pip --version
for py in python3.9 python3.10 python3.11; do
  if command -v "$py" >/dev/null 2>&1; then printf '%s: present (%s)\n' "$py" "$("$py" --version 2>&1)"; fi
done

say 'CUDA compiler'
if command -v nvcc >/dev/null 2>&1; then
  nvcc --version 2>&1
elif [ -x /usr/local/cuda/bin/nvcc ]; then
  printf 'nvcc not on PATH; found /usr/local/cuda/bin/nvcc\n'
  /usr/local/cuda/bin/nvcc --version 2>&1
else
  printf 'nvcc not installed\n'
fi
for d in /usr/local/cuda*; do [ -e "$d" ] && printf 'cuda dir: %s\n' "$d"; done

say 'Memory and swap'
run_if_found free -h
run_if_found swapon --show

say 'Storage'
run_if_found df -h / /home
run_if_found lsblk -d -o NAME,SIZE,TYPE,ROTA

say 'Current power mode (query only)'
if command -v nvpmodel >/dev/null 2>&1; then nvpmodel -q 2>&1 || printf 'nvpmodel query unavailable to current user\n'; else printf 'nvpmodel not installed\n'; fi

say 'Thermal zones (read-only sysfs, millidegrees C)'
found_zone=0
for zone in /sys/class/thermal/thermal_zone*; do
  [ -r "$zone/temp" ] || continue
  found_zone=1
  printf '%s %s\n' "$(cat "$zone/type" 2>/dev/null || printf unknown)" "$(cat "$zone/temp" 2>/dev/null || printf unreadable)"
done
[ "$found_zone" -eq 1 ] || printf 'no readable thermal zones\n'

say 'GPU telemetry tool availability (presence only, none executed)'
for tool in tegrastats jtop jetson_clocks docker; do
  if command -v "$tool" >/dev/null 2>&1; then printf '%s: available\n' "$tool"; else printf '%s: absent\n' "$tool"; fi
done

say 'PyTorch/CUDA smoke (only if torch already installed)'
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import os, platform
HOME = os.path.expanduser('~')
def clean(text):
    return str(text).replace(HOME, '~') if HOME and HOME != '/' else str(text)
print('arch:', platform.machine())
for mod in ('numpy', 'torchvision'):
    try:
        m = __import__(mod)
        print(mod + ':', getattr(m, '__version__', 'unknown'))
    except Exception as exc:
        print(mod + ' import unavailable:', type(exc).__name__)
try:
    import torch
    print('torch:', torch.__version__)
    print('torch CUDA build:', torch.version.cuda)
    print('cuDNN:', torch.backends.cudnn.version() if torch.backends.cudnn.is_available() else 'unavailable')
    available = torch.cuda.is_available()
    print('torch.cuda.is_available:', available)
    if available:
        try:
            print('GPU:', torch.cuda.get_device_name(0))
            print('compute capability:', torch.cuda.get_device_capability(0))
            free, total = torch.cuda.mem_get_info()
            print('GPU CUDA allocator free/total bytes:', free, total)
        except Exception as exc:
            print('GPU-detail warning:', type(exc).__name__, clean(exc))
except Exception as exc:
    print('torch import unavailable:', type(exc).__name__, clean(exc))
PY
else
  printf 'python3 unavailable\n'
fi

say 'End of read-only inventory'
printf 'No sudo or system mutation was attempted. Redact logs before sharing.\n'
