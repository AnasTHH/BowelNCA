# Proposal: split Stage 1 into 1A (Xavier environment) and 1B (upstream reproduction)

**Status: approved (D24): by the project owner (Anas, 26 Nov 2026) and by Dr. Iyad (26 Nov 2026 (20:16 UTC)), in the context of the ordered approval request.** The definitions below are now part of `docs/STAGE_GATES.md` and `docs/DEVELOPMENT_PLAN_v1.2.md`. Requested by the round 3 review (R3-09), 26 Nov 2026.

## Why

Stage 0 was defined as an inventory and installation-**proposal** stage. Installing the environment and validating CUDA on the Xavier is different work with different risks (host changes, a privileged prerequisite may surface) and does not depend on the OctreeNCA license. The current Stage 1 (`stage1/octree-repro`) bundles it with upstream reproduction, which is blocked by the license (B2, D17) and by Python 3.10 vs 3.8 (B3, D18). Splitting lets the environment work proceed, under its own approvals, without implying anything about upstream code.

## Proposed definitions

| Stage | Scope | Exit evidence | Gate | Depends on |
|---|---|---|---|---|
| **1A** Xavier environment | D21 account separation (administrator-run); core install (D22) and CUDA smoke test; optional scientific environment (D23) with import checks | `verify_workspace.sh --layout separated` output (redacted), `env-core-*` and optionally `env-sci-*` records ending `result: pass`, `reports/stage_1a.md` | Dr. Iyad approves D21, D22 (and D23 separately); review of the Stage 1A report | Stage 0 sign-off |
| **1B** Upstream reproduction | Reproduce upstream OctreeNCA (prostate) in the environment chosen by D18; CUDA overfit; timings | As the current Stage 1 | Unchanged from the current Stage 1 gate | 1A (if on the Xavier), license resolution (B2/D17), D18 |

Stage 0 would then close on: approved evidence (E1), the workspace check (W1), the installation **proposal** reviewed, and Dr. Iyad's sign-off. The GPU smoke test (G1) moves to Stage 1A instead of keeping Stage 0 open.

## Not changed by this proposal

- The scientific protocol, primary contrast, data rules and later stages.
- No installation, account change or upstream work is authorized by this document.
