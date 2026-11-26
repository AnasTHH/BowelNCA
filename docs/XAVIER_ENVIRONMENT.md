# Xavier research environment: installation proposal and dependency assessment

**Status: approved by the project owner (Anas, 26 Nov 2026), conditionally: D22 after D21, W2 and the Stage 0 to Stage 1A gate; D23 after a passing core record. NOT EXECUTED.** Nothing in this document has been run on the Xavier.
Installation is proposed as **Stage 1A** (`docs/proposals/STAGE_1A_1B_SPLIT.md`), which needs Dr. Iyad's sign-off. The core and scientific environments need **separate** recorded approvals (D22, D23 in `docs/DECISIONS.md`). Both require the account separation (D21) first.
**Last updated:** 26 Nov 2026 (round 3 revision) · **Script:** [`scripts/proposed/install_xavier_env.sh`](../scripts/proposed/install_xavier_env.sh) · **Locks and manifest:** [`env/xavier/`](../env/xavier/)

## 1. Target, as observed on 26 Nov 2026

JetPack 5.1.6-b5 / L4T R35.6.4, Ubuntu 20.04.6, aarch64, Python 3.8.10 (`cp38`), CUDA 11.4.19 (`nvcc` 11.4.315, not on PATH), cuDNN 8.6.0.166, TensorRT 8.5.2.2. Root eMMC 4.5 GiB free; NVMe `/data` 363 GiB free. Source: the owner's inventory run (`reports/stage_0.md` section 1).

This is NVIDIA's standard supported stack for the installed JetPack, and the proposal stays on it. The system Python 3.9.5 is not used, because NVIDIA's JetPack 5 wheels are `cp38` only.

## 2. PyTorch wheel

| Field | Value | Verified how |
|---|---|---|
| Wheel | `torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` | NVIDIA compatibility matrix row "2.1.0a / 23.06 / JetPack 5.1.x" |
| URL | `https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` | HTTP 200; downloaded 25 Nov and twice on 26 Nov 2026 |
| SHA-256 | `5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe` | Identical on all three downloads |
| Size | 170,246,840 bytes compressed; 458,170,160 bytes (9,810 files) uncompressed | Measured |
| ABI / arch | `cp38-cp38-linux_aarch64`; `Requires-Python >=3.8.0` | Wheel tag and METADATA |
| Built for | CUDA 11.4 (`torch/version.py: cuda = '11.4'`) | Wheel contents |

**Status: candidate compatible build, pending on-device validation** (JetPack 5.1.6; not yet installed or tested on this device). NVIDIA lists the wheel for "JetPack 5.1.x"; staff confirmed it on 5.1.4 / AGX Xavier; NVIDIA states 5.1.6 "packages the same compute stack as 5.1.5"; the device's CUDA 11.4 and cuDNN 8.6 match. The smoke test (section 6) is the on-device verification.

## 3. Dependencies

### 3.1 Locks

All locks were generated with `uv pip compile --python-version 3.8 --python-platform aarch64-manylinux_2_31 --only-binary :all: --generate-hashes` (glibc 2.31 = Ubuntu 20.04).

