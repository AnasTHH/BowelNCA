# Stage 0 - Xavier system and compatibility report

**Date/time (UTC):** 2026-11-25
**Device owner/reviewer:** Dr. Iyad Naim
**Engineer:** Claude Code (lead implementation agent), for Anas
**Git commit:** head of PR branch for issue #1 (see PR)
**Plan version:** `docs/DEVELOPMENT_PLAN_v1.2.md`
**Status:** **Draft, PARTIAL.** On-device inventory **not collected** (blocker B1). No stage approved by this report.

## 0. Summary for the reviewer

| Area | Result |
|---|---|
| Repository audit | Done. README claimed a `.gitignore` and CI that did not exist; both added. Public-visibility wording corrected. |
| Inventory script | Verified read-only, hardened, and guarded by CI tests (static deny-list, sandboxed run, 11-mutant test). |
| Xavier inventory | **Blocked (B1):** no authorized SSH route to the Xavier was available to the agent. Nothing executed on any device. |
| PyTorch stack (desk research) | NVIDIA's last JetPack 5 wheel: `torch 2.1.0a0+41361538.nv23.06`, cp38, CUDA 11.4, SHA-256 measured. Must be confirmed against the observed device. |
| Upstream compatibility | **Risk (B3):** upstream OctreeNCA targets Python 3.10 / CUDA 12.4; it fails at runtime on the Xavier's Python 3.8. |
| OctreeNCA license | **Blocker (B2):** no license at the pinned commit, so all rights reserved. Stage 1 cannot start until resolved. |
| Host changes / data / training | **None.** |

## 1. System facts (observed; sanitized)

**Not observed.** See blocker B1. The values below are what the plan *expects*; they are **not** measurements and must be replaced by the redacted inventory output.

| Item | Expected (from plan v1.2 / NVIDIA docs) | Observed | Evidence |
|---|---|---|---|
| Exact Jetson model | NVIDIA Jetson AGX Xavier (16 GB shared memory) | pending | inventory `== Jetson model` |
| Kernel / Jetson Linux / JetPack | L4T R35.6.4 / JetPack 5.1.6 (JetPack 5.1.7 / L4T 35.6.5 also exists, July 2026) | pending | `/etc/nv_tegra_release`, `dpkg-query nvidia-jetpack` |
| CPU ABI / Python version | aarch64 / Python 3.8.10 (`cp38`) | pending | inventory `== Python ...` |
| `nvcc` and CUDA runtime | CUDA 11.4 (JetPack 5.1.x) | pending | `nvcc --version`, `dpkg-query cuda-*` |
| PyTorch version / CUDA available | unknown | pending | inventory `== PyTorch/CUDA smoke` |
| Total/free RAM and swap | 16 GB shared CPU/GPU | pending | `free -h`, `swapon --show` |
| Disk free space | unknown | pending | `df -h / /home` |
| Current power mode | unknown (query only, never changed) | pending | `nvpmodel -q` |
| GPU/thermal status | unknown | pending | sysfs thermal zones |

## 2. NVIDIA PyTorch compatibility determination (desk research, not installed)

**Platform ceiling.** AGX Xavier is supported by the JetPack 5.1.x line (L4T R35.x, Ubuntu 20.04, CUDA 11.4, cuDNN 8.6, TensorRT 8.5.2, Python 3.8). JetPack 6 does not support Xavier, so CUDA 12 and NVIDIA's newer wheels are unavailable on this device.

- **Verified wheel and URL:** `https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl`
  - HTTP 200 on 25 Nov 2026; 170,246,840 bytes; Last-Modified 29 Jun 2023.
  - **SHA-256 `5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe`**. Measured by downloading to the agent's cloud sandbox and then deleting it. It was never sent to the Xavier.
  - Wheel `torch/version.py`: `__version__ = '2.1.0a0+41361538.nv23.06'`, `cuda = '11.4'`. METADATA: `Requires-Python >=3.8.0`, License BSD-3.
