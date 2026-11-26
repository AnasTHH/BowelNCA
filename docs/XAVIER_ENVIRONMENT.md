# Xavier research environment: installation proposal and dependency assessment

**Status: PROPOSAL. NOT APPROVED. NOT EXECUTED.** Nothing in this document has been run on the Xavier.
Installation needs Dr. Iyad's recorded approval (`docs/DECISIONS.md`). It should happen only after the workspace verification (section 6) has passed and the sanitized inventory has been approved.
**Last updated:** 26 Nov 2026 · **Script:** [`scripts/proposed/install_xavier_env.sh`](../scripts/proposed/install_xavier_env.sh) · **Locks:** [`env/xavier/`](../env/xavier/)

## 1. Target, as observed on 26 Nov 2026

JetPack 5.1.6-b5 / L4T R35.6.4, Ubuntu 20.04.6, aarch64, Python 3.8.10 (`cp38`), CUDA 11.4.19 (`nvcc` 11.4.315, not on PATH), cuDNN 8.6.0.166, TensorRT 8.5.2.2. The root eMMC has 4.5 GiB free; the NVMe `/data` has 363 GiB free. Source: [`reports/evidence-draft/stage0_inventory_2026-11-26_sanitized.md`](../reports/evidence-draft/stage0_inventory_2026-11-26_sanitized.md).

This is NVIDIA's standard supported stack for the installed JetPack. The proposal stays on it. The system Python 3.9.5 is not used, because NVIDIA's JetPack 5 wheels are `cp38` only.

## 2. PyTorch wheel

| Field | Value | Verified how |
|---|---|---|
| Wheel | `torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` | NVIDIA compatibility matrix row "2.1.0a / 23.06 / JetPack 5.1.x" |
| URL | `https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` | HTTP 200, downloaded 25 Nov **and again 26 Nov 2026** |
| SHA-256 | `5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe` | Computed from both downloads (identical) |
| Size | 170,246,840 bytes compressed; 458,170,160 bytes (9,810 files) uncompressed | Measured |
| ABI / arch | `cp38-cp38-linux_aarch64`; `Requires-Python >=3.8.0` | Wheel tag and METADATA |
| Built for | CUDA 11.4 (`torch/version.py: cuda = '11.4'`) | Wheel contents |
| Runtime deps | filelock, fsspec, jinja2, networkx, sympy, typing-extensions | Wheel METADATA |

**Compatibility with JetPack 5.1.6 specifically: inferred, not yet tested on this device.**
- NVIDIA lists this wheel for "JetPack 5.1.x".
- NVIDIA staff confirmed it on JetPack 5.1.4 / AGX Xavier.
- NVIDIA states that JetPack 5.1.6 "packages the same compute stack as JetPack 5.1.5".
- The device's CUDA 11.4 and cuDNN 8.6 match the JetPack 5.1.x line the wheel targets.
- The smoke test (section 5) is the on-device verification.

## 3. Dependency compatibility and reproducibility

All locks were generated with `uv pip compile --python-version 3.8 --python-platform aarch64-manylinux_2_31 --only-binary :all: --generate-hashes`. glibc 2.31 matches Ubuntu 20.04. Every non-torch artefact was then re-downloaded for `cp38 / manylinux aarch64` with `pip download --require-hashes` to confirm that the hashes and wheels exist.