| Lock | Purpose | Contents |
|---|---|---|
| `requirements-xavier-bootstrap.lock` | Upgrade the venv's bundled pip 20.0.2 | `pip==24.3.1` |
| `requirements-xavier-core.lock` | Core environment | torch (NVIDIA URL + SHA-256), `numpy==1.24.4` (last release for Python 3.8; NVIDIA's documented 1.26.1 requires Python >= 3.9), filelock, fsspec, jinja2, MarkupSafe, mpmath, networkx, sympy, typing-extensions |
| `requirements-xavier-sci.lock` | Scientific environment (a superset of core, constrained by it) | scipy 1.10.1, scikit-image 0.21.0, nibabel 5.2.1, SimpleITK 2.4.1, torchio 0.20.1, einops 0.8.1, batchgenerators 0.25.6, matplotlib 3.7.5, scikit-learn 1.3.2, pandas 2.0.3, pillow 10.4.0, tqdm 4.70.1, plus pinned transitive deps (49 packages + torch) |

CI checks that every lock entry is hashed, that the sci lock pins every core package identically, and that the installer's torch hash appears in both.

### 3.2 Machine-readable verification manifest

[`env/xavier/dependency-manifest.json`](../env/xavier/dependency-manifest.json) lists all **51 actual wheels** the locks pin, with filename, distribution name, version, Python/ABI/platform tags, `Requires-Python` from the wheel's METADATA, size and SHA-256, and which lock(s) use each. It was produced on 26 Nov 2026 by downloading every artefact for `cp38 / aarch64` with `pip download --require-hashes` (and the torch wheel from NVIDIA), then running [`env/xavier/generate_dependency_manifest.py`](../env/xavier/generate_dependency_manifest.py); the reproduce command is in that script. CI cross-checks every lock hash and version against the manifest.

Findings:
- **No source compilation.** Every compiled package (numpy, scipy, scikit-image, scikit-learn, pandas, pillow, SimpleITK, PyWavelets, matplotlib, contourpy, kiwisolver, fonttools, MarkupSafe, wrapt) has a `cp38 manylinux2014 / manylinux_2_17 aarch64` wheel. The rest are pure-Python `py3-none-any`. Total download about 346 MB including torch.
- **Requires-Python** is compatible with 3.8 for every wheel that declares it. Four wheels declare none (batchgenerators, mpmath, pytz, SimpleITK); their cp38 tag or pure-Python form is the compatibility evidence.

### 3.3 Torch substitution guard

torchio declares `torch` as a dependency, so a resolver could pull a CPU-only PyPI torch over NVIDIA's build. Every install runs with `--require-hashes --no-deps --only-binary=:all:` against fully pinned locks, and torch is installed only from the locally verified NVIDIA file.

### 3.4 Deliberately not included

| Package | Status | Reason |
|---|---|---|
| torchvision | Excluded | NVIDIA ships no JetPack 5 wheel. A source build on the Xavier needs separate authorization |
| monai | Not locked | Not used by upstream OctreeNCA |
| aim, qtpy | Not locked | Upstream logging and GUI tools |

Known limits: locks pin artefacts by hash, but cannot prove runtime compatibility on Jetson; the scientific import check (section 6) covers that. Some pins (packaging 26.2, python-dateutil 3.0.0, tqdm 4.70.1) are recent releases that still declare Python 3.8 support; regenerate with explicit upper bounds if a reviewer prefers older pins.

## 4. Installation lifecycle

Two **distinct, versioned** virtual environments. The scientific stage never modifies the core venv.

| Stage | Venv | Approval(s) | Precondition | Rollback |
|---|---|---|---|---|
| core | `/data/bowelnca/venvs/xavier-jp516-py38-torch21-core-v1` | `BOWELNCA_CORE_APPROVAL` (D22) | D21 done | delete the core venv and its `env-core-*` record |
| sci | `/data/bowelnca/venvs/xavier-jp516-py38-torch21-sci-v1` | `BOWELNCA_CORE_APPROVAL` (must match a **passing core record**) + `BOWELNCA_SCI_APPROVAL` (D23) | core passed | delete the sci venv and its `env-sci-*` record; core is untouched |

A later change creates `-v2` venvs rather than modifying existing ones.

### 4.1 Preconditions (read-only; the script aborts on any failure)

1. **Approval guard** (not for `--check-only`): reference(s) in the `D<nn>-YYYY-MM-DD-<initials>` format, and `BOWELNCA_REVIEWED_COMMIT` equal to `git rev-parse HEAD` with a clean checkout (no modified or untracked files).
2. **Host:** `aarch64`; `/etc/nv_tegra_release` reports R35 revision 6.4; `/usr/bin/python3` is 3.8 with `ensurepip` and `venv` (otherwise a privileged `apt-get install python3.8-venv` would need separate approval); `/usr/local/cuda/bin/nvcc` reports 11.4; `libopenblas.so.0` is in the linker cache (otherwise `libopenblas-dev`, separate approval). Command output is captured before matching, so no pipe can fail with SIGPIPE under `pipefail`.
3. **Account (D21):** not root; in no privileged group (`sudo admin wheel docker lxd libvirt disk`).
4. **Workspace (D21 separated layout):** `/data/bowelnca` canonical (no symlink in the path), owned by the administrator, group = a research group, mode 750, not research-writable; `datasets/` administrator-owned and not research-writable; the eight execution subdirectories research-owned, mode 700, not symlinks, on the workspace filesystem.
5. **Filesystem:** the workspace mount is `/data`, type `ext4`, not the root filesystem, with **no other filesystem mounted inside it** (if the mount table cannot be read, the check fails closed); at least 10 GiB (10,737,418,240 bytes) free, measured in bytes from `statfs`.
6. **Locks and smoke test** present; the pinned torch hash appears in the core and sci locks.

Then, **while holding an exclusive lock** (`flock` on `/data/bowelnca/tmp/.bowelnca-install.lock`; a concurrent run refuses). Before it is opened, the lock path is validated: an existing path must be a research-owned regular file with a single link (symlinks, dangling symlinks, directories, FIFOs and devices are refused); a new one is created exclusively; after opening, the descriptor must point at exactly that path.

7. **Containment:** the venv path, `tmp/` and `reports/` are canonical, inside the workspace, on the workspace filesystem, and research-owned. Symlinks anywhere on the path are rejected.
8. The target venv does not exist (never overwritten).
9. For `sci`: a passing `env-core-*` record made with the same core approval reference exists.

### 4.2 Commands (after approval; run as `<research-account>`, never with sudo)

```bash
cd /data/bowelnca/workspace/BowelNCA                      # clean clone
git checkout <reviewed-commit>
bash scripts/verify_workspace.sh --layout separated         # must report 0 FAIL
bash scripts/proposed/install_xavier_env.sh --stage core --check-only
BOWELNCA_CORE_APPROVAL=D22-YYYY-MM-DD-<initials> \
BOWELNCA_REVIEWED_COMMIT=<reviewed-commit> \
  bash scripts/proposed/install_xavier_env.sh --stage core
# Later, with its own approval:
BOWELNCA_CORE_APPROVAL=D22-... BOWELNCA_SCI_APPROVAL=D23-YYYY-MM-DD-<initials> \
BOWELNCA_REVIEWED_COMMIT=<reviewed-commit> \
  bash scripts/proposed/install_xavier_env.sh --stage sci
```

The approval references are an **accidental-execution guard, not authentication or authorization**. Before each run, a human confirms the reference exists in `docs/DECISIONS.md`, approves that stage, and names the exact reviewed commit.

### 4.3 What the script does (after the preconditions)

1. Downloads the wheel to a fresh `tmp/torch-dl.*` directory and runs `sha256sum --check --strict`. **On a mismatch it deletes the file and aborts before any venv exists.**
2. Creates the stage's venv with `/usr/bin/python3 -I -m venv` in a **controlled environment** (`env -i` with a fixed PATH, `PIP_CONFIG_FILE=/dev/null` and only the pip settings the script sets; an HTTPS proxy is passed on if set). Inherited `PYTHONPATH`, `PYTHONHOME`, `PIP_TARGET`, `PIP_PREFIX`, `PIP_USER`, `PIP_INDEX_URL` and pip configuration files cannot redirect or alter the install.
3. Hash-locked installs in the same controlled environment (`python -I -m pip install --require-hashes --no-deps --only-binary=:all: --no-cache-dir`), each checked explicitly (`|| abort`, so a failure aborts even if a caller disabled errexit): pip bootstrap; core (or sci) dependencies without torch; torch from the verified local file; `pip check`. pip's log goes to the private diagnostics directory.
4. Writes `bin/bowelnca-env.sh` in the venv and sources it from `activate`: `CUDA_HOME=/usr/local/cuda`, its `bin` on PATH, its `lib64` on `LD_LIBRARY_PATH`, `TMPDIR` on the NVMe, and `TORCH_HOME`, `TORCH_EXTENSIONS_DIR`, `MPLCONFIGDIR` and `XDG_CACHE_HOME` **inside the venv**. Nothing is written to `~/.bashrc` or system files.
5. Runs the smoke test (section 6) **through `activate` in a clean environment** (`env -i`, then `. venv/bin/activate`), which is the same scoped environment later research runs use. 300-second timeout.
6. Collects the evidence first and aborts if any part fails: lock-file hashes (all three); the smoke-test JSON (must exist and report `pass`); **installed versions**, read with `importlib.metadata` by `scripts/proposed/verify_installed_versions.py` and compared (PEP 440 normalized) with every bootstrap and stage entry in `env/xavier/dependency-manifest.json`, including torch `2.1.0a0+41361538.nv23.06`; and `pip freeze` as evidence only (a wheel installed from a local file appears as a PEP 610 direct reference, `torch @ file:///...`, so freeze text is never parsed for versions). Then creates the record `/data/bowelnca/reports/env-<stage>-<UTC>.txt` **exclusively** (an existing file or a dangling symlink at that path is refused) with: stage, venv, both approval references (sci), reviewed commit, L4T, wheel hash, lock hashes, smoke JSON, installed-version JSON, `pip freeze`, diagnostics path, and `result: pass` appended **last**. No usernames or hostnames.
7. **On any failure**, the trap removes exactly the paths this invocation created (its venv, its record) and its download directory. Pre-existing venvs, caches and records are never touched. **Diagnostics are kept privately** in `/data/bowelnca/reports/diag-<stage>-<UTC>/` (pip log, smoke JSON) for investigation; they stay on the device and are never committed.

**Scope of these safeguards.** Containment, locking, the controlled environment and rollback protect against mistakes and accidental damage on the filesystem. They are **not a security sandbox**: package code still runs as the research account with its normal permissions. The real controls are the account separation (D21), hash-locked binary-only artefacts and human review.

### 4.4 Footprint (estimated from measured wheel sizes)

| Item | Download | Installed |
|---|---|---|
| Core venv (torch + deps) | ~0.19 GB | ~0.55 GB + bytecode |
| Sci venv (core + scientific stack, separate copy) | ~0.35 GB | ~1.3 GB |
| Caches (inside each venv) | - | grows with use |
| **Total on NVMe** | | **≈ 2 GB for both venvs** |
| **On root eMMC** | | **≈ 0** by design |

## 5. Workspace verification

[`scripts/verify_workspace.sh`](../scripts/verify_workspace.sh) is non-destructive and prints PASS/WARN/FAIL lines only, with no usernames, hostnames or device names.
```bash
bash scripts/verify_workspace.sh                              # interim layout (today), read-only
bash scripts/verify_workspace.sh --write-test                 # + one 1 MiB file in tmp/
bash scripts/verify_workspace.sh --layout separated           # target layout after D21
```
- **interim** (current): research-owned root, mode 700. Privileged groups and research-writable `datasets/` are WARN.
- **separated** (D21): the table in `docs/XAVIER_ACCESS_AND_SECURITY.md` section 3.2. Privileged groups are FAIL.
- Both: canonical paths (no symlinks), the eight execution subdirectories research-owned and 700, mount `/data`, `ext4`, not the root filesystem, no nested mounts, `/data` not owned by the research account, free space in bytes, cache growth under HOME.
- **Write test:** runs only if every read-only check passed (otherwise reported as SKIPPED and nothing is written). It creates one file with `mktemp`, writes exactly 1,048,576 bytes in a single checked pipeline, `fsync`s **that file only** (`sync -- FILE`, never a global sync), verifies size and SHA-256, and removes it. A trap removes the file on any exit, including a failed or short write.

## 6. Verification (smoke test)

[`scripts/proposed/xavier_smoke_test.py`](../scripts/proposed/xavier_smoke_test.py). Bounded, not a benchmark; no power or clock changes.
1. **Scoped environment:** `VIRTUAL_ENV` is the interpreter's prefix; `CUDA_HOME` is `/usr/local/cuda`; `nvcc` on PATH comes from it; its `lib64` is on `LD_LIBRARY_PATH`; torch/matplotlib/XDG caches are inside the venv.
2. **Torch build:** `torch.version.cuda == "11.4"`, `torch.cuda.is_available()`, cuDNN present.
3. **Tensor functionality:** a 1024×1024 float32 matmul on the GPU matches the CPU result (`allclose`, rtol 1e-3, atol 1e-2); the maximum absolute error is recorded.
4. **Memory allocation:** 256 MiB allocated on the GPU, written, read back and released; peak allocated must be at least 256 MiB.
5. **Sci stage only:** every `name==version` pin in the sci lock is installed at exactly that version, and `numpy scipy skimage nibabel SimpleITK torchio einops batchgenerators matplotlib sklearn pandas PIL tqdm` import (matplotlib with the Agg backend).

**Recorded** (JSON, embedded in the environment record): the imported torch version, CUDA build, cuDNN version, device name and compute capability, matmul error and time, total/free-before/free-after/peak memory in MiB, each check's result, and for sci the imported module versions. **Pass criteria:** every check passes, `pip check` is clean, and the record ends with `result: pass`. Attach the record (redacted) to the Stage 1A report.

## 7. Rollback

Nothing outside `/data/bowelnca` is modified, and each stage owns exactly one venv and one record:
```bash
rm -rf /data/bowelnca/venvs/xavier-jp516-py38-torch21-sci-v1     # sci only
rm -f  /data/bowelnca/reports/env-sci-<UTC>.txt
rm -rf /data/bowelnca/venvs/xavier-jp516-py38-torch21-core-v1    # core (only after sci is gone or kept deliberately)
rm -f  /data/bowelnca/reports/env-core-<UTC>.txt
```
A failed run already removes what it created. No system packages, PATH files, services, power modes or permissions need reverting. Review each path before deleting.

## 8. What remains unapproved

- D21 account separation (a prerequisite; the installer refuses without it).
- Running the installer at all: core (D22) and sci (D23), separately.
- Any privileged prerequisite (`python3.8-venv`, `libopenblas-dev`) if the preconditions show them missing.
- Building torchvision or any other package from source on the Xavier.
- Any GPU workload beyond the bounded smoke test.
