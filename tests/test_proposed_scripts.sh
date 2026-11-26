#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034,SC2317  # sourcing scripts under test; overrides are called indirectly
# Regression tests for scripts/proposed/install_xavier_env.sh,
# scripts/verify_workspace.sh and scripts/lib/workspace_checks.sh.
#
# Synthetic, CPU-only, no network. External tools (curl, python3, nvcc,
# ldconfig, uname, the venv's python/pip) are stubs on PATH or in a temp tree;
# identities, mounts and ownership are substituted by overriding the ws_*
# query functions after sourcing. These tests check control flow and
# fail-closed behaviour. They are NOT a security guarantee and do not prove
# the real system calls behave as on the Xavier.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/scripts/proposed/install_xavier_env.sh"
verifier="$repo_root/scripts/verify_workspace.sh"
work="$(mktemp -d)"
trap 'jobs -p | xargs -r kill 2>/dev/null; rm -rf "$work"' EXIT
# Results go to files so checks inside subshells are counted.
ok()  { printf 'ok    %s\n' "$1"; echo x >> "$work/ok"; }
bad() { printf 'FAIL  %s\n' "$1"; echo x >> "$work/failed"; }

real_uname="$(command -v uname)"
stubs="$work/stubs"; markers="$work/markers"; state="$work/state"
mkdir -p "$stubs" "$markers" "$state"
no_markers() { [ -z "$(ls -A "$markers")" ]; }
reset_state() { rm -rf "${markers:?}"/* "${state:?}"/*; }

# --- stubs ----------------------------------------------------------------------
for tool in wget pip pip3 sudo apt apt-get dpkg nvpmodel jetson_clocks; do
  printf '#!/bin/sh\ntouch "%s/%s"\nexit 0\n' "$markers" "$tool" > "$stubs/$tool"
done
cat > "$stubs/curl" <<EOF
#!/bin/sh
touch "$markers/curl"
out=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
[ -n "\$out" ] || exit 2
if [ -f "$state/tamper" ]; then printf 'tampered wheel\n' > "\$out"; else printf 'fake wheel\n' > "\$out"; fi
EOF
cat > "$stubs/uname" <<EOF
#!/bin/sh
[ "\$1" = "-m" ] && { echo aarch64; exit 0; }
exec "$real_uname" "\$@"
EOF
# Large ldconfig output: the match is first, so a 'grep -q' pipe would SIGPIPE.
cat > "$stubs/ldconfig" <<EOF
#!/bin/sh
[ -f "$state/no_openblas" ] || echo '	libopenblas.so.0 (libc6,AArch64) => /usr/lib/aarch64-linux-gnu/libopenblas.so.0'
i=0; while [ \$i -lt 20000 ]; do echo "	libfake\$i.so (libc6,AArch64) => /usr/lib/libfake\$i.so"; i=\$((i+1)); done
EOF
real_sha="$(command -v sha256sum)"; real_date="$(command -v date)"
cat > "$stubs/sha256sum" <<EOF
#!/bin/sh
if [ -f "$state/fail_locksum" ]; then case "\$*" in *requirements-xavier*) exit 1 ;; esac; fi
exec "$real_sha" "\$@"
EOF
cat > "$stubs/date" <<EOF
#!/bin/sh
[ "\$*" = "-u +%Y%m%dT%H%M%SZ" ] && { echo 20261201T000000Z; exit 0; }
exec "$real_date" "\$@"
EOF
chmod +x "$stubs"/*

fake_cuda="$work/cuda"; mkdir -p "$fake_cuda/bin" "$fake_cuda/lib64"
printf '#!/bin/sh\necho "Cuda compilation tools, release 11.4, V11.4.315"\n' > "$fake_cuda/bin/nvcc"
chmod +x "$fake_cuda/bin/nvcc"
tegra="$work/nv_tegra_release"
printf '# R35 (release), REVISION: 6.4, GCID: 0, BOARD: t186ref, EABI: aarch64\n' > "$tegra"

# Venv python stub: pip installs are logged; the Nth install fails if
# $state/fail_pip_at contains N; the smoke test writes a JSON result and
# records the environment it ran in.
venv_py="$work/venv_python"
cat > "$venv_py" <<EOF
#!/bin/sh
[ "\$1" = "-I" ] && shift
if [ "\$1" = "-m" ] && [ "\$2" = "pip" ]; then
  case "\$3" in
    install)
      env | grep -E '^(PYTHON|PIP_|HOME=|PATH=)' | sort >> "$state/pip_env"
      prev=""; for a in "\$@"; do [ "\$prev" = "--log" ] && echo "pip log" >> "\$a"; prev="\$a"; done
      n=\$(( \$(cat "$state/pipcount" 2>/dev/null || echo 0) + 1 )); echo \$n > "$state/pipcount"
      prev=""; for a in "\$@"; do
        [ "\$prev" = "-r" ] && echo "install\$n \$(grep -E '^[A-Za-z]' "\$a" | head -n 1 | cut -c1-60)" >> "$state/pip.log"
        prev="\$a"; done
      echo "\$*" | grep -q -- '--require-hashes --no-deps --only-binary=:all:' || echo "UNLOCKED \$*" >> "$state/pip.log"
      [ "\$(cat "$state/fail_pip_at" 2>/dev/null)" = "\$n" ] && exit 1
      mkdir -p "\$(dirname "\$0")/../lib/fake-site" && echo \$n > "\$(dirname "\$0")/../lib/fake-site/pkg\$n"
      exit 0 ;;
    check) echo check >> "$state/pip.log"; exit 0 ;;
    freeze) [ -f "$state/fail_freeze" ] && exit 1; echo "torch==2.1.0a0+41361538.nv23.06"; echo "numpy==1.24.4"; exit 0 ;;
  esac
fi
out=""; stage=""; prev=""
for a in "\$@"; do [ "\$prev" = "--out" ] && out="\$a"; [ "\$prev" = "--stage" ] && stage="\$a"; prev="\$a"; done
env | grep -E '^(CUDA_HOME|TORCH_HOME|MPLCONFIGDIR|XDG_CACHE_HOME|VIRTUAL_ENV|PATH|LD_LIBRARY_PATH|PIP_NO_CACHE_DIR)=' > "$state/smoke_env.\$stage"
if [ -f "$state/smoke_fail" ]; then printf '{"result": "fail", "error": "synthetic"}\n' > "\$out"; exit 1; fi
[ -f "$state/smoke_nojson" ] && exit 0
printf '{"result": "pass", "stage": "%s", "torch_cuda_build": "11.4"}\n' "\$stage" > "\$out"
EOF
fake_py3="$work/python3"
cat > "$fake_py3" <<EOF
#!/bin/sh
[ "\$1" = "-I" ] && shift
[ "\$1" = "-c" ] && exit 0
if [ "\$1" = "-m" ] && [ "\$2" = "venv" ]; then
  env | grep -E '^(PYTHON|PIP_)' | sort > "$state/venv_env"
  mkdir -p "\$3/bin" || exit 1
  if [ -f "$state/activate_dir" ]; then mkdir -p "\$3/bin/activate"; else
  printf 'VIRTUAL_ENV="%s"\nexport VIRTUAL_ENV\nPATH="\$VIRTUAL_ENV/bin:\$PATH"\nexport PATH\n' "\$3" > "\$3/bin/activate"; fi
  cp "$venv_py" "\$3/bin/python"; exit 0
fi
exit 1
EOF
chmod +x "$venv_py" "$fake_py3"

# Fake wheel, locks pinned to its hash, and a clean git checkout.
fake_hash="$(printf 'fake wheel\n' | sha256sum | cut -d' ' -f1)"
real_hash="$(sed -n 's/^TORCH_SHA256="\([0-9a-f]\{64\}\)"$/\1/p' "$installer")"
locks="$work/locks"; mkdir -p "$locks"
for l in "$repo_root"/env/xavier/*.lock; do sed "s/$real_hash/$fake_hash/" "$l" > "$locks/$(basename "$l")"; done
fake_repo="$work/repo"; mkdir -p "$fake_repo"
git -C "$fake_repo" init -q
printf 'x\n' > "$fake_repo/README"
git -C "$fake_repo" add README
git -C "$fake_repo" -c user.name=test -c user.email=test@example.invalid commit -q -m init
reviewed="$(git -C "$fake_repo" rev-parse HEAD)"

data="$work/data"
WS="$data/bowelnca"
make_ws() {  # make_ws LAYOUT
  rm -rf "$data"; mkdir -p "$WS"
  local d; for d in workspace venvs datasets derived checkpoints experiments reports cache tmp; do mkdir -p "$WS/$d"; chmod 700 "$WS/$d"; done
  if [ "$1" = separated ]; then chmod 750 "$WS" "$WS/datasets"; else chmod 700 "$WS"; fi
}
tree_sum() { (cd "$data" && find . -printf '%p %s %m\n' | sort | sha256sum); }

# Synthetic identity: research uid 1000; administrator uid 1001 owns the root and
# datasets in the separated layout; the device owner (uid 0) owns the mount.
fake_system() {  # fake_system LAYOUT (call after sourcing)
  FAKE_LAYOUT="$1"
  ws_current_uid() { echo 1000; }
  ws_user_gids() { echo "1000 44"; }
  ws_user_groups() { echo "${FAKE_GROUPS:-research video}"; }
  ws_owner_uid() {
    case "$1" in
      "$ROOT"|"$ROOT/datasets") if [ "$FAKE_LAYOUT" = separated ]; then echo 1001; else echo 1000; fi ;;
      "$ROOT/tmp/.bowelnca-install.lock") echo "${FAKE_LOCK_OWNER:-1000}" ;;
      "$ROOT"/*) echo 1000 ;;
      *) echo 0 ;;
    esac
  }
  ws_owner_gid() { echo 1000; }
  ws_writable() {
    case "$1" in
      "$ROOT") [ "$FAKE_LAYOUT" != separated ] ;;
      "$ROOT/datasets") [ "$FAKE_LAYOUT" != separated ] || [ -n "${FAKE_DATASETS_WRITABLE:-}" ] ;;
      *) [ -w "$1" ] ;;
    esac
  }
  ws_mount_target() { echo "${FAKE_MNT_TARGET:-$EXPECTED_MOUNT}"; }
  ws_mount_fstype() { echo "${FAKE_FSTYPE:-ext4}"; }
  ws_all_mount_targets() {
    [ -z "${FAKE_MOUNTS_FAIL:-}" ] || return 1
    printf '/\n%s\n' "$EXPECTED_MOUNT"; if [ -n "${FAKE_NESTED:-}" ]; then echo "$FAKE_NESTED"; fi
  }
  ws_dev() { if [ "$1" = / ]; then echo rootfs; else stat -c %d -- "$1"; fi; }
  WS_MIN_FREE_BYTES="${FAKE_MIN_FREE:-1}"
}

# run_inst ARGS...: run the installer's main against the synthetic system.
run_inst() {
  (
    export PATH="$stubs:$PATH"
    BOWELNCA_SOURCE_ONLY=1
    . "$installer"
    ROOT="$WS"; EXPECTED_MOUNT="$data"; TEGRA_RELEASE_FILE="$tegra"; CUDA_HOME_DIR="$fake_cuda"
    PYTHON3="$fake_py3"; CURL="$stubs/curl"; REPO_DIR="$fake_repo"; LOCK_DIR="$locks"; TORCH_SHA256="$fake_hash"
    TORCH_URL="https://example.invalid/torch.whl"
    fake_system "${FAKE_LAYOUT_RUN:-separated}"
    main "$@"
  )
}
# run_ver ARGS...: run the verifier's main against the synthetic system.
run_ver() {
  (
    export PATH="$stubs:$PATH"
    BOWELNCA_SOURCE_ONLY=1
    . "$verifier"
    ROOT="$WS"; EXPECTED_MOUNT="$data"
    fake_system "${FAKE_LAYOUT_RUN:-interim}"
    main "$@"
  )
}
expect_fail() {  # expect_fail DESC PATTERN CMD...
  local desc="$1" pat="$2" out; shift 2
  if out="$("$@" 2>&1)"; then bad "$desc: succeeded unexpectedly"; return 0; fi
  if grep -qE -- "$pat" <<<"$out"; then ok "$desc"; else bad "$desc: output lacked /$pat/: $(tail -n 3 <<<"$out")"; fi
}
core_env() {
  export BOWELNCA_CORE_APPROVAL="D22-2026-12-01-AB" BOWELNCA_REVIEWED_COMMIT="$reviewed"
  unset BOWELNCA_SCI_APPROVAL
}
sci_env() { core_env; export BOWELNCA_SCI_APPROVAL="D23-2026-12-05-AB"; }

core_venv="$WS/venvs/xavier-jp516-py38-torch21-core-v1"
sci_venv="$WS/venvs/xavier-jp516-py38-torch21-sci-v1"

# =============================== installer: static ===============================
code="$(sed -e 's/[[:space:]]#.*$//' -e '/^[[:space:]]*#/d' "$installer")"
grep -qE '\bsudo\b|apt-get[[:space:]]+install|apt[[:space:]]+install' <<<"$(grep -vE "abort \"|log \"" <<<"$code")" \
  && bad "installer invokes sudo/apt outside messages" || ok "installer has no sudo/apt invocation"
grep -q '^set -euo pipefail' "$installer" && ok "installer uses set -euo pipefail" || bad "missing set -euo pipefail"
grep -q 'sha256sum --check --strict' "$installer" && ok "strict checksum verification present" || bad "no strict checksum check"
n_pip=$(grep -cE 'pip install' <<<"$code" || true)
n_hash=$(grep -cE 'pip install --require-hashes --no-deps --only-binary=:all:' <<<"$code" || true)
[ "$n_pip" -ge 1 ] && [ "$n_pip" = "$n_hash" ] && ok "every pip install is hash-locked, no-deps, binary-only" \
  || bad "a pip install lacks --require-hashes/--no-deps/--only-binary ($n_hash of $n_pip)"
grep -qE 'nvpmodel|jetson_clocks|systemctl|\bchown\b|\bchmod\b|\bsetfacl\b|\busermod\b|\bgpasswd\b' <<<"$code" \
  && bad "installer touches power/system/permissions/accounts" || ok "installer does not touch power, services, permissions or accounts"
grep -qE '\|[[:space:]]*grep -q' <<<"$code" && bad "installer pipes into grep -q (SIGPIPE risk under pipefail)" \
  || ok "installer never pipes into grep -q"
grep -qE 'df .*-BG|tr -dc' <<<"$code" && bad "installer parses df output in GiB" || ok "installer uses byte-based free-space checks"

# ============================ installer: refusals ===============================
reset_state; make_ws separated
expect_fail "refuses without --stage" 'choose --stage' run_inst
( unset BOWELNCA_CORE_APPROVAL BOWELNCA_SCI_APPROVAL BOWELNCA_REVIEWED_COMMIT
  expect_fail "refuses without core approval" 'NOT APPROVED' run_inst --stage core )
( export BOWELNCA_CORE_APPROVAL=yes BOWELNCA_REVIEWED_COMMIT="$reviewed"
  expect_fail "rejects a malformed approval reference" 'NOT APPROVED' run_inst --stage core )
( core_env; expect_fail "sci refuses without its own approval" 'NOT APPROVED.*sci' run_inst --stage sci )
( core_env; unset BOWELNCA_REVIEWED_COMMIT
  expect_fail "refuses without a reviewed commit" 'REVIEWED_COMMIT' run_inst --stage core )
( core_env; export BOWELNCA_REVIEWED_COMMIT=0000000000000000000000000000000000000000
  expect_fail "refuses when the checkout is not the reviewed commit" 'not the reviewed commit' run_inst --stage core )
touch "$fake_repo/untracked"
( core_env; expect_fail "refuses a modified or untracked checkout" 'local modifications' run_inst --stage core )
rm -f "$fake_repo/untracked"
no_markers && ok "no download or install attempted by any refusal" || bad "tools invoked during refusals: $(ls "$markers")"
[ ! -e "$core_venv" ] && [ ! -e "$WS/tmp/.bowelnca-install.lock" ] && ok "refusals create nothing" || bad "refusal created files"

# Precondition failures (all before any download).
pre_case() {  # pre_case DESC PATTERN [setup...]
  local desc="$1" pat="$2"; shift 2
  reset_state; make_ws separated
  ( core_env; "$@"; expect_fail "$desc" "$pat" run_inst --stage core )
  no_markers || bad "$desc: tools invoked: $(ls "$markers")"
  [ ! -e "$core_venv" ] || bad "$desc: venv created"
}
pre_case "refuses the interim layout (separation required)" 'separated layout' export FAKE_LAYOUT_RUN=interim
pre_case "refuses a research account in the sudo group" "privileged group 'sudo'" export FAKE_GROUPS="research sudo video"
pre_case "refuses a research account in the docker group" "privileged group 'docker'" export FAKE_GROUPS="research docker"
pre_case "refuses research-writable datasets" 'datasets is writable' export FAKE_DATASETS_WRITABLE=1
pre_case "refuses a wrong mount" 'workspace mount is' export FAKE_MNT_TARGET=/
pre_case "refuses a wrong filesystem type" 'filesystem is' export FAKE_FSTYPE=vfat
pre_case "refuses a nested mount inside the workspace" 'mounted inside the workspace' export FAKE_NESTED="$WS/venvs"
pre_case "refuses insufficient free space (bytes)" 'bytes free' export FAKE_MIN_FREE=999999999999999999
pre_case "refuses when libopenblas is missing" 'libopenblas' touch "$state/no_openblas"
symlink_venvs() { mkdir -p "$work/elsewhere"; rm -rf "$WS/venvs"; ln -s "$work/elsewhere" "$WS/venvs"; }
pre_case "refuses a symlinked venvs directory" 'symlink' symlink_venvs
reset_state; make_ws separated
ln -s "$work/elsewhere-venv" "$core_venv"
( core_env; expect_fail "refuses a dangling symlink at the venv destination" 'symlink|already exists' run_inst --stage core )
no_markers || bad "symlink destination: tools invoked"

# ldconfig with large output and the match first: no SIGPIPE false failure.
reset_state; make_ws separated
if out="$(run_inst --stage core --check-only 2>&1)"; then ok "check-only passes with large ldconfig output (no SIGPIPE)"
else bad "check-only failed on a valid synthetic host: $(tail -n 3 <<<"$out")"; fi

# --check-only writes nothing, downloads nothing and needs no approval.
reset_state; make_ws separated
before="$(tree_sum)"
( unset BOWELNCA_CORE_APPROVAL BOWELNCA_REVIEWED_COMMIT; run_inst --stage core --check-only >/dev/null 2>&1 ) \
  && [ "$before" = "$(tree_sum)" ] && no_markers && ok "--check-only writes and downloads nothing" \
  || bad "--check-only changed the workspace or invoked tools"

# Concurrent run: a held lock makes a second run refuse before any download.
reset_state; make_ws separated
: > "$WS/tmp/.bowelnca-install.lock"
flock "$WS/tmp/.bowelnca-install.lock" sleep 30 &
holder=$!
sleep 0.3
( core_env; expect_fail "refuses while another installation holds the lock" 'another installation is running' run_inst --stage core )
kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
no_markers && [ ! -e "$core_venv" ] && ok "concurrent refusal downloads and creates nothing" || bad "concurrent refusal had side effects"

# Checksum failure: file deleted, no venv, no record, temp download dir removed.
reset_state; make_ws separated; touch "$state/tamper"
( core_env; expect_fail "aborts on a SHA-256 mismatch" 'SHA-256 mismatch' run_inst --stage core )
[ ! -e "$core_venv" ] && [ -z "$(find "$WS/tmp" -mindepth 1 ! -name .bowelnca-install.lock)" ] \
  && [ -z "$(find "$WS/reports" -name 'env-*')" ] && ok "checksum failure leaves no venv, download or record" \
  || bad "checksum failure left files behind"

# Partial install rollback: fail at the 2nd pip install (core deps).
reset_state; make_ws separated
mkdir -p "$WS/venvs/unrelated-env"; printf 'keep\n' > "$WS/venvs/unrelated-env/marker"
printf 'keep\n' > "$WS/cache/preexisting"
echo 2 > "$state/fail_pip_at"
( core_env; expect_fail "aborts when a pip step fails" 'removed [0-9]+ path' run_inst --stage core )
[ ! -e "$core_venv" ] && ok "partial venv rolled back" || bad "partial venv left behind"
[ -f "$WS/venvs/unrelated-env/marker" ] && [ -f "$WS/cache/preexisting" ] \
  && ok "rollback keeps files this run did not create" || bad "rollback removed pre-existing files"
[ -z "$(find "$WS/reports" -name 'env-*')" ] && [ -z "$(find "$WS/tmp" -name 'torch-dl.*')" ] && ok "rollback leaves no record or download" \
  || bad "rollback left a record or download"

# Smoke-test failure also rolls back.
reset_state; make_ws separated; touch "$state/smoke_fail"
( core_env; expect_fail "aborts when the smoke test fails" 'smoke test failed' run_inst --stage core )
[ ! -e "$core_venv" ] && [ -z "$(find "$WS/reports" -name 'env-*')" ] && ok "smoke failure rolls back venv and record" || bad "smoke failure left files"

# sci before core: refused.
reset_state; make_ws separated
( sci_env; expect_fail "sci refuses without a passing core record" 'no passing core record' run_inst --stage sci )
no_markers || bad "sci-before-core invoked tools"

# ======================= installer: R4 containment and failures ===================
lock="$WS/tmp/.bowelnca-install.lock"
lock_case() {  # lock_case DESC PATTERN SETUP...
  local desc="$1" pat="$2"; shift 2
  reset_state; make_ws separated
  ( core_env; "$@"; expect_fail "$desc" "$pat" run_inst --stage core )
  no_markers || bad "$desc: tools invoked: $(ls "$markers")"
  [ ! -e "$core_venv" ] || bad "$desc: venv created"
}
lock_case "refuses a symlinked install lock" 'symlink' eval 'printf x > "$work/lock-target"; ln -s "$work/lock-target" "$lock"'
lock_case "refuses a dangling symlink install lock" 'symlink' ln -s "$work/missing-lock" "$lock"
lock_case "refuses a directory as install lock" 'not a regular file' mkdir "$lock"
lock_case "refuses a FIFO as install lock" 'not a regular file' mkfifo "$lock"
lock_case "refuses an install lock owned by another account" 'not owned by the research account' eval ': > "$lock"; export FAKE_LOCK_OWNER=1001'
lock_case "refuses a hard-linked install lock" 'extra hard links' eval ': > "$lock"; ln "$lock" "$WS/tmp/second-link"'
[ ! -e "$work/missing-lock" ] && ok "dangling lock symlink target never created" || bad "lock symlink target was created"
pre_case "fails closed when mounts cannot be enumerated" 'could not enumerate mounts' export FAKE_MOUNTS_FAIL=1

# Dangling symlink at the record destination (fixed timestamp via the date stub).
reset_state; make_ws separated
ln -s "$work/record-target" "$WS/reports/env-core-20261201T000000Z.txt"
( core_env; expect_fail "refuses a dangling symlink at the record destination" 'record destination' run_inst --stage core )
[ ! -e "$work/record-target" ] && [ ! -e "$core_venv" ] && ok "record symlink target never written; venv rolled back" \
  || bad "record symlink followed or venv left"

# Controlled installation environment (R4-02).
reset_state; make_ws separated
if out="$( (core_env; export PYTHONPATH=/evil PYTHONHOME=/evil PIP_TARGET=/evil PIP_PREFIX=/evil PIP_USER=1 \
      PIP_INDEX_URL=https://evil.invalid PIP_CONFIG_FILE=/evil.conf; run_inst --stage core) 2>&1)"; then
  if ! grep -qE '^(PYTHONPATH|PYTHONHOME|PIP_TARGET|PIP_PREFIX|PIP_USER|PIP_INDEX_URL)=' "$state/pip_env" "$state/venv_env" \
     && grep -qx 'PIP_CONFIG_FILE=/dev/null' "$state/pip_env" && grep -qx 'PATH=/usr/bin:/bin' "$state/pip_env"; then
    ok "pip and venv creation ignore inherited PYTHON*/PIP_* variables and pip config files"
  else bad "inherited environment reached pip or venv: $(cut -d= -f1 "$state/pip_env" "$state/venv_env" | sort -u | tr '\n' ' ')"; fi
else bad "install failed with hostile environment: $(tail -n 3 <<<"$out")"; fi
[ ! -e /evil ] && ok "no install redirected outside the venv" || bad "install wrote to /evil"

# Explicit failure handling (R4-03): each failure aborts, rolls back, keeps diagnostics.
fail_case() {  # fail_case DESC PATTERN SWITCH
  local desc="$1" pat="$2" sw="$3"
  reset_state; make_ws separated; touch "$state/$sw"
  ( core_env; expect_fail "$desc" "$pat" run_inst --stage core )
  [ ! -e "$core_venv" ] && [ -z "$(find "$WS/reports" -name 'env-*')" ] \
    && ok "$desc: venv and record rolled back" || bad "$desc: venv or record left behind"
  [ -n "$(find "$WS/reports" -maxdepth 1 -name 'diag-core-*' -type d)" ] \
    && ok "$desc: private diagnostics kept" || bad "$desc: diagnostics missing"
}
fail_case "aborts when the env hook cannot be written" 'environment hook' activate_dir
fail_case "aborts when pip freeze fails" 'pip freeze failed' fail_freeze
fail_case "aborts when the smoke result is missing" 'smoke result missing' smoke_nojson
fail_case "aborts when lock hashing fails" 'hash the lock files' fail_locksum
reset_state; make_ws separated; touch "$state/smoke_fail"
( core_env; run_inst --stage core >/dev/null 2>&1 ) || true
grep -q '"result": "fail"' "$WS"/reports/diag-core-*/smoke.json 2>/dev/null \
  && ok "failed smoke result retained in private diagnostics" || bad "failed smoke JSON not retained"

# ====================== installer: successful simulated runs =====================
reset_state; make_ws separated
if out="$( (core_env; run_inst --stage core) 2>&1)"; then ok "core install completes on a synthetic host"
else bad "core install failed: $(tail -n 5 <<<"$out")"; fi
order="$(cut -d' ' -f1,2 "$state/pip.log" | tr '\n' ';')"
case "$order" in
  "install1 pip==24.3.1;install2 filelock==3.16.1;install3 torch;check;") ok "core order: bootstrap, deps, verified torch, pip check" ;;
  *) bad "unexpected core install order: $order" ;;
