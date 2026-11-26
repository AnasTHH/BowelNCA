#!/usr/bin/env bash
# REGRESSION TEST for scripts/jetson_inventory.sh.
#
# Scope and limits: this is a lint-style regression check that catches
# accidental introduction of known-dangerous commands. It is NOT a security
# sandbox, NOT a proof or guarantee of read-only execution, and cannot detect
# obfuscated, indirect or newly invented mutations (e.g. commands assembled
# from variables, or side effects inside python3/torch). Human review of the
# script before running it on the Xavier remains mandatory, and real
# protection comes from OS accounts and permissions (CLAUDE.md).
#
#  1. Static check: deny-list of privileged, mutating, installing, network and
#     identity-revealing commands.
#  2. Dynamic check: runs on a non-Jetson host (e.g. CI) with HOME and the
#     working directory set to an empty sandbox, must exit 0, leave the sandbox
#     unchanged, emit every section and the read-only footer, and
#     must not print this machine's hostname or username.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${INVENTORY_SCRIPT:-$repo_root/scripts/jetson_inventory.sh}"
fail=0

# --- 1. static deny-list ----------------------------------------------------
# Comments and plain message lines (printf with a single literal argument)
# are stripped first; they cannot execute anything.
code="$(sed -e 's/[[:space:]]#.*$//' -e '/^[[:space:]]*#/d' "$script" \
        | grep -vE "^[[:space:]]*printf '[^']*'[[:space:]]*$" || true)"
deny_patterns=(
  '\bsudo\b' '\bsu\b ' '\bdoas\b' '\bpkexec\b'
  'apt(-get)?[[:space:]]+(install|remove|purge|upgrade|update|dist-upgrade)'
  '\bdpkg[[:space:]]+-(i|r|P|-install|-remove|-purge)'
  'pip3?[[:space:]]+install' '-m[[:space:]]+pip[[:space:]]+install' '\bconda[[:space:]]+install'
  'nvpmodel[[:space:]]+-m' 'nvpmodel[[:space:]]+-d' 'jetson_clocks[[:space:]]*($|[;&|-])'
  '\bsystemctl\b' '\bservice[[:space:]]' '\breboot\b' '\bshutdown\b' '\bmodprobe\b' '\bsysctl[[:space:]]+-w'
  '\bcurl\b' '\bwget\b' '\bssh\b' '\bscp\b' '\brsync\b' '\bgit[[:space:]]+(clone|pull|push|fetch)'
  '\brm[[:space:]]' '\bmv[[:space:]]' '\bdd[[:space:]]' '\bmkfs' '\bchmod\b' '\bchown\b' '\btee\b'
  '>[[:space:]]*/(etc|sys|proc|usr|var|boot)' '>[[:space:]]*/dev/[^n]' '\bhostname\b' '\bwhoami\b' '\bip[[:space:]]+(a|addr)' '\bifconfig\b'
  '\blsblk\b' '\bblkid\b' '\bswapon[[:space:]]+--show[[:space:]]*($|[^=])' 'pip[[:space:]]+--version' '\bdf[[:space:]]+-h[[:space:]]+/' 'serial-number'
  '^[[:space:]]*\.[[:space:]]+/etc/os-release' '\bsource[[:space:]]'
)
for pattern in "${deny_patterns[@]}"; do
  if grep -nE -- "$pattern" <<<"$code" >/dev/null; then
    printf 'FAIL static: forbidden pattern %s\n' "$pattern"
    grep -nE -- "$pattern" <<<"$code" | sed 's/^/    /'
    fail=1
  fi
done
# jetson_clocks / tegrastats / jtop / docker may appear only inside the presence-only loop.
if grep -nE '^[[:space:]]*(jetson_clocks|tegrastats|jtop|docker)\b' <<<"$code" >/dev/null; then
  printf 'FAIL static: telemetry/power tool executed directly\n'; fail=1
fi

# Never execute a script that failed the static check.
if [ "$fail" -ne 0 ]; then
  printf 'Static check failed; refusing to execute the script.\n'
  exit 1
fi

# --- 2. dynamic run in a sandbox --------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
before="$(find "$sandbox" | sort | sha256sum)"
output="$(cd "$sandbox" && HOME="$sandbox" bash "$script" 2>&1)" || { printf 'FAIL dynamic: non-zero exit\n'; fail=1; }
after="$(find "$sandbox" | sort | sha256sum)"
[ "$before" = "$after" ] || { printf 'FAIL dynamic: script created files in working directory\n'; fail=1; }

grep -q 'No sudo or system mutation was attempted' <<<"$output" || { printf 'FAIL dynamic: footer missing\n'; fail=1; }
for section in 'Jetson model' 'L4T / Jetson release' 'Python and machine architecture' 'CUDA compiler' \
               'Memory and swap' 'Storage' 'Current power mode' 'PyTorch/CUDA smoke'; do
  grep -qF "== $section" <<<"$output" || { printf 'FAIL dynamic: section missing: %s\n' "$section"; fail=1; }
done
host="$(uname -n)"
user_name="$(id -un)"
if [ "${#host}" -ge 4 ] && grep -qF -- "$host" <<<"$output"; then printf 'FAIL dynamic: hostname leaked\n'; fail=1; fi
if [ "${#user_name}" -ge 4 ] && [ "$user_name" != "root" ] && grep -qwF -- "$user_name" <<<"$output"; then
  printf 'FAIL dynamic: username leaked\n'; fail=1
fi

# Data-minimization spot checks (not exhaustive; human redaction still required).
if grep -nE '(^|[[:space:]])/dev/[a-z]' <<<"$output" >/dev/null; then printf 'FAIL dynamic: block-device path printed\n'; fail=1; fi
if grep -niE '([0-9a-f]{2}:){5}[0-9a-f]{2}' <<<"$output" >/dev/null; then printf 'FAIL dynamic: MAC-like address printed\n'; fail=1; fi
if grep -nE '/(home|Users)/[^[:space:]/]+' <<<"$output" | grep -vE '[[:space:]]/home$' >/dev/null; then
  printf 'FAIL dynamic: home-directory path printed\n'; fail=1
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'PASS: inventory regression checks (static deny-list + sandboxed run; not a security guarantee)\n'
