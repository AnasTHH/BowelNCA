#!/usr/bin/env bash
# Repository policy check for a PUBLIC research repository.
#
# Validates the exact content Git would publish, read from Git objects, never
# from the working tree:
#   --index        the staged index (default; used by the pre-commit hook)
#   --tree REV     the tree of commit REV (used by pre-push for every new
#                  commit, and by CI)
#
# Fails on: restricted data/steward/test directories at any depth; medical
# images, model weights, run artefacts, archives, logs and raw console output;
# secret-like content; oversized files; device evidence without a redaction
# attestation or containing identifiers; paths or file types outside the
# publication allowlist; symlinks, submodules and unusual file names; binary
# or control-character content in text files and images whose content does
# not match their extension or that lack a recorded human approval; private
# AI-assistant links and session trailers; and private identifiers from a
# local pattern file kept OUTSIDE the repository.
#
# Output names the rule and a safe reference only. A path is printed only if
# it uses plain characters and matches no private pattern; otherwise it is
# withheld and the Git object is named instead. Matched text is never printed.
#
# Exit status: 0 pass, 1 policy findings, 3 internal error (a Git command,
# object read, pattern file or scanner failed). Any non-zero status blocks.
#
# Usage: scripts/check_repo_policy.sh [--index | --tree REV] [repo_root]
# Private patterns: see scripts/lib/publication_checks.sh and SECURITY.md.
# This is a safety net for mistakes, not an access control.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/publication_checks.sh
. "$script_dir/lib/publication_checks.sh"

mode=index rev=''
case "${1:-}" in
  --index) shift ;;
  --tree)  [ -n "${2:-}" ] || { echo "usage: $0 [--index | --tree REV] [repo_root]" >&2; exit 2; }
           mode=tree; rev="$2"; shift 2 ;;
esac
root="${1:-$(git rev-parse --show-toplevel)}" || pc_die 'not inside a Git repository'
cd "$root" || pc_die 'cannot enter the repository root'
git rev-parse --git-dir >/dev/null 2>&1 || pc_die 'not a Git repository'

fail=0
max_bytes=$((2 * 1024 * 1024))
tmp="$(mktemp -d)" || pc_die 'mktemp failed'
trap 'rm -rf "$tmp"' EXIT
report() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }

pattern_rc=0
pc_load_patterns "$root" || pattern_rc=1
[ "$pattern_rc" -eq 0 ] || fail=1

# --- Enumerate entries from Git objects; any Git failure is fatal. ----------
entries="$tmp/entries"
if [ "$mode" = index ]; then
  git ls-files --stage -z > "$entries" || pc_die 'git ls-files failed'
  where='staged'
else
  commit="$(git rev-parse --verify --quiet "${rev}^{commit}")" || pc_die 'revision is not a commit'
  git ls-tree -r -z --full-tree "$commit" > "$entries" || pc_die 'git ls-tree failed'
  where="commit ${commit:0:12}"
fi