esac
grep -q '^UNLOCKED' "$state/pip.log" && bad "an install ran without hash locking" || ok "all simulated installs hash-locked"
rec="$(ls "$WS"/reports/env-core-*.txt 2>/dev/null | head -n 1)"
if [ -n "$rec" ] && grep -qx 'result: pass' "$rec" && grep -qx 'approval_core: D22-2026-12-01-AB' "$rec" \
   && grep -qx "reviewed_commit: $reviewed" "$rec" && grep -q '^smoke: {"result": "pass"' "$rec" \
   && [ "$(tail -n 1 "$rec")" = "result: pass" ]; then ok "core record has approval, commit, smoke result; pass written last"
else bad "core record incomplete"; fi
grep -q 'approval_sci' "$rec" && bad "core record claims a sci approval" || ok "core record has no sci approval"
envf="$state/smoke_env.core"
if grep -qx "CUDA_HOME=$fake_cuda" "$envf" && grep -q "^PATH=$fake_cuda/bin:$core_venv/bin:" "$envf" \
   && grep -q "^LD_LIBRARY_PATH=$fake_cuda/lib64" "$envf" && grep -qx "TORCH_HOME=$core_venv/.cache/torch" "$envf" \
   && grep -qx "MPLCONFIGDIR=$core_venv/.cache/matplotlib" "$envf" && grep -qx 'PIP_NO_CACHE_DIR=1' "$envf"; then
  ok "smoke test ran through activate in the scoped research environment"
