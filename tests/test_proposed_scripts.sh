#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034  # sourcing the installer under test by path
# Regression tests for scripts/proposed/install_xavier_env.sh and
# scripts/verify_workspace.sh. Synthetic, CPU-only, no network: tool stubs on
# PATH record any attempt to download or install. Not a security guarantee.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/scripts/proposed/install_xavier_env.sh"
verifier="$repo_root/scripts/verify_workspace.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

# Stubs: any call leaves a marker.
stubs="$work/stubs"; markers="$work/markers"
mkdir -p "$stubs" "$markers"
for tool in curl wget pip pip3 sudo apt apt-get dpkg; do
  printf '#!/bin/sh\ntouch "%s/%s"\nexit 0\n' "$markers" "$tool" > "$stubs/$tool"
  chmod +x "$stubs/$tool"
done
no_markers() { [ -z "$(ls -A "$markers")" ]; }

# --- installer: static properties -------------------------------------------
code="$(sed -e 's/[[:space:]]#.*$//' -e '/^[[:space:]]*#/d' "$installer")"
grep -qE '\bsudo\b|apt-get[[:space:]]+install|apt[[:space:]]+install' <<<"$(grep -vE "abort \"|log \"" <<<"$code")" \
  && bad "installer invokes sudo/apt outside messages" || ok "installer has no sudo/apt invocation"
grep -q 'set -euo pipefail' "$installer" && ok "installer uses set -euo pipefail" || bad "missing set -euo pipefail"
grep -q 'sha256sum --check --strict' "$installer" && ok "strict checksum verification present" || bad "no strict checksum check"
n_pip=$(grep -cE 'pip install' <<<"$code" || true)
n_hash=$(grep -cE 'pip install --require-hashes --no-deps --only-binary=:all:' <<<"$code" || true)
[ "$n_pip" -ge 1 ] && [ "$n_pip" = "$n_hash" ] && ok "every pip install is hash-locked, no-deps, binary-only" \
  || bad "a pip install lacks --require-hashes/--no-deps/--only-binary ($n_hash of $n_pip)"
grep -qE 'nvpmodel|jetson_clocks|systemctl|chown|chmod' <<<"$code" && bad "installer touches power/system/permissions" \
  || ok "installer does not touch power, services or permissions"

