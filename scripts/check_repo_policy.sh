#!/usr/bin/env bash
# Repository policy check for a PUBLIC research repository.
#
# Fails if tracked files include: restricted data/steward/test directories at
# any depth, medical images, model weights and other run artefacts, archives,
# logs and raw console output, secrets/keys, oversized files, or committed
# device evidence that lacks a redaction attestation or contains identifiers.
#
# This is a safety net for mistakes, not an access control. Runs on file
# names and text only; safe for hosted CI.
#
# Usage: scripts/check_repo_policy.sh [repo_root]   (default: git toplevel)
set -euo pipefail

root="${1:-$(git rev-parse --show-toplevel)}"
cd "$root"
fail=0
max_bytes=$((2 * 1024 * 1024))
report() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }

mapfile -t files < <(git ls-files)

# 1. Restricted directories, matched as a path segment at ANY depth.
restricted_dirs='data|raw_data|raw_dev|derived|private_data_steward|source_archive|canonical_and_duplicates|locked_test|test_data|approved_dev_transfer|second_labels|alternate_labels|artifacts|artefacts|checkpoints|weights|runs|outputs|logs|wandb|mlruns|aim|\.aim|lightning_logs|nnUNet_raw|nnUNet_preprocessed|nnUNet_results|third_party|upstream|OctreeNCA|\.ssh'
# 2. Imaging, weights, run artefacts, archives, keys.
forbidden_ext='\.(nii|nii\.gz|mha|mhd|nrrd|dcm|dicom|ima|img|hdr|mgz|tif|tiff|svs|npy|npz|h5|hdf5|mat|pkl|pickle|joblib|pt|pth|ckpt|safetensors|onnx|engine|trt|plan|tflite|bin|whl|zip|tar|gz|tgz|bz2|xz|7z|rar|pem|key|p12|pfx|ppk|kdbx|keystore|jks)$'
# 3. Logs and raw console/run output (redacted evidence must be .txt/.md under reports/evidence/).
forbidden_log='(\.log|\.out|\.err|\.stdout|\.stderr|\.tfevents\..*|events\.out\..*|nohup\.out)$'
# 4. Secret-bearing or private file names.
forbidden_name='(^|/)(\.env(\..*)?|\.netrc|\.pgpass|id_(rsa|ed25519|ecdsa|dsa)(\.pub)?|known_hosts|authorized_keys|credentials(\.json)?|service[-_]account.*\.json|.*_inventory_local\..*|splits_private.*|test_ids.*|.*\.sha256\.private)$'

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  if grep -qE "(^|/)(${restricted_dirs})/" <<<"$f"; then report 'restricted directory' "$f"; fi
  if grep -qiE "$forbidden_ext" <<<"$f"; then report 'forbidden file type' "$f"; fi
  if grep -qiE "$forbidden_log" <<<"$f"; then report 'log/raw output file' "$f"; fi
  if grep -qiE "$forbidden_name" <<<"$f"; then report 'forbidden file name' "$f"; fi
  size=$(wc -c < "$f")
  if [ "$size" -gt "$max_bytes" ]; then report 'file over 2 MiB' "$f ($size bytes)"; fi
  # Binary files outside an explicit allow-list (docs images) are suspicious.
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.svg)
      case "$f" in docs/figures/*|docs/img/*) ;; *) report 'image outside docs/figures (possible patient overlay)' "$f" ;; esac ;;
  esac
done

# 5. Secret-like content (this script and its test contain the patterns).
secret_re='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{32,}|hf_[A-Za-z0-9]{30,})'
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in scripts/check_repo_policy.sh|tests/test_repo_policy.sh) continue ;; esac
  if grep -qIE -- "$secret_re" "$f"; then report 'secret-like content' "$f"; fi
done

# 6. Device evidence. Two locations, both scanned for identifiers:
#    reports/evidence-draft/  must declare "REDACTION-STATUS: PENDING-HUMAN-APPROVAL";
#    reports/evidence/        must carry "REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>".
#    The scan is a safety net and does not replace human redaction.
private_ip_re='(^|[^0-9.])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168|169\.254|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'
for f in "${files[@]}"; do
  case "$f" in reports/evidence/*|reports/evidence-draft/*) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  case "$f" in
    reports/evidence/*)
      head -n 5 "$f" | grep -qE '^REDACTED-BY-HUMAN: [A-Za-z]{2,4} [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' \
        || report 'evidence missing "REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>" header' "$f" ;;
    reports/evidence-draft/*)
      head -n 5 "$f" | grep -q 'REDACTION-STATUS: PENDING-HUMAN-APPROVAL' \
        || report 'draft evidence missing "REDACTION-STATUS: PENDING-HUMAN-APPROVAL" header' "$f" ;;
  esac
  grep -qE "$private_ip_re" "$f" && report 'private/VPN IPv4 address in evidence' "$f"
  grep -qiE '\.ts\.net\b|\bfd7a:115c|\b(fd|fe80)[0-9a-f]{0,2}::?[0-9a-f]{1,4}:' "$f" && report 'VPN hostname or private IPv6 in evidence' "$f"
  grep -qiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' "$f" && report 'MAC address in evidence' "$f"
  grep -qE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" && report 'email address in evidence' "$f"
  grep -qE '/(home|Users)/[^[:space:]/]+' "$f" && report 'home-directory path in evidence' "$f"
  grep -qE '(^|[[:space:]])/dev/[a-z]' "$f" && report 'block-device path in evidence' "$f"
  grep -qE 'ssh-(ed25519|rsa)|ecdsa-sha2-|SHA256:[A-Za-z0-9+/]{43}' "$f" && report 'SSH key or fingerprint in evidence' "$f"
done

# 7. Required governance files.
for f in CLAUDE.md docs/DEVELOPMENT_PLAN_v1.2.md docs/DATA_GOVERNANCE.md .gitignore; do
  [ -f "$f" ] || report 'missing required file' "$f"
done

if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: repository policy (%d tracked files)\n' "${#files[@]}"