else bad "smoke environment not scoped: $(tr '\n' ' ' < "$envf")"; fi
[ -z "$(find "$WS/tmp" -name 'torch-dl.*')" ] && ok "download directory removed after success" || bad "download dir left"
grep -q 'bowelnca-env.sh' "$core_venv/bin/activate" && ok "activate sources the scoped env hook" || bad "env hook not wired"
for t in sudo apt apt-get pip pip3 wget nvpmodel jetson_clocks; do
  [ ! -e "$markers/$t" ] || bad "core install invoked $t"
done
ok "core install invoked no sudo, apt, system pip or power tools"

# Second core run refuses: venv exists, nothing overwritten.
core_sum="$(cd "$core_venv" && find . -type f -exec sha256sum {} + | sort | sha256sum)"
( core_env; expect_fail "a second core install refuses to overwrite" 'already exists' run_inst --stage core )

# sci with a different core approval reference: refused.
( sci_env; export BOWELNCA_CORE_APPROVAL="D99-2026-12-01-ZZ"
  expect_fail "sci refuses a core reference that was not recorded" 'no passing core record' run_inst --stage sci )

# sci after core: new venv, core untouched, both approvals recorded.
rm -f "$state/pip.log" "$state/pipcount"
if out="$( (sci_env; run_inst --stage sci) 2>&1)"; then ok "sci install completes after core"
else bad "sci install failed: $(tail -n 5 <<<"$out")"; fi
[ -d "$sci_venv" ] && ok "sci uses its own versioned venv" || bad "sci venv missing"
[ "$core_sum" = "$(cd "$core_venv" && find . -type f -exec sha256sum {} + | sort | sha256sum)" ] \
  && ok "sci install leaves the core venv unchanged" || bad "sci install modified the core venv"