# --- installer: refuses without approval, before any action ------------------
rm -f "$markers"/*
if out="$(PATH="$stubs:$PATH" BOWELNCA_ROOT="$work/ws" bash "$installer" 2>&1)"; then
  bad "installer ran without approval"
else
  grep -q 'NOT APPROVED' <<<"$out" && ok "installer refuses without approval" || bad "unexpected refusal message: $out"
fi
no_markers && ok "no download/install attempted without approval" || bad "tools invoked without approval: $(ls "$markers")"

# Malformed approval token is rejected.
rm -f "$markers"/*
if PATH="$stubs:$PATH" BOWELNCA_INSTALL_APPROVAL="yes" BOWELNCA_ROOT="$work/ws" bash "$installer" >/dev/null 2>&1; then
  bad "malformed approval accepted"
else ok "malformed approval rejected"; fi
no_markers || bad "tools invoked with malformed approval"

# Valid-format approval on a non-Jetson host aborts at preconditions, before any download.
rm -f "$markers"/*
if out="$(PATH="$stubs:$PATH" BOWELNCA_INSTALL_APPROVAL="D99-2026-11-26-XX" BOWELNCA_ROOT="$work/ws" bash "$installer" 2>&1)"; then
  bad "installer proceeded on a non-Jetson host"
else
  grep -q 'ABORT' <<<"$out" && ok "preconditions abort on a non-Jetson host" || bad "unexpected output: $out"
fi
no_markers && ok "no download/install attempted when preconditions fail" || bad "tools invoked despite failed preconditions: $(ls "$markers")"

# --check-only also stops at preconditions here and never downloads.
rm -f "$markers"/*
PATH="$stubs:$PATH" BOWELNCA_ROOT="$work/ws" bash "$installer" --check-only >/dev/null 2>&1 || true
no_markers && ok "--check-only never downloads or installs" || bad "--check-only invoked tools"

# Checksum function: mismatch aborts and deletes the file; match passes.
f="$work/fake.whl"; printf 'not a wheel\n' > "$f"
good="$(sha256sum "$f" | cut -d' ' -f1)"
if ( BOWELNCA_SOURCE_ONLY=1; . "$installer"; verify_sha256 "$f" "$good" ) >/dev/null 2>&1; then ok "matching checksum accepted"
else bad "matching checksum rejected"; fi
if ( BOWELNCA_SOURCE_ONLY=1; . "$installer"; verify_sha256 "$f" "0000000000000000000000000000000000000000000000000000000000000000" ) >/dev/null 2>&1; then
  bad "checksum mismatch accepted"
else
  [ ! -e "$f" ] && ok "checksum mismatch aborts and deletes the file" || bad "mismatched file not deleted"
fi

# Lock consistency: installer's pinned torch hash appears in the core lock.
pinned="$(sed -n 's/^readonly TORCH_SHA256="\([0-9a-f]\{64\}\)"$/\1/p' "$installer")"
grep -q "sha256:$pinned" "$repo_root/env/xavier/requirements-xavier-core.lock" && ok "installer torch hash matches core lock" \
  || bad "installer torch hash not in core lock"
grep -q "sha256:$pinned" "$repo_root/env/xavier/requirements-xavier-sci.lock" && ok "installer torch hash matches sci lock" \
  || bad "installer torch hash not in sci lock"
for lock in "$repo_root"/env/xavier/*.lock; do
  # Every requirement line must carry at least one hash.
  python3 - "$lock" <<'PY' && ok "all entries hashed: $(basename "$lock")" || bad "unhashed entry in $(basename "$lock")"
import re, sys
text = open(sys.argv[1]).read()
blocks = re.split(r'\n(?=[A-Za-z0-9])', text)
reqs = [b for b in blocks if not b.startswith('--') and re.match(r'[A-Za-z0-9]', b)]
sys.exit(0 if reqs and all('--hash=sha256:' in b for b in reqs) else 1)
PY
done

# --- workspace verifier ------------------------------------------------------
ws="$work/ws"
mkdir -p "$ws"
for d in workspace venvs datasets derived checkpoints experiments reports cache tmp; do mkdir -p "$ws/$d"; done
chmod 700 "$ws"
mnt="$(findmnt -no TARGET -T "$ws")"
before="$(find "$ws" | sort | sha256sum)"
out="$(BOWELNCA_ROOT="$ws" BOWELNCA_EXPECTED_MOUNT="$mnt" bash "$verifier" --write-test 2>&1)" || true
fails_seen="$(grep '^FAIL' <<<"$out" || true)"
if [ "$(id -u)" -eq 0 ]; then
  # Local sandboxes may run as root; the verifier must flag exactly that and nothing else.
  [ "$fails_seen" = "FAIL  running as root (not required)" ] && ok "verifier passes a correct workspace (root flagged as expected)" \
    || bad "verifier failures on a correct workspace: $fails_seen"
else
  [ -z "$fails_seen" ] && ok "verifier passes on a correct synthetic workspace" || bad "verifier failures on a correct workspace: $fails_seen"
fi
after="$(find "$ws" | sort | sha256sum)"
[ "$before" = "$after" ] && ok "write test leaves no files behind" || bad "write test left files behind"
grep -q 'write test: 1 MiB written, verified and removed' <<<"$out" && ok "write test executed" || bad "write test did not run"
host="$(uname -n)"; user_name="$(id -un)"
if [ "${#host}" -ge 4 ] && grep -qF -- "$host" <<<"$out"; then bad "verifier printed hostname"; else ok "verifier prints no hostname"; fi
if [ "$user_name" != "root" ] && [ "${#user_name}" -ge 4 ] && grep -qwF -- "$user_name" <<<"$out"; then bad "verifier printed username"; else ok "verifier prints no username"; fi

chmod 755 "$ws"
if BOWELNCA_ROOT="$ws" BOWELNCA_EXPECTED_MOUNT="$mnt" bash "$verifier" >/dev/null 2>&1; then bad "verifier accepted mode 755"
else ok "verifier rejects a group/world-readable workspace"; fi
chmod 700 "$ws"; rmdir "$ws/derived"
if BOWELNCA_ROOT="$ws" BOWELNCA_EXPECTED_MOUNT="$mnt" bash "$verifier" >/dev/null 2>&1; then bad "verifier accepted a missing subdir"
else ok "verifier rejects a missing subdirectory"; fi
vcode="$(sed -e 's/[[:space:]]#.*$//' -e '/^[[:space:]]*#/d' "$verifier")"
grep -qE '(^|[;&|(]|then|do)[[:space:]]*sudo\b|\bchown\b|\bchmod\b|\bsetfacl\b|\bhostname\b|\bwhoami\b' <<<"$vcode" && bad "verifier contains a privileged/identity command" \
  || ok "verifier has no sudo/chown/chmod/hostname calls"

if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: proposed installer fails closed; workspace verifier behaves (regression checks, not guarantees)\n'
