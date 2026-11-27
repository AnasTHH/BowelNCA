# Stage 0 - Xavier system and compatibility report

**Date (UTC):** 2026-11-26 (revision 10, documentation only: Stage 0, D19 and D28 approved by Dr. Iyad; first drafted 2026-11-25)
**Device owner/reviewer:** Dr. Iyad Naim
**Engineer:** Claude Code (lead implementation agent), for Anas
**Git commit:** head of PR #2 (see PR for the exact SHA and CI run)
**Plan version:** `docs/DEVELOPMENT_PLAN_v1.2.md`
**Status:** **Stage 0 approved by Dr. Iyad on 26 Nov 2026 (20:16 UTC)** (as reported by the project owner). Engineering preparation was accepted at `18689161acd47ded650cc76f83fd7d5232fc1260` and merged as `e68360b`. The owner attested the redaction of the sanitized inventory (E1), published in [`reports/evidence/`](evidence/stage0_inventory_2026-11-26.md). Workspace verification passed in the interim layout (W1). Installation and the GPU smoke test belong to **Stage 1A** (D24, approved) and are **not executed**; Stage 1A execution still needs D21, W2 and a recorded D22 reference.

## 0. Summary for the reviewer

| Area | State | Evidence |
|---|---|---|
| Xavier access | **Done (human only).** Private VPN with a direct peer connection; OpenSSH with a dedicated ED25519 key; dedicated project account with password-protected sudo granted by the device administrator. The agent has **no** access | Owner report, 26 Nov |
| Hardware/software inventory | **Collected** 2026-11-26T07:20:16Z with the reviewed script (commit `e26e3db`, blob `16b7cb9f`, re-verified). The sanitized summary was compared against the owner's terminal output by the round 3 reviewer: consistent, no sensitive identifiers. **Redaction attested by the owner (AN, 2026-11-26); E1 accepted and published** | Section 1 (values); [`reports/evidence/stage0_inventory_2026-11-26.md`](evidence/stage0_inventory_2026-11-26.md) |
| Storage | **Verified (owner-reported).** Root eMMC 4.5 GiB free (83% used); existing NVMe `/data` 363 GiB free. No storage purchase, repartitioning or OS migration needed | Section 1.3 |
| Research workspace | **Verified in the interim layout (W1 PASSED,** 2026-11-26T08:40:33Z, commit `73dbac6`, 0 FAIL, 2 expected WARN). The administrator-owned separated layout (D21) is proposed and needs its own verification | Section 1.4; `scripts/verify_workspace.sh` |
| PyTorch wheel | **Candidate compatible build, pending on-device validation.** NVIDIA `torch 2.1.0a0+41361538.nv23.06`, cp38, CUDA 11.4, SHA-256 re-verified 26 Nov and unchanged. Its declared targets match the observed JetPack 5.1.6 / Python 3.8.10 / CUDA 11.4 / cuDNN 8.6; it has not been installed or run on the device | Section 2 |
| Dependencies | **Hash-locked** for cp38/aarch64. A machine-readable manifest records all 51 actual wheels (filename, version, tags, Requires-Python, SHA-256). All binary wheels; no compilation needed | `env/xavier/dependency-manifest.json`, `docs/XAVIER_ENVIRONMENT.md` |
| Installation | **Proposal accepted by engineering review at `1868916`; NOT approved for execution, NOT executed.** Separate versioned core and sci venvs, containment and lock checks, exact rollback; 122 CI regression checks. Proposed as Stage 1A (D22, D23, D24); requires D21 first | `scripts/proposed/install_xavier_env.sh` |
| GPU / CUDA functionality | **Not tested.** PyTorch is not installed | - |
| OctreeNCA license | **Unresolved (B2).** Inquiry sent 25 Nov 2026, awaiting response; decision point 16 Dec 2026 (D17) | `docs/UPSTREAM_LICENSE_REVIEW.md` |
| Security | **No further account changes have been made following the initial authorized access setup.** Account separation (D21) with directory layout and a migration procedure that preserves current access is proposed, not executed | `docs/XAVIER_ACCESS_AND_SECURITY.md` |
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