srec="$(ls "$WS"/reports/env-sci-*.txt 2>/dev/null | head -n 1)"
if [ -n "$srec" ] && grep -qx 'approval_core: D22-2026-12-01-AB' "$srec" && grep -qx 'approval_sci: D23-2026-12-05-AB' "$srec" \
   && grep -qx 'result: pass' "$srec"; then ok "sci record carries both approval references"
else bad "sci record incomplete"; fi
grep -q '^install2 batchgenerators==' "$state/pip.log" && ok "sci installs from the sci lock" || bad "sci did not use the sci lock"

# sci failure rolls back only the sci venv.
rm -f "$state/pip.log" "$state/pipcount"; rm -rf "$sci_venv" "$WS"/reports/env-sci-*.txt "$WS"/reports/diag-sci-*
echo 2 > "$state/fail_pip_at"
( sci_env; expect_fail "sci aborts when a pip step fails" 'removed' run_inst --stage sci )
rm -f "$state/fail_pip_at"
[ ! -e "$sci_venv" ] && [ -d "$core_venv" ] && [ -n "$(ls "$WS"/reports/env-core-*.txt)" ] \
  && ok "sci rollback removes only the sci venv; core venv and record kept" || bad "sci rollback touched core"

# ============================ smoke test (static) ================================
smoke="$repo_root/scripts/proposed/xavier_smoke_test.py"
python3 -m py_compile "$smoke" 2>/dev/null && ok "smoke test compiles" || bad "smoke test does not compile"
rm -rf "$repo_root/scripts/proposed/__pycache__"
for k in torch_version torch_cuda_build cudnn_version device_capability peak_allocated_mib free_before_mib sci_imports sci_pinned_versions; do
  grep -q "$k" "$smoke" || bad "smoke test does not record $k"
