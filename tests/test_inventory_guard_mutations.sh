#!/usr/bin/env bash
# Mutation test for the regression check tests/test_inventory_readonly.sh:
# injects known-forbidden commands into a temporary copy of the inventory
# script and requires the check to reject every mutant WITHOUT executing it.
# This measures the deny-list's coverage of known patterns only; it is not
# evidence that the inventory script is safe against unknown mutations.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mutants=(
  'sudo nvpmodel -m 0'
  'jetson_clocks'
  'pip3 install torch'
  'python3 -m pip install numpy'
  'apt-get install -y libopenblas-dev'
  'hostname'
  '. /etc/os-release'
  'printf x > /etc/foo'
  'curl -s https://example.invalid'
  'rm -rf /tmp/x'
  'systemctl restart nvpmodel'
  'lsblk -o NAME,SERIAL'
  'python3 -m pip --version'
)
fail=0
for mutant in "${mutants[@]}"; do
  copy="$work/jetson_inventory.sh"
  marker="$work/EXECUTED"
  rm -f "$marker"
  # Inject the mutant followed by a marker write; if the guard ever runs the
  # mutant, the marker file appears.
  awk -v inj="$mutant" -v mk="$marker" \
    '{print} /^say .System.$/ {print inj; print ": > \"" mk "\""}' \
    "$repo_root/scripts/jetson_inventory.sh" > "$copy"
  if INVENTORY_SCRIPT="$copy" bash "$repo_root/tests/test_inventory_readonly.sh" >/dev/null 2>&1; then
    printf 'FAIL: guard accepted mutant: %s\n' "$mutant"; fail=1
  fi
  if [ -e "$marker" ]; then
    printf 'FAIL: guard executed mutant: %s\n' "$mutant"; fail=1
  fi
done
if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: guard rejected all %d mutants without executing them\n' "${#mutants[@]}"