**W1 PASSED (interim layout).** The owner ran `bash scripts/verify_workspace.sh --layout interim --write-test` at commit `73dbac6f2699d6c313f7536adf60fade326218ec` on 2026-11-26T08:40:33Z. Before the run, the owner normalized the workspace root and all nine subdirectories to mode 0700. Results (owner-reported):

| Check | Result |
|---|---|
| FAIL / WARN | **0 FAIL, 2 WARN** |
| Ownership, mode, canonical paths | Verified |
| Mount / filesystem | `/data`, ext4; not the root filesystem; no nested mounts |
| Free space | Workspace 389,725,986,816 bytes; root filesystem 4,813,811,712 bytes |
| GPU groups | `video` and `render` membership present |
| Write test | Exactly 1,048,576 bytes written, fsynced, checksum-verified and removed |
| Expected WARN 1 | Research account still in `sudo` (pending D21) |
| Expected WARN 2 | `datasets/` still research-writable (pending D21) |

This verifies the **interim** layout only. The **separated** layout (D21) is a distinct, later step: `verify_workspace.sh --layout separated` after the migration, where both warnings become failures if unresolved.

### 1.5 Observations (no action authorized)

- The SSH client reports that no post-quantum key exchange was negotiated. Authentication works.
- Some EMC parameters are unreadable without privileges.
- The root filesystem is nearly full. The installer refuses to install onto it, uses no pip cache, puts `TMPDIR` on the NVMe and keeps `TORCH_HOME`, `TORCH_EXTENSIONS_DIR`, `MPLCONFIGDIR` and `XDG_CACHE_HOME` inside the venv.

## 2. NVIDIA PyTorch compatibility determination

| Field | Value |
|---|---|
| Wheel | `torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` |
| URL | `https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl` |
| SHA-256 | `5112e2ef5051f1003ae2ffb545ae596377df66979d62a954d774f18009064dbe`. **Downloaded and hashed 25 Nov and twice on 26 Nov 2026 (identical)** in the agent's cloud sandbox, never installed |
| Size | 170,246,840 bytes compressed; 458,170,160 bytes uncompressed |
| ABI | `cp38` aarch64, matching the observed default Python 3.8.10 |
| CUDA | Built for 11.4, matching the observed toolkit 11.4.19 / nvcc 11.4.315 |
| JetPack | NVIDIA matrix row "5.1.x". Staff-confirmed on 5.1.4 / AGX Xavier. 5.1.6 "packages the same compute stack as 5.1.5". **On-device compatibility with 5.1.6-b5 remains unverified until the smoke test** |
| NumPy | `1.24.4`. NVIDIA's documented `1.26.1` requires Python >= 3.9 |
| torchvision | No JetPack 5 wheel; source build excluded pending authorization |

**Determination:** this wheel is a **candidate compatible build, pending on-device validation** (the Stage 1A smoke test). The observed stack is NVIDIA's standard supported environment for JetPack 5.1.x. Python 3.9.5 exists on the device, but it is not used because the JetPack 5 wheels are cp38 only.

### 2.1 Upstream OctreeNCA vs this toolchain (risk B3)

Upstream (`70f7742`, inspected outside this repository) targets Python 3.10.14 and CUDA 12.4. It uses dict-union (`a | b`) in 18 files, including `train_prostate2.py`, and PEP 585 annotations, so it fails at runtime on Python 3.8. **Recommended (D18, supported by Anas, pending Dr. Iyad):**
- Reproduce upstream in a modern Python 3.10 / CUDA 12 reference environment.
- Keep the Xavier on the standard JetPack 5.1.x stack for this project's own Python-3.8-compatible code.