done
ok "smoke test records torch, CUDA, cuDNN, capability, memory and sci checks"

# ============================= lock consistency ==================================
grep -q "sha256:$real_hash" "$repo_root/env/xavier/requirements-xavier-core.lock" \
  && grep -q "sha256:$real_hash" "$repo_root/env/xavier/requirements-xavier-sci.lock" \
  && ok "installer torch hash matches core and sci locks" || bad "torch hash missing from a lock"
python3 - "$repo_root/env/xavier" <<'PY' && ok "every lock entry hashed; sci lock pins every core package identically" || bad "lock consistency failed"
import re, sys, os
d = sys.argv[1]
def entries(name):
    text = open(os.path.join(d, name)).read()
    blocks = [b for b in re.split(r'\n(?=[A-Za-z0-9])', text) if re.match(r'[A-Za-z0-9]', b)]
    assert blocks and all('--hash=sha256:' in b for b in blocks), name
    return {re.split(r'[=@ ]', b, maxsplit=1)[0].lower(): b.split('\\')[0].strip() for b in blocks}
core, sci = entries('requirements-xavier-core.lock'), entries('requirements-xavier-sci.lock')
entries('requirements-xavier-bootstrap.lock')
missing = {k: v for k, v in core.items() if sci.get(k) != v}
sys.exit(1 if missing else 0)
PY
man="$repo_root/env/xavier/dependency-manifest.json"
python3 - "$repo_root/env/xavier" "$man" <<'PY' && ok "dependency manifest matches every lock hash and pin" || bad "dependency manifest inconsistent with locks"
import json, re, sys, os
d, man = sys.argv[1], json.load(open(sys.argv[2]))
by_hash = {w["sha256"]: w for w in man["wheels"]}
for lock in ("bootstrap", "core", "sci"):
    text = open(os.path.join(d, "requirements-xavier-%s.lock" % lock)).read()
    for b in re.split(r'\n(?=[A-Za-z0-9])', text):
        if not re.match(r'[A-Za-z0-9]', b):
            continue
        name = re.split(r'[=@ ]', b, maxsplit=1)[0].lower()
        hashes = re.findall(r'sha256:([0-9a-f]{64})', b)
        hit = [by_hash[h] for h in hashes if h in by_hash]
        assert len(hit) == 1, (lock, name, len(hit))
        w = hit[0]
        assert w["name"].lower().replace("_", "-") == name.replace("_", "-"), (name, w["name"])
        assert "aarch64" in w["platform_tag"] or w["platform_tag"] == "any", w
        assert re.search(r"(cp38|py3|py2\.py3|abi3)", w["python_tag"] + w["abi_tag"]), w
        m = re.match(r'[^=]+==(\S+)', b)
        if m:
            assert w["version"] == m.group(1), (name, w["version"])
