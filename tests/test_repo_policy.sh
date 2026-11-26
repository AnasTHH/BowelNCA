#!/usr/bin/env bash
# Regression test for scripts/check_repo_policy.sh using synthetic fixtures in
# a throwaway git repository. No real data is created or read.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check_repo_policy.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

new_fixture_repo() {
  local dir="$1"
  rm -rf "$dir"; mkdir -p "$dir/docs"
  git -C "$dir" init -q
  printf 'x\n' > "$dir/CLAUDE.md"
  printf 'x\n' > "$dir/docs/DEVELOPMENT_PLAN_v1.2.md"
  printf 'x\n' > "$dir/docs/DATA_GOVERNANCE.md"
  printf 'x\n' > "$dir/.gitignore"
}

# Clean baseline must pass.
base="$work/clean"
new_fixture_repo "$base"
mkdir -p "$base/reports/evidence"
printf 'REDACTED-BY-HUMAN: AB 2026-11-25\nL4T R35 (release), REVISION: 6.4\ncuDNN 8.6.0.166 TensorRT 8.5.2.2\nfree: 15Gi\n' > "$base/reports/evidence/stage0_inventory_redacted.txt"
mkdir -p "$base/reports/evidence-draft"
printf 'REDACTION-STATUS: PENDING-HUMAN-APPROVAL\nCUDA 11.4.19-1, mount /data\n' > "$base/reports/evidence-draft/draft.md"
git -C "$base" add -A
if ! bash "$checker" "$base" >/dev/null; then printf 'FAIL: clean fixture rejected\n'; bash "$checker" "$base" || true; fail=1; fi

# Each case: "<path>|<content>" must be rejected.
cases=(
  'data/raw_dev/case01.txt|x'
  'src/pkg/data/derived/a.txt|x'
  'nested/locked_test/ids.txt|x'
  'second_labels/a.txt|x'
  'checkpoints/a.txt|x'
  'outputs/run1/metrics.txt|x'
  'logs/run.txt|x'
  'third_party/OctreeNCA/model.py|x'
  'scan.nii.gz|x'
  'model.pth|x'
  'cache.pkl|x'
  'slide.tiff|x'
  'run.log|x'
  'train.out|x'
  'events.out.tfevents.1|x'
  'stage0_inventory_local.txt|x'
  '.env|x'
  'reports/overlay_case3.png|x'
  'notes.md|-----BEGIN OPENSSH PRIVATE KEY-----'
  'reports/evidence/no_header.txt|L4T R35'
  'reports/evidence/ip.txt|REDACTED-BY-HUMAN: AB 2026-11-25\nlisten 192.168.1.20'
  'reports/evidence/vpn.txt|REDACTED-BY-HUMAN: AB 2026-11-25\npeer 100.101.102.103'
  'reports/evidence/tsnet.txt|REDACTED-BY-HUMAN: AB 2026-11-25\nhost dev.tail1234.ts.net'
  'reports/evidence/key.txt|REDACTED-BY-HUMAN: AB 2026-11-25\nssh-ed25519 AAAAC3Nza'
  'reports/evidence/badheader.txt|REDACTED-BY-HUMAN: PENDING\nL4T R35'
  'reports/evidence-draft/noheader.md|L4T R35'
  'reports/evidence-draft/ip.md|REDACTION-STATUS: PENDING-HUMAN-APPROVAL\nlisten 10.0.0.5'
  'reports/evidence/home.txt|REDACTED-BY-HUMAN: AB 2026-11-25\n/home/devuser/venv'
  'reports/evidence/dev.txt|REDACTED-BY-HUMAN: AB 2026-11-25\n/dev/mmcblk0p1 28G'
  'reports/evidence/mac.txt|REDACTED-BY-HUMAN: AB 2026-11-25\nether 00:1b:44:11:3a:b7'
)
for entry in "${cases[@]}"; do
  path="${entry%%|*}"
  content="${entry#*|}"
  dir="$work/case"
  new_fixture_repo "$dir"
  mkdir -p "$dir/$(dirname "$path")"
  printf '%b\n' "$content" > "$dir/$path"
  git -C "$dir" add -A -f
  if bash "$checker" "$dir" >/dev/null 2>&1; then
    printf 'FAIL: policy accepted %s\n' "$path"; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: repository policy rejects all %d synthetic violations and accepts a clean tree\n' "${#cases[@]}"
