#!/usr/bin/env bash
# Repository policy check for a PUBLIC research repository.
# Fails if tracked files include medical images, model checkpoints, archives,
# secrets/keys, unredacted local inventory logs, or oversized files.
# Runs on synthetic/no data only; safe for hosted CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
fail=0
max_bytes=$((2 * 1024 * 1024))

mapfile -t files < <(git ls-files)

forbidden_ext='\.(nii|nii\.gz|mha|mhd|nrrd|dcm|dicom|ima|img|hdr|npz|npy|h5|hdf5|pt|pth|ckpt|safetensors|onnx|engine|trt|whl|zip|tar|tgz|gz|7z|pem|key|p12|pfx|ppk|kdbx)$'
forbidden_name='(^|/)(\.env(\..*)?|id_(rsa|ed25519|ecdsa|dsa)(\.pub)?|known_hosts|authorized_keys|credentials(\.json)?|.*_inventory_local\.log|splits_private.*)$'

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  if grep -qiE "$forbidden_ext" <<<"$f"; then printf 'FAIL forbidden file type: %s\n' "$f"; fail=1; fi
  if grep -qiE "$forbidden_name" <<<"$f"; then printf 'FAIL forbidden file name: %s\n' "$f"; fail=1; fi
  size=$(wc -c < "$f")
  if [ "$size" -gt "$max_bytes" ]; then printf 'FAIL file over 2 MiB: %s (%s bytes)\n' "$f" "$size"; fail=1; fi
  case "$f" in data/*|artifacts/*|checkpoints/*|runs/*) printf 'FAIL tracked file under ignored data dir: %s\n' "$f"; fail=1 ;; esac
done

# Secret-like content (skip this script, which contains the patterns).
secret_re='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,})'
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  [ "$f" = "scripts/check_repo_policy.sh" ] && continue
  if grep -qIE -- "$secret_re" "$f"; then printf 'FAIL secret-like content in: %s\n' "$f"; fail=1; fi
done

# Required governance files.
for f in CLAUDE.md docs/DEVELOPMENT_PLAN_v1.2.md docs/DATA_GOVERNANCE.md .gitignore; do
  [ -f "$f" ] || { printf 'FAIL missing required file: %s\n' "$f"; fail=1; }
done

if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: repository policy (%d tracked files)\n' "${#files[@]}"