PY

# =========================== workspace verifier ==================================
vcode="$(sed -e 's/[[:space:]]#.*$//' -e '/^[[:space:]]*#/d' -e '/_GROUPS=(/d' "$verifier" "$repo_root/scripts/lib/workspace_checks.sh")"
grep -qE '(^|[;&|(]|then|do)[[:space:]]*sudo\b|\bchown\b|\bchmod\b|\bsetfacl\b|\bhostname\b|\bwhoami\b|\busermod\b' <<<"$vcode" \
  && bad "verifier contains a privileged/identity command" || ok "verifier has no sudo/chown/chmod/hostname calls"
grep -qE '(^|[;&|[:space:]])sync([[:space:]]*$|[[:space:]]*[;&|])' <<<"$vcode" && bad "verifier runs a global sync" \
  || ok "verifier never runs a global sync"

reset_state; make_ws interim
before="$(tree_sum)"
out="$(run_ver --write-test 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^FAIL' <<<"$out" && ok "verifier passes a correct interim workspace" \
  || bad "verifier failed a correct interim workspace: $(grep '^FAIL' <<<"$out" | head -n 3)"
grep -q 'write test: exactly 1048576 bytes written, fsynced, verified and removed' <<<"$out" \
  && ok "write test writes exactly 1 MiB and verifies it" || bad "write test did not complete"
