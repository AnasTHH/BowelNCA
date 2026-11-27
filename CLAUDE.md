# Claude Code Contract - Jejunum-Ileum NCA Research

**Read `docs/DEVELOPMENT_PLAN_v1.2.md` before proposing code.** It is the source of truth for research methodology. This file describes execution boundaries, not a substitute for hardware permissions or scientific review.

## Current authorization

**Stage 0 is approved** (Dr. Iyad, 26 Nov 2026 (20:16 UTC); `docs/DECISIONS.md` D14). **Stage 1A** (Xavier environment, D24) may be prepared and executed **manually by the human administrator** within the recorded approvals (D21 to D23, D25); agents have no device access and never run privileged or installation steps. **D19** (synthetic-only, CPU-only parallel development of P1, P2, P4, P7, P8) is **approved** (Dr. Iyad, 26 Nov 2026 (21:53 UTC)); work starts with P1 once this approval record is merged, and implementation branches are published only after the security enforcement gate passes. D19 authorizes no real MRI access, upstream reproduction, GPU training, paid compute or privileged execution. Q3 is approved with an amendment (D28): P4 follows that evaluation policy. Do not self-advance to install packages or train models. Stages 1B to 6 require their preceding stage report and reviewer gate; confirmatory HPC and test-set evaluation require a separate explicit approval.

## Immutable research constraints

1. Target is source label `3` only, called **jejunum-ileum (excluding duodenum)**. Arm D's extra class labels are auxiliary, not new clinical targets.
2. **Primary comparison remains Arm B - Arm A at n=40** in the confirmatory stage even if Arm D wins exploratory selection.
3. The original 114 files reportedly contain 102 unique images. **Do not assume** the finding is independently verified. Halt split generation on mismatched results.
4. All test cases, their ground-truth masks, and alternate annotation versions are excluded from Xavier and model-development agents. Do not open, preview, OCR, copy or summarize test images/masks.
5. The 40/10/52 split is conditional on the completed, approved duplicate and patient-level audit. `train20` must be contained in `train30`, contained in `train40`.
6. `Selection30` (10 validation + 20 later training candidates) is exploratory, **not** a pristine independent validation cohort.
7. Do not generate shape features from segmentation masks. Recompute Hessian features **after** geometric and intensity augmentation on the full transformed volume. No left-right flips.
8. Never modify or delete original data; derived data belongs in ignored `data/derived/`. No raw MRI, test data, checkpoints, secrets, tokens or user private keys in Git, CI or external prompts.
9. Do not copy upstream OctreeNCA implementation into a public repo or claim reuse rights until the license review is complete.
10. Every training run must record source commits, dataset/split hashes, seed, hardware, versions, steps, memory, wall-clock and full configuration.
11. A stage is complete only with a reviewed PR, a `reports/stage_N.md` report and sign-off where required. No self-approval or hidden protocol changes.
12. Never run work estimated above 24 hours without Dr. Iyad's explicit permission. No automatic paid cloud instance start.

## Stage 0 task scope

- Gather Jetson environment facts **read-only** with `bash scripts/jetson_inventory.sh` (no sudo needed).
- Identify exact compatible NVIDIA ARM64 PyTorch distribution for the observed JetPack, and document sources/versions.
- Pin and cite the precise upstream OctreeNCA commit you plan to inspect; document license status, do not assume a license from public GitHub visibility.
- Draft a safe, manually reviewed install plan if packages are needed, but do **not** execute it.
- Write `reports/stage_0.md` using the template, link to redacted logs. Stop for review.

## Forbidden unattended actions

- `sudo`/privileged configuration changes, kernel/JetPack upgrades, flashing, repartitioning, destructive cleanup.
- GPU training, long benchmarks, `jetson_clocks`, `nvpmodel -m ...` (power mode changes), external SSH service exposure.
- Uploading raw scans or patient labels to tools, issues, agents or hosted CI.
- Editing the approved split manifest after freeze, or visiting locked test storage.
- Merging your own PRs or changing the experimental primary contrast.

Security boundaries must be enforced by SSH permissions, dataset ACLs and separate storage. Claude Code approval/deny rules and hooks are helpful defense-in-depth but are **not** sufficient access controls.

## Coding and reporting quality

- One issue/branch per coherent change. Tests + docs in the same PR. Do not conflate source-derived observations with measured new results.
- Prefer pinned deterministic dependencies, explicit physical units, original-grid metric checks, synthetic test fixtures, clean logs and reproducible commands.
- Include clear implementation rationale and unresolved blockers; do not silently patch science decisions.
