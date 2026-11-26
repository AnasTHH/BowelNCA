# Stage 0 - Xavier system and compatibility report

**Date (UTC):** 2026-11-26 (revision 4; first drafted 2026-11-25)
**Device owner/reviewer:** Dr. Iyad Naim
**Engineer:** Claude Code (lead implementation agent), for Anas
**Git commit:** head of PR #2 (see PR for the exact SHA and CI run)
**Plan version:** `docs/DEVELOPMENT_PLAN_v1.2.md`
**Status:** **Draft - Stage 0 INCOMPLETE.** The hardware and software inventory has been collected (by the owner) and is pending human redaction approval. Workspace verification, environment installation and the GPU smoke test are **outstanding and unapproved**. No stage is approved by this report.

## 0. Summary for the reviewer

| Area | State | Evidence |
|---|---|---|
| Xavier access | **Done (human only).** Private VPN with a direct peer connection; OpenSSH with a dedicated ED25519 key; dedicated project account with password-protected sudo granted by the device administrator. The agent has **no** access | Owner report, 26 Nov |
| Hardware/software inventory | **Collected** 2026-11-26T07:20:16Z with the reviewed script (commit `e26e3db`, blob `16b7cb9f`, re-verified). Sanitized summary **pending human redaction approval** | [`reports/evidence-draft/stage0_inventory_2026-11-26_sanitized.md`](evidence-draft/stage0_inventory_2026-11-26_sanitized.md) |
| Storage | **Verified (owner-reported).** Root eMMC 4.5 GiB free (83% used); existing NVMe `/data` 363 GiB free. No storage purchase, repartitioning or OS migration needed | Section 1.3 |
| Research workspace | **Created** at `/data/bowelnca` (mode 700). Write test and final ownership/mount check **pending** | Section 1.4; `scripts/verify_workspace.sh` |
| PyTorch wheel | **Re-verified 26 Nov:** NVIDIA `torch 2.1.0a0+41361538.nv23.06`, cp38, CUDA 11.4, SHA-256 unchanged. Matches the observed JetPack 5.1.6 / Python 3.8.10 / CUDA 11.4 / cuDNN 8.6. Compatibility on 5.1.6 is **inferred until the smoke test runs** | Section 2 |
| Dependencies | **Hash-locked** for cp38/aarch64: bootstrap, core and scientific locks. All binary wheels; no compilation needed | `env/xavier/`, `docs/XAVIER_ENVIRONMENT.md` |
| Installation | **Proposal ready, NOT approved, NOT executed.** Fail-closed script with CI regression tests | `scripts/proposed/install_xavier_env.sh` |
| GPU / CUDA functionality | **Not tested.** PyTorch is not installed | - |
| OctreeNCA license | **Unresolved (B2).** Inquiry sent 25 Nov 2026, awaiting response; decision point 16 Dec 2026 (D17) | `docs/UPSTREAM_LICENSE_REVIEW.md` |
| Security | Assessment and account-separation proposal written; **no changes made** | `docs/XAVIER_ACCESS_AND_SECURITY.md` |
| Host changes by the agent / data / training | **None** | - |

## 1. System facts (observed, sanitized)

All values below are **owner-reported results** of `scripts/jetson_inventory.sh` (commit `e26e3db9824613d37a7577d4c87d6f213408ee83`, Git blob `16b7cb9feb78a12cf5ef31b852bb01a1ad97b81a`; the agent re-computed the blob hash from the repository and it matches). The owner ran the script manually on 2026-11-26 at 07:20:16 UTC, unprivileged. The agent did not see the raw log, which stays private.

### 1.1 Hardware

| Item | Observed |
|---|---|
| Exact Jetson model | NVIDIA Jetson AGX Xavier, Tegra194, aarch64 |
| Memory | 16 GB shared CPU/GPU class; 14 GiB Linux-visible; 13 GiB available at measurement |
| Swap | 7.3 GiB zram (compressed RAM) |
| Power mode (query only) | MAXN. The unprivileged query cannot read some kernel-level EMC parameters |
| Thermal | CPU 39.5 °C, GPU 39.5 °C at measurement |