# Path rules.
restricted_dirs='data|raw_data|raw_dev|derived|private_data_steward|source_archive|canonical_and_duplicates|locked_test|test_data|approved_dev_transfer|second_labels|alternate_labels|artifacts|artefacts|checkpoints|weights|runs|outputs|logs|wandb|mlruns|aim|\.aim|lightning_logs|nnUNet_raw|nnUNet_preprocessed|nnUNet_results|third_party|upstream|OctreeNCA|\.ssh'
forbidden_ext='\.(nii|nii\.gz|mha|mhd|nrrd|dcm|dicom|ima|img|hdr|mgz|tif|tiff|svs|npy|npz|h5|hdf5|mat|pkl|pickle|joblib|pt|pth|ckpt|safetensors|onnx|engine|trt|plan|tflite|bin|whl|zip|tar|gz|tgz|bz2|xz|7z|rar|pem|key|p12|pfx|ppk|kdbx|keystore|jks)$'
forbidden_log='(\.log|\.out|\.err|\.stdout|\.stderr|\.tfevents\..*|events\.out\..*|nohup\.out)$'
forbidden_name='(^|/)(\.env(\..*)?|\.netrc|\.pgpass|id_(rsa|ed25519|ecdsa|dsa)(\.pub)?|known_hosts|authorized_keys|credentials(\.json)?|service[-_]account.*\.json|.*_inventory_local\..*|splits_private.*|test_ids.*|.*\.sha256\.private)$'
# Publication allowlist: every published file must be in an approved path
# with an approved type. Adding a path or type is a reviewed change here.
allow_re='^(CLAUDE\.md|README\.md|LICENSE(\.md)?|SECURITY\.md|\.gitignore|\.gitleaks\.toml|pyproject\.toml'
allow_re+='|\.github/workflows/[A-Za-z0-9._-]+\.ya?ml'
allow_re+='|docs/([A-Za-z0-9._/-]+)\.md|docs/(figures|img)/[A-Za-z0-9._/-]+\.(png|jpe?g|svg)'
allow_re+='|reports/[A-Za-z0-9._-]+\.md|reports/evidence/[A-Za-z0-9._-]+\.(md|txt)'
allow_re+='|scripts/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.(sh|py)|scripts/hooks/(pre-commit|pre-push|commit-msg)'
allow_re+='|src/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.py'
allow_re+='|tests/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.(sh|py)'
allow_re+='|env/xavier/[A-Za-z0-9._-]+\.(in|lock|json|py)'
# D19 P1 (D19-R02): CPU dev dependency lock and the synthetic golden digests.
allow_re+='|env/dev/requirements-dev\.(in|lock)'
allow_re+='|tests/python/golden/p1_digests\.json)$'
safe_name_re='^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'
# Images need a human publication approval recorded in this file, keyed by
# the SHA-256 of the exact image content:
#   <sha256>  <path>  APPROVED-BY-HUMAN: <initials> <YYYY-MM-DD>
approvals_path='docs/figures/PUBLICATION_APPROVALS.md'
# Evidence identifier rules.
private_ip_re='(^|[^0-9.])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168|169\.254|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'
ctrl_chars=$'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'

# Parse entries into parallel arrays (NUL-delimited; names with newlines or
# other unusual characters are handled, then rejected).
paths=() oids=() modes=() n_entries=0
while IFS= read -r -d '' rec; do
  meta="${rec%%$'\t'*}"; path="${rec#*$'\t'}"
  read -r f1 f2 f3 <<<"$meta"
  if [ "$mode" = index ]; then   # "<mode> <oid> <stage>"
    m="$f1" oid="$f2"
    [ "$f3" = 0 ] || { report 'unmerged index entry' "object ${oid:0:12}"; continue; }
  else                           # "<mode> <type> <oid>"
    m="$f1" oid="$f3"
  fi
  paths+=("$path"); oids+=("$oid"); modes+=("$m"); n_entries=$((n_entries + 1))
done < "$entries"

# label PATH OID: a safe reference for output.
label() {
  local hits
  if [[ "$1" =~ $safe_name_re ]]; then
    hits="$(pc_private_hits_str "$1")" || pc_die 'private pattern scan failed'
    if [ -z "$hits" ]; then printf '%s' "$1"; return; fi
  fi
  printf '<path withheld> (%s, object %s)' "$where" "${2:0:12}"
}

# read_blob OID FILE: exact object content, or a fatal error.
read_blob() { git cat-file blob "$1" > "$2" 2>/dev/null || pc_die "git object read failed (object ${1:0:12})"; }

# Load image approvals from the same source being checked.
approvals="$tmp/approvals"; : > "$approvals"
for i in "${!paths[@]}"; do
  if [ "${paths[$i]}" = "$approvals_path" ] && [ "${modes[$i]}" = 100644 ]; then read_blob "${oids[$i]}" "$approvals"; fi
done