The alternatives (a local compatibility patch, which needs modification rights; or a non-standard Python/PyTorch build on the Xavier) are not recommended.

## 3. Proposed environment installation (NOT approved, NOT executed; proposed Stage 1A)

Full procedure: [`docs/XAVIER_ENVIRONMENT.md`](../docs/XAVIER_ENVIRONMENT.md). Revised after review round 3:
- **Lifecycle (R3-04):** two distinct, versioned venvs: `xavier-jp516-py38-torch21-core-v1` (D22) and `xavier-jp516-py38-torch21-sci-v1` (D23, core + scientific stack). The sci stage needs its own approval **and** a passing core record made with the recorded core approval; both references go in the sci record. Rolling back sci never touches core.
- **Approval boundary (R3-05):** approval references are an accidental-execution guard, not authentication. The script also requires `BOWELNCA_REVIEWED_COMMIT` to equal `HEAD` of a clean checkout; a human confirms the decision record and commit before running.
- **Containment (R3-02):** the separated layout (D21) is required; every destination must be canonical (no symlinks), inside `/data/bowelnca`, on its filesystem and research-owned; nested mounts are refused; an exclusive `flock` prevents concurrent runs; on failure the trap removes **only the paths this invocation created**.
- **Precondition reliability (R3-07):** command output is captured before matching (no SIGPIPE false failures under `pipefail`); free space is checked in bytes from `statfs`.
- **Fail-closed:** wheel `sha256sum --check --strict` **before** any venv exists; every pip step `--require-hashes --no-deps --only-binary=:all:` and explicitly checked.
- **Scoped CUDA and smoke test (R3-06):** the smoke test runs through the venv's `activate` in a clean environment, the same environment research runs will use, and records the imported torch version, CUDA build, cuDNN version, device capability and memory results. The sci stage adds pinned-version and import checks for the scientific stack.
- **Installed-version check (final review):** after installation, `verify_installed_versions.py` reads every installed distribution with `importlib.metadata` and compares it, PEP 440 normalized, with `env/xavier/dependency-manifest.json` (bootstrap + the stage's lock). `pip freeze` is recorded as evidence only, because a wheel installed from a local file appears as a PEP 610 direct reference.
- **Round 4 (R4-01 to R4-03):** the lock file is validated before opening (symlinks, dangling symlinks, other file types, wrong owner and extra hard links refused); the record is created exclusively and a dangling symlink there is refused; failure to read the mount table fails closed; venv creation and pip run in a controlled environment (`env -i`, `python -I`, `PIP_CONFIG_FILE=/dev/null`); every hook write and all evidence (lock hashes, smoke JSON, `pip freeze`) must succeed before `result: pass`; failed runs keep private diagnostics on the device. These are filesystem safeguards, **not a security sandbox**.
- **Footprint:** about 2 GB on NVMe for both venvs, about 0 on the eMMC.
- **Possible privileged prerequisites:** if `python3.8-venv` or `libopenblas` is missing, the script aborts. Installing them needs separate approval.

## 4. Dependency compatibility and reproducibility assessment

- **Availability:** every compiled dependency has a cp38 manylinux2014 aarch64 wheel. This covers numpy, scipy 1.10.1, scikit-image 0.21.0, scikit-learn 1.3.2, pandas 2.0.3, pillow, SimpleITK 2.4.1, matplotlib 3.7.5, PyWavelets and others. **No compilation on the Xavier is needed**, and `--only-binary=:all:` enforces that.
- **Python 3.8 ceiling:** these are the last Python 3.8 lines of numpy (1.24), scipy (1.10), scikit-image (0.21), pandas (2.0) and matplotlib (3.7). New research code must stay Python 3.8-compatible (D18).
- **Torch substitution risk:** torchio declares `torch`, so a resolver could pull a CPU-only PyPI torch. This is prevented by `--no-deps` with fully pinned locks, and by installing torch only from the verified NVIDIA file.
- **Reproducibility:**
  - Locks pin exact versions and SHA-256 for every artefact, and the regeneration command is recorded in each `.in` file.
  - `env/xavier/dependency-manifest.json` records the 51 actual wheels (filename, version, Python/ABI/platform tags, Requires-Python, size, SHA-256); CI cross-checks it against the locks.
  - The installer writes an environment record (approval references, reviewed commit, lock hashes, smoke-test JSON, `pip freeze`).
  - Remaining non-determinism: system libraries from JetPack (CUDA, cuDNN, libopenblas) are pinned by the observed JetPack version, not by these locks.
- **Not yet verified:** on-device import and runtime behaviour of the scientific stack. That is Stage 1A work, after approval.

## 5. Security and data governance (summary)

Full assessment: [`docs/XAVIER_ACCESS_AND_SECURITY.md`](../docs/XAVIER_ACCESS_AND_SECURITY.md).
- **Main risk (S1):** the research account is a sudoer. **D21 (revised, R3-03):** a new administrator account with password-protected sudo (never `NOPASSWD`); the existing SSH research identity loses sudo and stays out of `docker`. Account names are kept out of the public repository.
- **Scope of a D21 approval:** it authorizes the documented manual account migration by the device administrator, but **does not authorize autonomous agent execution** on the device.
- **Current state:** no further account changes have been made following the initial authorized access setup.
- **Layout:** administrator-owned `/data/bowelnca` (0750, research group, traversal only) and `datasets/` (read-only to research); research-owned 0700 execution subdirectories; `/data` unchanged.
- **Migration:** seven phases (0 to 6), run by the administrator; current access is preserved until the new administrator account is verified from a separate session; the eight execution subdirectories are normalized to 0700; the effective sudo policy is verified with `sudo -l -U` from the administrator account; stale privileged research sessions are closed and checked before any install; the administrator fallback is kept. **Not executed.**
- **Evidence (R3-10):** unapproved drafts never enter the public repository. CI rejects any `evidence-draft` path and any file marked `PENDING-HUMAN-APPROVAL`.
- **Not published:** VPN details, hostnames, account names, keys, raw logs and private correspondence.

## 6. Upstream OctreeNCA and license

- **Commit:** `70f774232305b76330a75edef9fddda8ec960cab`. No LICENSE file, headers or packaging license, so all rights are reserved.
- **Inquiry:** sent 25 Nov 2026, awaiting response. Correspondence is private.
- **Decision point:** 16 Dec 2026 (D17): license or grant in hand, extend the wait, or authorize a clean-room implementation.
- **No upstream implementation is authorized for redistribution or adaptation.**

Details: [`docs/UPSTREAM_LICENSE_REVIEW.md`](../docs/UPSTREAM_LICENSE_REVIEW.md).

## 7. Evidence and execution record

| Item | State |
|---|---|
| Inventory evidence | Sanitized transcription, reviewed in round 3 as consistent with the owner's terminal output. **Redaction attested by the owner on 2026-11-26 (`REDACTED-BY-HUMAN: AN 2026-11-26`); E1 accepted.** Published as [`reports/evidence/stage0_inventory_2026-11-26.md`](evidence/stage0_inventory_2026-11-26.md). Relative to the attested private copy, only the attestation header and the title (no longer "draft") changed; the body is identical. Its workspace section reflects the state at collection time (write test pending), which W1 later resolved (section 1.4). The earlier draft commit `9c92ab7` remains in this PR branch's history; it contains no sensitive identifiers (round 3 review), so no history rewrite is proposed. A squash merge keeps it out of `main` |
| Raw log | Kept privately by the owner; not committed |
| Data transfer / training | **None** |
| Read-only inventory (Stage 0 scope) | Run by the owner, unprivileged, with the reviewed script at `e26e3db`. Read-only; no sudo |
| Owner's authorized administrative setup | **Separate from the inventory and outside the agent's boundaries.** With the device administrator's grant, the owner created `/data/bowelnca` and its nine subdirectories (D20) and, before W1, normalized them to mode 0700. These were manual, authorized administrative actions by a human on the project workspace only; `/data` was not changed |
| Workspace verification (W1) | Run by the owner, unprivileged; non-destructive (one 1 MiB temp file, removed) |
| Account changes | The device administrator's initial authorized access setup (the dedicated project account, its SSH key and password-protected sudo) only. **No further account changes have been made following the initial authorized access setup** |
| Agent execution boundary | **Unchanged.** The agent has no access to the Xavier, ran nothing on it, and made no privileged, account, permission or system change anywhere. Its work is limited to this repository and its cloud sandbox |
| Privileged changes by the agent | **None** |
| Earlier incident (25 Nov) | A test-design bug ran an injected mutant in the agent's cloud sandbox only. Fixed; covered by the mutation test (section 9) |

## 8. Blockers, outstanding work and approvals

| ID | Item | Status | Needed from |
|---|---|---|---|
| ~~B1~~ | Access and inventory | **Resolved for humans:** SSH works and the inventory is collected. The agent intentionally has no access | - |
| ~~E1~~ | Owner's redaction attestation of the sanitized evidence | **Accepted.** Attested by Anas (AN, 2026-11-26); published in `reports/evidence/` | - |
| ~~W1~~ | Workspace check and write test (interim layout) | **PASSED** 2026-11-26T08:40:33Z at `73dbac6` (0 FAIL, 2 expected WARN) | - |
| W2 | Separated-layout verification (`--layout separated`) | After D21 migration; part of Stage 1A | Administrator, then research account |
| S1 / D21 | Account separation, layout and migration | **Approved by the owner (26 Nov 2026), not yet executed.** Prerequisite for D22. Authorizes the documented manual migration by the human administrator, not autonomous agent execution | Anas, as administrator (D25) |
| ~~D24~~ | Split Stage 1 into 1A (environment) and 1B (upstream reproduction) | **Approved** by the owner (26 Nov) and Dr. Iyad (26 Nov 2026 (20:16 UTC)) | - |
| I1 / D22 | Core environment install and CUDA smoke test (G1) | **Owner-approved, conditional** on D21, W2 and a recorded D22 reference; the Stage 0 to Stage 1A gate passed on 26 Nov 2026 (20:16 UTC). Not executed | Anas (administrator, D25 confirmed) |
| I2 / D23 | Scientific environment install and import checks | **Owner-approved, conditional** on a passing D22 core record; not executed | Anas |
| I3 | Privileged prerequisites, only if `--check-only` reports `python3.8-venv` or `libopenblas` missing | Not requested | Dr. Iyad |
| B2 | OctreeNCA license | Inquiry sent, awaiting response; decision 16 Dec 2026 (D17) | Authors, then Anas and Dr. Iyad |
| B3 | Upstream Python 3.10 vs Xavier Python 3.8 | D18 approved by the owner (separate environments) | - |
| P | Parallel architecture-independent work, P1, P2, P4, P7, P8 (synthetic data, CPU only) | D19 approved by the owner (26 Nov) and by **Dr. Iyad (26 Nov 2026 (21:53 UTC))**; P1 starts after the approval record is merged; not started | - |
| M | Merge PR #2 (squash) | **Engineering review accepted PR #2 at `18689161acd47ded650cc76f83fd7d5232fc1260`**; documentation head `ee60a3a` accepted by Anas (CI run 45795277612). Squash merge authorized by the owner on 26 Nov 2026; later commits are approval records only, with the engineering tree unchanged | Anas (a human merges; agents never merge their own PRs) |

### Stage 0 acceptance criteria (issue #1)

| Criterion | Status |
|---|---|
| Device model, architecture, Jetson Linux release captured | **Done** (observed; E1 accepted) |
| Python, CUDA, PyTorch, `torch.cuda.is_available()` captured, including absent-import cases | **Done:** PyTorch absent, so CUDA availability is not testable before an install |
| Memory/storage, cooling/power noted | **Done** |
| NVIDIA wheel checked against the observed JetPack and ABI, not installed | **Done:** candidate compatible build, pending on-device validation (Stage 1A smoke test) |
| OctreeNCA commit identified, license recorded separately | **Done**; license **unresolved** |
| Installation commands proposed only | **Done** (revised proposal, locks, manifest), not executed |
| `reports/stage_0.md` with evidence and reproducibility notes | **Done** (this revision) |
| Redacted evidence, zero raw scans, zero privileged changes by the agent | **Done:** owner attestation recorded (E1 accepted); no raw scans; no privileged changes by the agent |
| Workspace verified | **Done (interim layout, W1).** Separated layout verified later (W2, after D21) |
| Next-stage gate explicitly pending | **Yes.** Stage 0 approved (26 Nov 2026 (20:16 UTC)). Stage 1A is the next stage; its execution still needs D21, W2 and a recorded D22 reference. Stage 1B is not authorized |

**Stage 0 is approved.** With D24 approved, the GPU smoke test belongs to Stage 1A and does not hold Stage 0 open.

- **Reviewer sign-off (name, date, decision):** Dr. Iyad Naim, 26 Nov 2026 (20:16 UTC), **approved** (as reported by the project owner; the written approval stays private).

## 9. Tests run for this revision (repository-side only)

All pass locally (as root and as an unprivileged user) and in CI:
- `bash -n` and `shellcheck -S warning` on all scripts, including `scripts/lib/` and `scripts/proposed/`;
- `scripts/check_repo_policy.sh`;
- `tests/test_repo_policy.sh` (32 synthetic violations rejected, including evidence drafts anywhere in the tree);
- `tests/test_inventory_readonly.sh`;
- `tests/test_inventory_guard_mutations.sh` (13 mutants rejected, none executed);
- `tests/test_proposed_scripts.sh` (122 checks; the final review added installed-version verification against the manifest and a direct-reference `pip freeze` case; round 4 added lock-file validation (symlink, dangling symlink, directory, FIFO, wrong owner, hard link), mount-enumeration failure, a dangling symlink at the record destination, a hostile inherited environment (`PYTHONPATH`, `PYTHONHOME`, `PIP_TARGET`, `PIP_PREFIX`, `PIP_USER`, `PIP_INDEX_URL`, `PIP_CONFIG_FILE`), and failures of the env hook, `pip freeze`, the smoke JSON and lock hashing, each with rollback and retained private diagnostics): refusals (no stage, approval, reviewed commit, dirty checkout); precondition failures (interim layout, sudo/docker membership, writable datasets, wrong mount or filesystem, nested mount, low space, missing libopenblas, symlinked directories and destinations); large `ldconfig` output without SIGPIPE; `--check-only` writes nothing; a concurrent run refuses; checksum failure; rollback after a failed pip step and after a failed smoke test, keeping pre-existing files; **successful simulated core and sci runs** (install order, hash locking, records with both approvals, smoke test executed through `activate` with scoped CUDA and caches, core venv unchanged by sci); lock/manifest consistency; verifier interim and separated layouts, write test skipped on failed checks, failed and short writes detected and cleaned up, no global sync, no identifiers printed.

One defect was found while writing these tests: a failed pip step could be ignored when the script ran inside a caller that had disabled errexit. Every install step now aborts explicitly, and a mutation check confirmed the rollback tests fail if that is removed.

These are regression checks with substituted identities and mounts, not security guarantees and not a substitute for the on-device run.

## 10. History

- **Round 1 (25 Nov, `f0f2eef`):** six requested changes, all addressed in `878197a`:
  - guard wording;
  - output minimization;
  - fail-closed install;
  - stronger policy;
  - removal of the unverified third-party claim;
  - Python 3.8 framing.
- **Round 2 (25 Nov, `878197a`):** technical GO for the preparatory changes at that commit only (superseded by round 3), subject to Dr. Iyad's merge authorization (squash). Status updates in `e26e3db`.
- **26 Nov (`9c92ab7`):** owner completed access, inventory and workspace. Observed values, locks, installer proposal, workspace verifier and security assessment added.
- **Round 3 (26 Nov, `9c92ab7`):** REQUEST CHANGES, R3-01 to R3-10. The sanitized inventory was found consistent with the owner's terminal output. Addressed in `73dbac6`.
- **Round 4 (26 Nov, `73dbac6`):** CONDITIONAL GO with targeted corrections R4-01 to R4-04; account names stay private; no history rewrite. W1 passed the same day. This revision applies R4-01 to R4-04, records W1 and D20 (interim), and records Anas's recommendation to approve D19.
- **Final Stage 0 engineering review (26 Nov, `87858b6`):** Technical GO for the preparatory repository changes, subject to the owner's redaction attestation (E1) and Dr. Iyad's merge authorization; **no installation authorization**. One pre-installation correction: verify installed versions with `importlib.metadata` against the manifest instead of parsing `pip freeze` (a local wheel is listed as `torch @ file:///...`). Done in `1868916`, with regression tests; `pip freeze` is kept as evidence. The independent engineering review then **accepted PR #2 at `18689161acd47ded650cc76f83fd7d5232fc1260`** with all 122 regression checks passing.
- **Revision 8 (26 Nov, documentation only):** the owner attested the redaction (`REDACTED-BY-HUMAN: AN 2026-11-26`), so E1 is accepted and the sanitized inventory is published in `reports/evidence/`. Wording corrected: engineering preparation complete with formal acceptance pending; no further account changes after the initial authorized access setup; the wheel is a candidate compatible build pending on-device validation; D21 approval covers the manual migration by the administrator, not autonomous agent execution. No engineering changes.
- **Revision 9 (26 Nov 2026 (20:16 UTC), documentation only):** Dr. Iyad approved Stage 0 (D14) and D24, confirmed the D25 delegation in writing, and approved Q1, Q2, Q4, Q5 and Q6 (D26, D27, D29, D30, D31). D19 and Q3 (D28) remain pending.
- **Revision 10 (26 Nov 2026 (21:53 UTC), documentation only):** Dr. Iyad approved D19 and approved Q3 with an amendment (D28: linear probability interpolation to the original grid, then threshold for A/B or argmax for D; equivalent nnU-Net procedure after verifying its export; policy frozen before final testing). The Stage 2 data steward remains open.

## 11. Sources

- NVIDIA, *Installing PyTorch for Jetson Platform*: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform/index.html
- NVIDIA, *PyTorch for Jetson compatibility matrix*: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform-release-notes/pytorch-jetson-rel.html
- NVIDIA forum, wheel on AGX Xavier / JetPack 5.1.4: https://forums.developer.nvidia.com/t/cannot-install-pytorch-on-agx-xavier-with-jetpack-5-1-4-not-supported-wheel-on-this-platform/316956
- NVIDIA forum, PyTorch for L4T 35.6: https://forums.developer.nvidia.com/t/request-build-script-for-pytorch-or-up-to-date-pytorh-binary-release-supporting-jetson-boards-running-l4t35-6-ubuntu20-04/316972
- JetPack 5.1.6 / L4T 35.6.4 announcement: https://forums.developer.nvidia.com/t/jetpack-5-1-6-l4t-35-6-4-is-now-live/359614
- Upstream: https://github.com/MECLabTUDA/OctreeNCA @ `70f774232305b76330a75edef9fddda8ec960cab`; arXiv:2508.06993