### 1.2 OS, NVIDIA stack and Python

| Item | Observed |
|---|---|
| OS / kernel | Ubuntu 20.04.6 LTS / 5.10.216-tegra |
| L4T / JetPack | R35.6.4 / 5.1.6-b5 |
| CUDA | Toolkit package 11.4.19-1; `nvcc` 11.4.315 at `/usr/local/cuda/bin/nvcc`, **not on PATH** |
| cuDNN / TensorRT | 8.6.0.166 / 8.5.2.2 |
| Tools present (not executed) | tegrastats, jtop, jetson_clocks, Docker |
| Python | Default 3.8.10 (`cp38`); additional 3.9.5; pip 20.0.2; NumPy 1.17.4 |
| PyTorch / torchvision | **Not importable** under the default Python |
| `torch.cuda.is_available()` | **Not testable** (no PyTorch) |

### 1.3 Storage

| Filesystem | Capacity | Used | Free | Use | Role |
|---|---|---|---|---|---|
| Root, internal eMMC | 28 GiB | 22 GiB | 4.5 GiB | 83% | OS only. **No research installs or caches** |
| `/data`, existing 500 GB NVMe, ext4 | 458 GiB | 72 GiB | 363 GiB | 17% | Research workspace, venvs, caches, temp, future approved artefacts |

The existing NVMe is sufficient, so no storage expansion, repartitioning or OS migration is needed for initial development. `/data` belongs to the device owner, and its ownership and permissions stay unchanged.

### 1.4 Workspace (owner-created, 26 Nov)

`/data/bowelnca/` was created by the owner with the administrator's grant (`install -d -m 700`, owned by the project account). It has the subdirectories `workspace venvs datasets derived checkpoints experiments reports cache tmp`. Both commands returned without errors.

**Pending:** run [`scripts/verify_workspace.sh --write-test`](../scripts/verify_workspace.sh). It is non-destructive: it writes one 1 MiB temp file in `tmp/`, verifies it and removes it. It confirms ownership, mode 700, the `/data` ext4 mount, separation from the root filesystem, unchanged `/data` ownership, free space, cache leakage under HOME and risky group membership. It prints no usernames, hostnames or device names.

### 1.5 Observations (no action authorized)

- The SSH client reports that no post-quantum key exchange was negotiated. Authentication works.
- Some EMC parameters are unreadable without privileges.
- The root filesystem is nearly full. The installer refuses to install onto it, and redirects every cache (`TMPDIR`, `PIP_CACHE_DIR`, `XDG_CACHE_HOME`, `TORCH_HOME`, `TORCH_EXTENSIONS_DIR`, `MPLCONFIGDIR`, `PYTHONPYCACHEPREFIX`) to `/data/bowelnca`.

## 2. NVIDIA PyTorch compatibility determination

| Field | Value |
|---|---|
| Wheel | `torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` |
| URL | `https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` |
| SHA-256 | `5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe`. **Downloaded and hashed 25 Nov and 26 Nov 2026 (identical)** in the agent's cloud sandbox, then deleted |
| Size | 170,246,840 bytes compressed; 458,170,160 bytes uncompressed |
| ABI | `cp38` aarch64, matching the observed default Python 3.8.10 |
| CUDA | Built for 11.4, matching the observed toolkit 11.4.19 / nvcc 11.4.315 |
| JetPack | NVIDIA matrix row "5.1.x". Staff-confirmed on 5.1.4 / AGX Xavier. 5.1.6 "packages the same compute stack as 5.1.5". **On-device compatibility with 5.1.6-b5 remains unverified until the smoke test** |
| NumPy | `1.24.4`. NVIDIA's documented `1.26.1` requires Python >= 3.9 |
| torchvision | No JetPack 5 wheel; source build excluded pending authorization |

The observed stack is NVIDIA's standard supported environment for JetPack 5.1.x. Python 3.9.5 exists on the device, but it is not used because the JetPack 5 wheels are cp38 only.