- **Wheel Python ABI and ARM64:** `cp38-cp38-linux_aarch64`. It only fits if the device's `python3` is 3.8.
- **Corresponding JetPack/L4T/CUDA:** NVIDIA's compatibility matrix lists PyTorch "2.1.0a" (commit 41361538) with wheel 23.06 for JetPack "5.1.x". NVIDIA staff stated (forum thread 316956, Dec 2024) that this wheel works on JetPack 5.1.4 on AGX Xavier, and (thread 316972) that prebuilt JetPack 5 wheels stop at v2.1. JetPack 5.1.6 "packages the same compute stack as JetPack 5.1.5", so the same wheel is expected to apply, **but this is inferred, not tested on 5.1.6/5.1.7.**
- **Alternative wheel:** `jp/v511/pytorch/torch-2.0.0+nv23.05-cp38-cp38-linux_aarch64.whl` (HTTP 200). A fallback only.
- **torchvision:** NVIDIA ships no JetPack 5 wheel. It must be built from source (v0.16.x matches torch 2.1). That build is a Stage 1 task needing approval.
- **Containers:** NVIDIA's matrix lists no container for the 2.1.0a JetPack 5 row. Community `dustynv/l4t-pytorch:r35.x` images exist but are **not verified here**. Docker presence is reported by the inventory.
- **NVIDIA documentation defect:** the install guide says `pip install numpy==1.26.1`. numpy 1.26 requires Python >= 3.9, so this **cannot** install on the cp38 wheel. Pin `numpy==1.24.4` instead.
- **Verified CUDA smoke result:** not available (B1).

### 2.1 Upstream OctreeNCA vs the Xavier toolchain (risk B3)

Inspected at upstream commit `70f7742` in a scratch checkout outside this repository. No code was copied here.

| Check | Finding |
|---|---|
| Upstream's stated environment | `conda create -n nca python=3.10.14`; CUDA extension example uses `CUDA_HOME=/usr/local/cuda-12.4`; dependencies "by trial-and-error" (no lockfile) |
| Python 3.8 grammar | All `.py` files parse with `ast.parse(..., feature_version=(3, 8))`. This is a parse check only, not proof of runtime compatibility. |
| Python 3.9+ **runtime** features | 90 dict-union (`a \| b`) lines in 18 files, including `train_prostate2.py` lines 26-30. There are also 14 PEP 585 annotations (`list[torch.Tensor]`, `tuple[...]`) that are evaluated at definition time. **`train_prostate2.py` will raise `TypeError` on Python 3.8 before training starts.** |
| PyTorch API level | `torch.compile` (>= 2.0) in some models; `train_prostate2.py` sets `performance.compile = False`. torch 2.1 is expected to be adequate but is untested. |
| Custom CUDA kernels | `nca_cuda3d` is an optional fast path (wrapped in `try/except`). Building it on Xavier needs nvcc and `TORCH_CUDA_ARCH_LIST=7.2`. Not needed for a first smoke test. |
| Dependencies | torchio, einops, batchgenerators, nibabel, scipy, scikit-image, matplotlib, aim, plus GUI-only qtpy. All must be pinned to Python 3.8-capable releases. |

**Options for the reviewer (ranked; none executed, and each is a scope decision for Dr. Iyad):**

1. **Run the Stage 1 upstream reproduction on a Python 3.10 / CUDA 12 machine** (a workstation or the future HPC), matching upstream's own environment. Use the Xavier with torch 2.1 / Python 3.8 only for this project's own code, written to be Python 3.8-compatible. This gives the cleanest reproduction with the least Jetson risk. It moves Stage 1 hardware, so it needs approval.
2. **Xavier with torch 2.1 cp38 plus a small local compatibility patch** (dict-union to `{**a, **b}`, `from __future__ import annotations`). This needs **modification rights** (B2) and still deviates from upstream's environment.
3. **Build Python 3.10 and PyTorch from source on Xavier** (e.g. via jetson-containers). Unofficial, multi-hour builds, high maintenance, and still CUDA 11.4. Not recommended.

### 2.2 Installation actions proposed (NOT executed; for human approval)

Run only after B1 is cleared and the inventory confirms aarch64, Python 3.8, CUDA 11.4 and JetPack 5.1.x. Everything installs into an unprivileged virtualenv under the developer's own account.