| Lock | Purpose | Contents |
|---|---|---|
| `requirements-xavier-bootstrap.lock` | Upgrade the venv's bundled pip 20.0.2 | `pip==24.3.1` (the last pip line supporting Python 3.8 is 25.0.x; 24.3.1 is conservative) |
| `requirements-xavier-core.lock` | Smoke-test runtime | torch (NVIDIA URL + SHA-256), `numpy==1.24.4` (last release for Python 3.8; NVIDIA's documented 1.26.1 requires Python >= 3.9), filelock 3.16.1, fsspec 2025.3.0, jinja2 3.1.6, MarkupSafe 2.1.5, mpmath 1.3.0, networkx 3.1, sympy 1.13.3, typing-extensions 4.13.2 |
| `requirements-xavier-sci.lock` | Scientific stack for Stage 1+ (**separate approval**) | scipy 1.10.1, scikit-image 0.21.0, nibabel 5.2.1, SimpleITK 2.4.1, torchio 0.20.1, einops 0.8.1, batchgenerators 0.25.6, matplotlib 3.7.5, scikit-learn 1.3.2, pandas 2.0.3, pillow 10.4.0, tqdm 4.70.1, plus pinned transitive deps (49 packages + torch) |

**ARM64 availability.** Every compiled package has a `cp38 manylinux2014/2_17 aarch64` binary wheel: numpy, scipy, scikit-image, scikit-learn, pandas, pillow, SimpleITK, PyWavelets, matplotlib, contourpy, kiwisolver, fonttools, MarkupSafe and wrapt. **No source compilation is required.** Every install uses `--only-binary=:all:`, so pip fails instead of compiling.

**Torch substitution guard.** torchio and monai declare `torch` as a dependency. If pip resolved them, it could install a CPU-only PyPI torch over NVIDIA's build. The installer prevents this:
- every install runs with `--no-deps --require-hashes` against fully pinned locks;
- torch itself is installed only from the locally verified NVIDIA wheel.

**Not included (deliberately).**

| Package | Status | Reason |
|---|---|---|
| torchvision | Excluded | NVIDIA ships no JetPack 5 wheel. Building v0.16.x from source on the Xavier needs separate authorization |
| monai | Not locked | Not used by upstream OctreeNCA. Pure-Python wheel; can be added later |
| aim, qtpy | Not locked | Upstream logging and GUI tools, not needed for research runs |

**Known limits.**
- The locks pin PyPI artefacts by hash, but they cannot guarantee that a package is free of runtime incompatibilities on Jetson. Stage 1 import tests verify that.
- Some packages (packaging 26.2, python-dateutil 3.0.0, tqdm 4.70.1) are recent releases that still declare Python 3.8 support. If a reviewer prefers older pins, regenerate the lock with explicit upper bounds.

## 4. Installation procedure (proposed)

**Preconditions.** The script checks each one read-only, and aborts on any failure:
1. Not root; `aarch64`; `/etc/nv_tegra_release` reports R35 revision 6.4.
2. `python3` is 3.8, and `ensurepip`/`venv` are importable. If not, a privileged `apt-get install python3.8-venv` would need **separate approval**.
3. `/usr/local/cuda/bin/nvcc` reports 11.4.
4. `libopenblas.so.0` is present. If not, a privileged `apt-get install libopenblas-dev` would need **separate approval**.
5. `/data/bowelnca` exists, is owned by the current user with mode 700, is **not** on the root filesystem, and has at least 10 GiB free.
6. The target venv does not already exist (the script never overwrites).
7. The lock files are present, and the torch hash in the core lock equals the pinned SHA-256.

**Commands (after approval; run as the project account, never with sudo):**
```bash
cd /data/bowelnca/workspace/BowelNCA            # a clean clone at the approved commit
git rev-parse HEAD                               # record; must equal the approved commit
bash scripts/proposed/install_xavier_env.sh --check-only     # read-only preconditions
BOWELNCA_INSTALL_APPROVAL=D<nn>-YYYY-MM-DD-<initials> \
  bash scripts/proposed/install_xavier_env.sh                # core + smoke test
# Scientific stack later, only with its own approval:
# BOWELNCA_INSTALL_APPROVAL=... BOWELNCA_SCI_APPROVAL=... \
#   bash scripts/proposed/install_xavier_env.sh --with-sci   (on a fresh venv)
```

**What the script does, in order.** It stops at the first error.
1. Validates the approval token format, then all preconditions.
2. Points every cache and temp location at the NVMe:
   - `TMPDIR=/data/bowelnca/tmp`
   - `PIP_CACHE_DIR`, `XDG_CACHE_HOME`, `TORCH_HOME`, `TORCH_EXTENSIONS_DIR`, `MPLCONFIGDIR` and `PYTHONPYCACHEPREFIX` all under `/data/bowelnca/cache/`
   - `PYTHONNOUSERSITE=1`
3. Downloads the wheel to a temp directory and runs `sha256sum --check --strict`. **On a mismatch it deletes the file and aborts before any venv exists.**
4. Creates `/data/bowelnca/venvs/xavier-jp516-py38-torch21`.
5. Runs hash-locked installs, all with `--require-hashes --no-deps --only-binary=:all:`:
   - pip bootstrap;
   - core dependencies;
   - torch from the verified local file;
   - `pip check`.
6. Writes `bin/bowelnca-env.sh` inside the venv and sources it from that venv's `activate`. It sets `CUDA_HOME=/usr/local/cuda`, prepends `$CUDA_HOME/bin` to PATH and `lib64` to LD_LIBRARY_PATH, and repeats the cache variables. **Nothing is written to `~/.bashrc` or system files.**
7. Runs the bounded smoke test (section 5) with a 300-second timeout.
8. Writes an environment record to `/data/bowelnca/reports/env-<UTC>.txt`: the approval reference, repo commit, lock hashes and `pip freeze`. It contains no usernames or hostnames.
9. If anything fails after step 4, the trap removes the partially created venv.

**Footprint (estimated from measured wheel sizes).**

| Item | Download | Installed |
|---|---|---|
| Core (torch + deps) | ~0.19 GB | ~0.55 GB |
| Scientific stack (optional) | ~0.17 GB | ~0.67 GB |
| pip cache (purgeable) | ≈ download size | - |
| Bytecode cache | - | ~0.1 GB |
| **Total on NVMe** | | **≈ 1.0 GB core-only; ≈ 2 GB with the scientific stack** |
| **On root eMMC** | | **≈ 0** by design (all caches and temp redirected) |

## 5. Verification (smoke test)

This is bounded, not a benchmark, and makes no power or clock changes:
1. `torch.version.cuda == "11.4"` and `torch.cuda.is_available()`. The script prints the device name, compute capability and cuDNN version.
2. **Tensor functionality:** a 1024×1024 float32 matmul on the GPU must match the CPU result (`allclose`, rtol 1e-3).
3. **Memory allocation:** allocate 256 MiB on the GPU, write and read it back, then release it. The script reports peak allocated memory and free memory before and after (`torch.cuda.mem_get_info`).

**Pass criteria:** all assertions pass, `pip check` is clean, and the environment record is written. Afterwards, attach the record (redacted) to the Stage 0 or Stage 1 report.

## 6. Workspace verification (before installation)

[`scripts/verify_workspace.sh`](../scripts/verify_workspace.sh) is non-destructive. It prints PASS/WARN/FAIL lines only, with no usernames, hostnames or device names.
```bash
bash scripts/verify_workspace.sh                 # read-only checks
bash scripts/verify_workspace.sh --write-test    # + one 1 MiB temp file in /data/bowelnca/tmp, verified and removed
```
It checks:
- the root and the nine subdirectories exist, are owned by the current user, and the root has mode 700;
- the workspace sits on the `/data` mount (ext4), not on the root filesystem;
- `/data` is not owned by the research account, so the device owner's ownership is unchanged;
- free space on the workspace and the root filesystem;
- cache growth under HOME;
- membership in privileged groups (docker, sudo, ...).

## 7. Rollback

Nothing outside `/data/bowelnca` is modified, so rollback is local and complete:
```bash
rm -rf /data/bowelnca/venvs/xavier-jp516-py38-torch21
rm -rf /data/bowelnca/cache/pip /data/bowelnca/cache/xdg /data/bowelnca/cache/torch \
       /data/bowelnca/cache/torch_extensions /data/bowelnca/cache/matplotlib /data/bowelnca/cache/pycache
rm -rf /data/bowelnca/tmp/torch-dl.*
```
No system packages, PATH files, services, power modes or permissions need reverting. Review each path before deleting.

## 8. What remains unapproved

- Running the installer at all (core or `--with-sci`).
- Any privileged prerequisite (`python3.8-venv`, `libopenblas-dev`) if the preconditions show them missing.
- Building torchvision or any other package from source on the Xavier.
- Any GPU workload beyond the bounded smoke test.