blob="$tmp/blob"
for i in "${!paths[@]}"; do
  f="${paths[$i]}" oid="${oids[$i]}" m="${modes[$i]}"
  lbl="$(label "$f" "$oid")" || pc_die 'label failed'

  # Object types: only regular files are publishable.
  case "$m" in
    100644|100755) ;;
    120000) report 'symbolic link (not publishable)' "$lbl"; continue ;;
    160000) report 'submodule (not publishable)' "$lbl"; continue ;;
    *)      report "unsupported object mode $m" "$lbl"; continue ;;
  esac

  # Path rules.
  [[ "$f" =~ $safe_name_re ]] || report 'unusual file name (only A-Z a-z 0-9 . _ - and /)' "$lbl"
  pc_grep -qE "(^|/)(${restricted_dirs})/" <<<"$f" && report 'restricted directory' "$lbl"
  pc_grep -qiE "$forbidden_ext" <<<"$f" && report 'forbidden file type' "$lbl"
  pc_grep -qiE "$forbidden_log" <<<"$f" && report 'log/raw output file' "$lbl"
  pc_grep -qiE "$forbidden_name" <<<"$f" && report 'forbidden file name' "$lbl"
  case "$f" in
    *evidence-draft/*|*evidence_draft/*|*evidence-drafts/*)
      report 'unapproved evidence draft in public repository (keep drafts in private storage)' "$lbl" ;;
  esac
  pc_grep -qE "$allow_re" <<<"$f" || report 'path or file type not on the publication allowlist' "$lbl"
  hits="$(pc_private_hits_str "$f")" || pc_die 'private pattern scan failed'
  for h in $hits; do report "private identifier in file name (pattern #$h)" "$lbl"; done

  size="$(git cat-file -s "$oid" 2>/dev/null)" || pc_die "git object read failed (object ${oid:0:12})"
  if [ "$size" -gt "$max_bytes" ]; then report 'file over 2 MiB' "$lbl ($size bytes)"; continue; fi
  read_blob "$oid" "$blob"

  # Content type: images must really be images and carry a human approval;
  # everything else must be UTF-8 text without NUL or control characters.
  is_image=0
  case "$f" in *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.gif|*.GIF|*.svg|*.SVG) is_image=1 ;; esac
  if [ "$is_image" = 1 ]; then
    case "$f" in docs/figures/*|docs/img/*) ;; *) report 'image outside docs/figures (possible patient overlay)' "$lbl" ;; esac
    magic="$(head -c 8 "$blob" | od -An -tx1 | tr -d ' \n')" || pc_die 'cannot read image header'
    case "$f" in
      *.png|*.PNG) [ "$magic" = 89504e470d0a1a0a ] || report 'content does not match the .png extension' "$lbl" ;;
      *.jpg|*.JPG|*.jpeg|*.JPEG) [ "${magic:0:6}" = ffd8ff ] || report 'content does not match the .jpg extension' "$lbl" ;;
      *.svg|*.SVG)
        iconv -f UTF-8 -t UTF-8 "$blob" >/dev/null 2>&1 && pc_grep -qa '<svg' "$blob" \
          || report 'content does not match the .svg extension' "$lbl"
        pc_grep -qaiE '<script|javascript:|on[a-z]+=' "$blob" && report 'active content in SVG' "$lbl" ;;
    esac
    sum="$(sha256sum "$blob" 2>/dev/null || shasum -a 256 "$blob")" || pc_die 'SHA-256 failed'; sum="${sum%% *}"
    pc_grep -qE "^${sum}[[:space:]]+[^[:space:]]+[[:space:]]+APPROVED-BY-HUMAN: [A-Za-z]{2,4} [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$" "$approvals" \
      || report "image without a recorded human publication approval in $approvals_path" "$lbl"
  else
    if [ "$(tr -d '\000' < "$blob" | wc -c)" -ne "$size" ]; then
      report 'binary content (NUL bytes) in a text file type' "$lbl"
    elif ! iconv -f UTF-8 -t UTF-8 "$blob" >/dev/null 2>&1; then
      report 'content is not valid UTF-8 text' "$lbl"
    fi
    LC_ALL=C pc_grep -qa "$ctrl_chars" "$blob" && report 'control characters (binary or raw terminal output)' "$lbl"
  fi

  # Content rules (-a: binary content is scanned too, never skipped).
  case "$f" in
    tests/test_repo_policy.sh) ;;   # contains synthetic secret-like fixtures
    *) pc_grep -qaE -- "$PC_SECRET_RE" "$blob" && report 'secret-like content' "$lbl" ;;
  esac
  head -n 5 "$blob" > "$tmp/head" || pc_die 'cannot read file header'
  pc_grep -qa 'REDACTION-STATUS: PENDING-HUMAN-APPROVAL' "$tmp/head" \
    && report 'file marked PENDING-HUMAN-APPROVAL must not be committed' "$lbl"
  pc_grep -qaE -- "$PC_AI_LINK_RE" "$blob" && report 'private AI-assistant link or session trailer' "$lbl"
  hits="$(pc_private_hits "$blob")" || pc_die 'private pattern scan failed'
  for h in $hits; do report "private identifier (pattern #$h)" "$lbl"; done

  # Golden digests: strict JSON structure (SEC-08), see
  # scripts/lib/validate_golden_digests.py. The "synthetic" marker is a
  # declaration, not proof of provenance; P1 regenerates digests independently.
  if [ "$f" = tests/python/golden/p1_digests.json ]; then
    command -v python3 >/dev/null 2>&1 || pc_die 'python3 is required to validate the golden digest file'
    rc=0; why="$(python3 -I "$script_dir/lib/validate_golden_digests.py" "$blob" 2>/dev/null)" || rc=$?
    case "$rc" in
      0) ;;
      1) report "golden digest file invalid (${why:-unspecified})" "$lbl" ;;
      *) pc_die 'golden digest validator failed' ;;
    esac
  fi

  # Device evidence: only human-approved evidence in reports/evidence/, with
  # "REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>"; identifier scan as a net.
  case "$f" in
    reports/evidence/*)
      pc_grep -qE '^REDACTED-BY-HUMAN: [A-Za-z]{2,4} [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' "$tmp/head" \
        || report 'evidence missing "REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>" header' "$lbl"
      pc_grep -qaE "$private_ip_re" "$blob" && report 'private/VPN IPv4 address in evidence' "$lbl"
      pc_grep -qaiE '\.ts\.net\b|\bfd7a:115c|\b(fd|fe80)[0-9a-f]{0,2}::?[0-9a-f]{1,4}:' "$blob" && report 'VPN hostname or private IPv6 in evidence' "$lbl"
      pc_grep -qaiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' "$blob" && report 'MAC address in evidence' "$lbl"
      pc_grep -qaE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$blob" && report 'email address in evidence' "$lbl"
      pc_grep -qaE '/(home|Users)/[^[:space:]/]+' "$blob" && report 'home-directory path in evidence' "$lbl"
      pc_grep -qaE '(^|[[:space:]])/dev/[a-z]' "$blob" && report 'block-device path in evidence' "$lbl"
      pc_grep -qaE 'ssh-(ed25519|rsa)|ecdsa-sha2-|SHA256:[A-Za-z0-9+/]{43}' "$blob" && report 'SSH key or fingerprint in evidence' "$lbl"
      ;;
  esac
done

# Required governance files, in the content being checked.
for req in CLAUDE.md docs/DEVELOPMENT_PLAN_v1.2.md docs/DATA_GOVERNANCE.md .gitignore; do
  found=0
  for i in "${!paths[@]}"; do [ "${paths[$i]}" = "$req" ] && { found=1; break; }; done
  [ "$found" = 1 ] || report 'missing required file' "$req"
done

[ "$PC_PATTERNS_STATUS" = loaded ] && printf 'INFO: %d private identifier patterns checked\n' "${#PC_PATTERNS[@]}"
if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: repository policy (%s, %d files)\n' "$where" "$n_entries"