### 2.1 Upstream OctreeNCA vs this toolchain (risk B3)

Upstream (`70f7742`, inspected outside this repository) targets Python 3.10.14 and CUDA 12.4. It uses dict-union (`a | b`) in 18 files, including `train_prostate2.py`, and PEP 585 annotations, so it fails at runtime on Python 3.8. **Recommended (D18, supported by Anas, pending Dr. Iyad):**
- Reproduce upstream in a modern Python 3.10 / CUDA 12 reference environment.
- Keep the Xavier on the standard JetPack 5.1.x stack for this project's own Python-3.8-compatible code.

The alternatives (a local compatibility patch, which needs modification rights; or a non-standard Python/PyTorch build on the Xavier) are not recommended.

## 3. Proposed environment installation (NOT approved, NOT executed)

Full procedure: [`docs/XAVIER_ENVIRONMENT.md`](../docs/XAVIER_ENVIRONMENT.md).
- **Location:** venv at `/data/bowelnca/venvs/xavier-jp516-py38-torch21`, created with the system Python 3.8.
- **Fail-closed:**
  - `set -euo pipefail`;
  - approval token required;
  - read-only preconditions (not root, aarch64, L4T R35.6.4, Python 3.8 with venv, nvcc 11.4, libopenblas present, workspace owned and mode 700 on a non-root filesystem with at least 10 GiB free, no existing venv, lock/hash consistency);
  - wheel `sha256sum --check --strict` **before** any venv exists;
  - every pip install uses `--require-hashes --no-deps --only-binary=:all:`;
  - the trap removes a partial venv on failure.
- **Locks:**
  - `env/xavier/requirements-xavier-bootstrap.lock` (pip 24.3.1);
  - `requirements-xavier-core.lock` (torch + numpy 1.24.4 + 8 deps);
  - `requirements-xavier-sci.lock` (49 packages + torch; separate approval).
  - All were generated for cp38 / manylinux_2_31 aarch64, and the non-torch wheels were re-downloaded under `--require-hashes` to confirm they exist.
- **CUDA scoping:** `CUDA_HOME`, `PATH` and `LD_LIBRARY_PATH` are set only inside the venv (`bin/bowelnca-env.sh`, sourced by `activate`). No `~/.bashrc` or system changes.
- **Smoke test** (bounded, about seconds; not a benchmark):
  - torch CUDA build 11.4 and `cuda.is_available()`;
  - GPU vs CPU 1024² matmul agreement;
  - 256 MiB GPU allocation write, readback and release, reporting peak and free memory.
- **Footprint:** about 1.0 GB on NVMe for core, about 2 GB with the scientific stack, and about 0 on eMMC.
- **Rollback:** delete the venv and the cache directories under `/data/bowelnca`. Nothing else changes.
- **Possible privileged prerequisites:** if the preconditions find `python3.8-venv` or `libopenblas-dev` missing, the script aborts. Installing those requires separate approval.

## 4. Dependency compatibility and reproducibility assessment

- **Availability:** every compiled dependency has a cp38 manylinux2014 aarch64 wheel. This covers numpy, scipy 1.10.1, scikit-image 0.21.0, scikit-learn 1.3.2, pandas 2.0.3, pillow, SimpleITK 2.4.1, matplotlib 3.7.5, PyWavelets and others. **No compilation on the Xavier is needed**, and `--only-binary=:all:` enforces that.
- **Python 3.8 ceiling:** these are the last Python 3.8 lines of numpy (1.24), scipy (1.10), scikit-image (0.21), pandas (2.0) and matplotlib (3.7). New research code must stay Python 3.8-compatible (D18).
- **Torch substitution risk:** torchio declares `torch`, so a resolver could pull a CPU-only PyPI torch. This is prevented by `--no-deps` with fully pinned locks, and by installing torch only from the verified NVIDIA file.
- **Reproducibility:**
  - Locks pin exact versions and SHA-256 for every artefact, and the regeneration command is recorded in each `.in` file.
  - The installer writes an environment record (approval reference, repo commit, lock hashes, `pip freeze`).
  - Remaining non-determinism: system libraries from JetPack (CUDA, cuDNN, libopenblas) are pinned by the observed JetPack version, not by these locks.