[ "$before" = "$(tree_sum)" ] && ok "write test leaves no files behind" || bad "write test left files behind"
grep -q "WARN  datasets is research-writable" <<<"$out" && ok "interim layout warns that datasets are research-writable" \
  || bad "interim datasets warning missing"
host="$("$real_uname" -n)"; uname_="$(id -un)"
if [ "${#host}" -ge 4 ] && grep -qF -- "$host" <<<"$out"; then bad "verifier printed hostname"; else ok "verifier prints no hostname"; fi
if [ "$uname_" != root ] && [ "${#uname_}" -ge 4 ] && grep -qwF -- "$uname_" <<<"$out"; then bad "verifier printed username"
else ok "verifier prints no username"; fi

# Failed preconditions: write test is skipped and mktemp is never called.
cat > "$stubs/mktemp" <<EOF
#!/bin/sh
touch "$markers/mktemp"
exec /usr/bin/mktemp "\$@"
EOF
chmod +x "$stubs/mktemp"
ver_case() {  # ver_case DESC PATTERN [setup...]   (layout from CASE_LAYOUT)
  local desc="$1" pat="$2" layout="${CASE_LAYOUT:-interim}"; shift 2
  reset_state; make_ws "$layout"
  (
    export FAKE_LAYOUT_RUN="$layout"
    "$@"
    before="$(tree_sum)"
    expect_fail "$desc" "$pat" run_ver --layout "$layout" --write-test
    [ ! -e "$markers/mktemp" ] && [ "$before" = "$(tree_sum)" ] || bad "$desc: write attempted despite failed checks"
  )
}
ver_case "verifier rejects root mode 755 and skips the write test" 'mode is 755.*|SKIPPED' chmod 755 "$WS"
ver_case "verifier rejects a missing subdirectory" 'subdir derived missing' rmdir "$WS/derived"
ver_case "verifier rejects a symlinked subdirectory" 'subdir tmp missing, not a directory, or a symlink' \
  eval 'mkdir -p "$work/elsewhere-tmp"; rmdir "$WS/tmp"; ln -s "$work/elsewhere-tmp" "$WS/tmp"'