```bash
# 0. Privileged prerequisite. Needs Dr. Iyad's explicit approval, and only if the
#    inventory shows these packages missing:
#    sudo apt-get install -y libopenblas-dev python3-venv

# 1. User-level virtual environment (no sudo)
python3 -m venv ~/venvs/bowelnca-jp5
. ~/venvs/bowelnca-jp5/bin/activate
python -m pip install "pip==24.3.1"        # pip 25.1+ dropped Python 3.8
python -m pip install "numpy==1.24.4"      # NOT 1.26.1 (needs Python >= 3.9)

# 2. NVIDIA wheel, hash-verified before install
WHL=torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl
curl -fL -o "$WHL" "https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/$WHL"
echo "5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe  $WHL" | sha256sum -c -
python -m pip install "./$WHL"

# 3. Smoke test (seconds; no training, no benchmark, no power-mode change)
python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available()); x=torch.ones(2,device='cuda'); print((x*2).sum().item())"
```

Expected footprint: about 170 MB download and about 1 GB installed. Rollback is `rm -rf ~/venvs/bowelnca-jp5`. Nothing system-wide changes except the optional apt step. Lock the remaining dependencies with `pip-compile --generate-hashes` into `requirements-xavier.lock` in Stage 1.

## 3. Upstream OctreeNCA and license

- **Commit:** `70f774232305b76330a75edef9fddda8ec960cab` (single commit "init", 2025-08-13, only branch `master`).
- **Code paths:** the README names `src/models/Model_OctreeNCA_3d_patching2.py` (3D) and `..._2d_patching2.py`. `train_prostate2.py` exists, which confirms the plan's v1.1 pointers. Configs are composed from `configs/` and `src/utils/BaselineConfigs.py`. Storage paths must be set in `src/utils/ProjectConfiguration.py`, which upstream leaves as `<path>` placeholders.
- **License findings:** **no LICENSE file, no SPDX or copyright headers, no license in packaging metadata.** Default copyright applies (all rights reserved). There is also apparent unattributed TransUNet-derived code (Apache-2.0). The sibling lab repositories M3D-NCA and Med-NCA are MIT, so a license request looks promising. Full detail is in [`docs/UPSTREAM_LICENSE_REVIEW.md`](../docs/UPSTREAM_LICENSE_REVIEW.md).
- **Author contacts:** not yet contacted. This is an outward-facing action for the owner.
- **Redistribution permission status:** **UNRESOLVED. Blocks copying upstream code into this public repository and, in practice, Stage 1.**

## 4. Redacted evidence

- **Inventory log path and SHA-256:** none. The inventory was not run (B1).
- **Agent-side evidence (non-device):** the upstream clone, wheel HEAD/GET checks and NVIDIA documentation were all done in the agent's ephemeral cloud sandbox. Sources are listed in section 7.
- **Unexpected errors:** an early version of the new guard test (not the inventory script) executed a deliberately injected mutant after its static check had already failed. This happened in the cloud sandbox only. One mutant was `pip3 install torch`; it was stopped before completing, and `pip show torch` confirms nothing was installed. The guard now refuses to execute any script that fails the static check. `tests/test_inventory_guard_mutations.sh` proves this with an execution marker for 11 mutants.
- **Data transfer or training executed?** **No.**
- **Privileged changes executed?** **No.** No command was run on the Xavier or on any registered server.

## 5. Repository audit (performed in this PR)

| Finding | Action |
|---|---|
| README advertised "a safe Git ignore policy and a lightweight repository-policy CI check", but neither `.gitignore` nor `.github/workflows/` existed | Added `.gitignore` (data, imaging formats, weights, archives, unredacted logs, keys, upstream checkouts) and `.github/workflows/research-contract.yml` |
| README called this a "future research repository"/"package" and said public release was planned later | Rewritten: the source repo is public from day one; weights, results, upstream-derived code and DOI release stay gated. Recorded as decision D16, pending Dr. Iyad's acknowledgment |
| README told users to `tee` the inventory into the working tree | Now redirects to a git-ignored `*_inventory_local.log` |
| Plan Section 12 proposes GPU CI via a "private runner" | Not changed (approved plan). Added a governance warning: self-hosted runners must never serve `pull_request` workflows on a public repo |
| `scripts/jetson_inventory.sh` sourced (executed) `/etc/os-release` | Now parsed with `sed`. Added read-only `dpkg-query` for JetPack/CUDA/cuDNN/TensorRT, thermal sysfs, `swapon`/`lsblk`, cuDNN version and compute capability, a root-user warning, and redaction of `$HOME` in Python error strings |
| Branch naming | The plan suggests `stage0/jetson-env`. This PR uses the agent session's required branch name. The deviation is cosmetic and recorded here |