- **Not yet verified:** on-device import and runtime behaviour of the scientific stack. That is Stage 1 work, after approval.

## 5. Security and data governance (summary)

Full assessment: [`docs/XAVIER_ACCESS_AND_SECURITY.md`](../docs/XAVIER_ACCESS_AND_SECURITY.md).
- **Main risk (S1):** the research account is a sudoer. Proposed before any automated or agent execution:
  - a separate **unprivileged execution account**, with no sudo and not in `docker` (root-equivalent);
  - the human admin role keeps password-protected sudo;
  - **no `NOPASSWD`**.
- **Dataset isolation layout** for Stage 2:
  - development data read-only to the execution account;
  - the locked test cohort and alternate labels never on the device;
  - manifest-checked transfers.
- **Repository policy:** the check now also scans draft and approved evidence for private/VPN IPv4, `*.ts.net`, private IPv6, SSH key material, MACs, emails, home paths and device paths.
- **Not published:** VPN details, hostnames, personal usernames, keys, raw logs and private correspondence.

## 6. Upstream OctreeNCA and license

- **Commit:** `70f774232305b76330a75edef9fddda8ec960cab`. No LICENSE file, headers or packaging license, so all rights are reserved.
- **Inquiry:** sent 25 Nov 2026, awaiting response. Correspondence is private.
- **Decision point:** 16 Dec 2026 (D17): license or grant in hand, extend the wait, or authorize a clean-room implementation.
- **No upstream implementation is authorized for redistribution or adaptation.**

Details: [`docs/UPSTREAM_LICENSE_REVIEW.md`](../docs/UPSTREAM_LICENSE_REVIEW.md).

## 7. Evidence and execution record

| Item | State |
|---|---|
| Inventory evidence | Sanitized transcription in `reports/evidence-draft/` (header `REDACTION-STATUS: PENDING-HUMAN-APPROVAL`). After approval, move it to `reports/evidence/` with `REDACTED-BY-HUMAN: <initials> <date>`; CI enforces both forms |
| Raw log | Kept privately by the owner; not committed |
| Data transfer / training | **None** |
| Privileged changes | **None by the agent.** The owner created the workspace manually with the administrator's grant (recorded as D20) |
| Agent actions on any device | **None** |
| Earlier incident (25 Nov) | A test-design bug ran an injected mutant in the agent's cloud sandbox only. Fixed; covered by the mutation test (section 9) |

## 8. Blockers, outstanding work and approvals

| ID | Item | Status | Needed from |
|---|---|---|---|
| ~~B1~~ | Access and inventory | **Resolved for humans:** SSH works and the inventory is collected. The agent intentionally has no access | - |
| E1 | Human redaction approval of the sanitized evidence | Pending | Anas (initials and date) |
| W1 | Workspace write test and final mount/ownership verification | Pending; script ready | Anas (manual run, non-destructive) |
| I1 | Approval to install the core environment (`--check-only` first, then install) | **Not approved** | Dr. Iyad (decision row) |
| I2 | Approval of privileged prerequisites, only if `--check-only` reports `python3.8-venv` or `libopenblas` missing | Not requested yet | Dr. Iyad |
| G1 | GPU/CUDA smoke test (part of I1) | **Not run** | Follows I1 |
| B2 | OctreeNCA license | Inquiry sent, awaiting response; decision 16 Dec 2026 (D17) | Authors, then Anas and Dr. Iyad |
| B3 | Upstream Python 3.10 vs Xavier Python 3.8 | D18 proposed (separate environments) | Dr. Iyad |
| S1 | Account separation before any automation | Proposed (D21) | Dr. Iyad (device owner) |
| P | Parallel architecture-independent work, P1, P2, P4, P7, P8 (synthetic data, CPU only) | D19 proposed; **not started** | Dr. Iyad (scientific approval) |
| M | Merge PR #2 (squash) | Technical GO from Anas | Dr. Iyad authorization |