ver_case "verifier rejects a wrong mount" 'workspace mount is' export FAKE_MNT_TARGET=/
ver_case "verifier rejects a nested mount" 'mounted inside the workspace' export FAKE_NESTED="$WS/derived"
ver_case "verifier rejects too little free space" 'bytes free' export FAKE_MIN_FREE=999999999999999999
ver_case "verifier fails closed when mounts cannot be enumerated" 'could not enumerate mounts' export FAKE_MOUNTS_FAIL=1
grep -q 'SKIPPED' <<<"$( (export FAKE_FSTYPE=vfat; run_ver --write-test) 2>&1 || true)" \
  && ok "write test reports SKIPPED when a check fails" || bad "write test skip not reported"
rm -f "$stubs/mktemp"

# Failed and short writes: reported as FAIL and the temporary file is removed.
cat > "$stubs/tee" <<'EOF'
#!/bin/sh
for a; do f="$a"; done
head -c 1000 > "$f"; cat >/dev/null; exit 1
EOF
chmod +x "$stubs/tee"
reset_state; make_ws interim
expect_fail "write failure is reported" 'write test: write failed; temporary file removed' run_ver --write-test
[ -z "$(find "$WS/tmp" -name 'write-test.*')" ] && ok "failed write leaves no temporary file" || bad "failed write left a file"
cat > "$stubs/tee" <<'EOF'
#!/bin/sh
for a; do f="$a"; done
head -c 1000 > "$f"; cat >/dev/null; exit 0
EOF
reset_state; make_ws interim
expect_fail "short write is detected" 'wrote 1000 bytes' run_ver --write-test
[ -z "$(find "$WS/tmp" -name 'write-test.*')" ] && ok "short write leaves no temporary file" || bad "short write left a file"
rm -f "$stubs/tee"

# Separated (D21) layout.
reset_state; make_ws separated
out="$(FAKE_LAYOUT_RUN=separated run_ver --layout separated --write-test 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] && ok "verifier passes a correct separated layout" || bad "separated layout failed: $(grep '^FAIL' <<<"$out" | head -n 3)"
CASE_LAYOUT=separated
ver_case "separated layout rejects sudo membership" "privileged group 'sudo'" export FAKE_GROUPS="research sudo"
ver_case "separated layout rejects research-writable datasets" 'datasets is writable' export FAKE_DATASETS_WRITABLE=1
ver_case "separated layout rejects a group-writable root" 'mode is 770' chmod 770 "$WS"
unset CASE_LAYOUT
# A research-owned root is what the interim layout produces; checking it as separated must fail.
reset_state; make_ws interim
( export FAKE_LAYOUT_RUN=interim; expect_fail "interim workspace fails the separated check" 'separated layout expects' run_ver --layout separated )
interim_sudo="$( (export FAKE_GROUPS="research sudo"; run_ver) 2>&1 || true)"
grep -q "WARN  account is in privileged group 'sudo'" <<<"$interim_sudo" && ok "interim layout warns (not fails) on sudo membership" \
  || bad "interim sudo warning missing"

if [ -s "$work/failed" ]; then printf '%d check(s) failed\n' "$(wc -l < "$work/failed")"; exit 1; fi
n_ok="$(wc -l < "$work/ok")"
printf 'PASS: %d checks; proposed installer fails closed, rolls back its own files, and the verifier behaves (regression checks, not guarantees)\n' "$n_ok"