**Local checks run (all passed):** `bash -n` and `shellcheck -S warning` on all scripts; `scripts/check_repo_policy.sh`; `tests/test_inventory_readonly.sh`; `tests/test_inventory_guard_mutations.sh` (11/11 mutants rejected, none executed). The sandboxed run of the inventory on a non-Jetson x86 host exits 0 and prints no hostname or username.

## 6. Exit recommendation and open blockers

| ID | Blocker / risk | Owner | Proposed resolution |
|---|---|---|---|
| **B1** | No authorized access route to the Xavier for the agent. The registered remote hosts are unrelated cloud servers and were not probed | Anas / Dr. Iyad | Create the developer's own restricted account and SSH key on the Xavier (README step 1). Then either (a) a human runs `bash scripts/jetson_inventory.sh > stage0_inventory_local.log 2>&1`, redacts it and attaches it to this PR, or (b) the Xavier is registered for the agent with an **allowlist** policy permitting only that command |
| **B2** | OctreeNCA has no license | Anas, then Dr. Iyad | Email the authors requesting an MIT license or written grant (`docs/UPSTREAM_LICENSE_REVIEW.md`). Set a deadline (proposed 3 weeks) after which a clean-room re-implementation is decided |
| **B3** | Upstream needs Python >= 3.9 at runtime; Xavier is capped at Python 3.8 / CUDA 11.4 | Dr. Iyad | Choose an option in section 2.1 (recommended: option 1) |
| R1 | 16 GB shared CPU/GPU memory; thermal and power behaviour unknown | - | Measure in Stage 3; never change power mode without approval |
| R2 | JetPack 5 is end-of-line for new PyTorch; torch 2.1 is a 2023 build | - | Accept for exploration; confirmatory work runs on HPC anyway |

- **Is the environment suitable for Stage 1 smoke testing?** **Undetermined** until B1 is cleared. Even then, Stage 1 is gated by B2, and its location depends on B3.
- **Required disk/OS compatibility fixes (proposals only):** section 2.2. Optional `libopenblas-dev`/`python3-venv` via apt needs approval.
- **License gate:** open (D12).
- **Safety/power/cooling risks:** unknown; the inventory reports them read-only.

### Stage 0 acceptance criteria (from issue #1)

| Criterion | Status |
|---|---|
| Device model, architecture, Jetson Linux release captured | **Pending B1** |
| Python, CUDA, PyTorch, `torch.cuda.is_available()` captured | **Pending B1** (script handles absent-import cases) |
| Memory/storage, cooling/power noted | **Pending B1** |
| NVIDIA wheel/container checked against JetPack and ABI, not installed | **Done (desk)**; recheck against observed values |
| OctreeNCA commit identified, license recorded separately | **Done**; license **unresolved** |
| Install commands proposed only | **Done** (section 2.2) |
| `reports/stage_0.md` with evidence and reproducibility notes | **Done (partial)** |
| Redacted evidence, zero raw scans, zero privileged changes | **Done** |
| Next-stage gate explicitly pending | **Yes. Stage 1 NOT authorized** |

- **Reviewer sign-off (name, date, decision):** _pending - Dr. Iyad Naim_

## 7. Sources

- NVIDIA, *Installing PyTorch for Jetson Platform*: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform/index.html
- NVIDIA, *PyTorch for Jetson release notes / compatibility matrix*: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform-release-notes/pytorch-jetson-rel.html
- NVIDIA forum, wheel on AGX Xavier with JetPack 5.1.4: https://forums.developer.nvidia.com/t/cannot-install-pytorch-on-agx-xavier-with-jetpack-5-1-4-not-supported-wheel-on-this-platform/316956
- NVIDIA forum, PyTorch for L4T 35.6: https://forums.developer.nvidia.com/t/request-build-script-for-pytorch-or-up-to-date-pytorh-binary-release-supporting-jetson-boards-running-l4t35-6-ubuntu20-04/316972
- JetPack 5.1.6 / L4T 35.6.4 announcement: https://forums.developer.nvidia.com/t/jetpack-5-1-6-l4t-35-6-4-is-now-live/359614
- JetPack 5.1.7 / L4T 35.6.5 announcement: https://forums.developer.nvidia.com/t/jetpack-5-1-7-l4t-35-6-5-is-now-live/378094
- Upstream: https://github.com/MECLabTUDA/OctreeNCA @ `70f774232305b76330a75edef9fddda8ec960cab`; arXiv:2508.06993