### Stage 0 acceptance criteria (issue #1)

| Criterion | Status |
|---|---|
| Device model, architecture, Jetson Linux release captured | **Done** (observed; evidence pending approval E1) |
| Python, CUDA, PyTorch, `torch.cuda.is_available()` captured, including absent-import cases | **Done:** PyTorch absent, so CUDA availability is not testable until I1/G1 |
| Memory/storage, cooling/power noted | **Done** |
| NVIDIA wheel checked against the observed JetPack and ABI, not installed | **Done** (on-device confirmation deferred to G1) |
| OctreeNCA commit identified, license recorded separately | **Done**; license **unresolved** |
| Installation commands proposed only | **Done** (fail-closed script + locks), not executed |
| `reports/stage_0.md` with evidence and reproducibility notes | **Done** (this revision) |
| Redacted evidence, zero raw scans, zero privileged changes by the agent | **Draft done; human approval pending (E1)** |
| Workspace verified | **Pending (W1)** |
| Next-stage gate explicitly pending | **Yes. Stage 1 NOT authorized** |

**Stage 0 is not complete.** Closing it needs E1 and W1, a decision on I1/G1 (whether the smoke test belongs in Stage 0 or opens Stage 1), and Dr. Iyad's sign-off.

- **Reviewer sign-off (name, date, decision):** _pending - Dr. Iyad Naim_

## 9. Tests run for this revision (repository-side only)

All pass locally and in CI:
- `bash -n` and `shellcheck -S warning` on all scripts;
- `scripts/check_repo_policy.sh`;
- `tests/test_repo_policy.sh` (30 synthetic violations rejected, clean tree accepted);
- `tests/test_inventory_readonly.sh`;
- `tests/test_inventory_guard_mutations.sh` (13 mutants rejected, none executed);
- `tests/test_proposed_scripts.sh`: the installer refuses without approval and with a malformed token, aborts at preconditions on a non-Jetson host, `--check-only` never downloads, a checksum mismatch aborts and deletes the file, and the lock and installer hashes agree; the workspace verifier passes a correct synthetic workspace, rejects mode 755 and missing subdirectories, leaves no files, and prints no identifiers.

These are regression checks, not security guarantees.

## 10. History

- **Round 1 (25 Nov, `f0f2eef`):** six requested changes, all addressed in `878197a`:
  - guard wording;
  - output minimization;
  - fail-closed install;
  - stronger policy;
  - removal of the unverified third-party claim;
  - Python 3.8 framing.
- **Round 2 (25 Nov, `878197a`):** technical GO for the preparatory changes, subject to Dr. Iyad's merge authorization (squash). Status updates in `e26e3db`.
- **26 Nov:** owner completed access, inventory and workspace. This revision records the observed values and adds the locks, the installer proposal, the workspace verifier and the security assessment.

## 11. Sources

- NVIDIA, *Installing PyTorch for Jetson Platform*: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform/index.html
- NVIDIA, *PyTorch for Jetson compatibility matrix*: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform-release-notes/pytorch-jetson-rel.html
- NVIDIA forum, wheel on AGX Xavier / JetPack 5.1.4: https://forums.developer.nvidia.com/t/cannot-install-pytorch-on-agx-xavier-with-jetpack-5-1-4-not-supported-wheel-on-this-platform/316956
- NVIDIA forum, PyTorch for L4T 35.6: https://forums.developer.nvidia.com/t/request-build-script-for-pytorch-or-up-to-date-pytorh-binary-release-supporting-jetson-boards-running-l4t35-6-ubuntu20-04/316972
- JetPack 5.1.6 / L4T 35.6.4 announcement: https://forums.developer.nvidia.com/t/jetpack-5-1-6-l4t-35-6-4-is-now-live/359614
- Upstream: https://github.com/MECLabTUDA/OctreeNCA @ `70f774232305b76330a75edef9fddda8ec960cab`; arXiv:2508.06993
