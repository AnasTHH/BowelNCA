# Feature-Augmented OctreeNCA for Jejunum-Ileum MRI Segmentation

**Status: research development starter, not trained or validated.**

This repository starter implements the **engineering contract and read-only Stage 0 check**, not a segmentation model. Its authoritative specification is [`docs/DEVELOPMENT_PLAN_v1.2.md`](docs/DEVELOPMENT_PLAN_v1.2.md).

## Scope and scientific questions

- **Target:** jejunum-ileum, exactly source label 3, excluding duodenum.
- **Primary outcome:** paired held-out 3D Dice difference (feature-augmented Arm B minus image-only Arm A), both trained with 40 cases.
- **Secondary:** auxiliary anatomical-context Arm D, HD95, resource use and training-size sensitivity at 20/30/40.
- **Baseline:** nnU-Net v2 at n=20 and n=40 is mandatory in a future, separately approved confirmatory HPC phase.
- **Not clinical software.** No model weights, scientific results or MRI data are contained in this starter.

## What is included now

- A revised, scientifically controlled development plan (v1.2).
- A research governance and approvals log.
- A ready-to-paste Claude Code Stage 0 handoff.
- A read-only Jetson inventory script and stage report template.
- A safe Git ignore policy and a lightweight repository-policy CI check.

## First action on Dr. Iyad's Xavier

1. Create a **separate user account and SSH key** for the developer; do not reuse Dr. Iyad's credentials.
2. Clone the future research repository or transfer this package to a controlled development directory. Do not transfer raw MRI or test annotations to the Xavier.
3. Inspect [`docs/STAGE_0_CLAUDE_HANDOFF.md`](docs/STAGE_0_CLAUDE_HANDOFF.md) and run only the read-only inventory:

   ```bash
   bash scripts/jetson_inventory.sh | tee stage0_inventory_local.log
   ```

4. Review/redact the local inventory log before attaching it to `reports/stage_0.md`; verify matching NVIDIA Jetson ARM64 PyTorch support.
5. Obtain approval before any installation, power-mode change, firmware update, external code import or long training job.

## Explicit non-approvals

- Do **not** start full model training, the nnU-Net experiments, or final test evaluation.
- Do **not** assume the reported dataset deduplication is validated.
- Do **not** redistribute OctreeNCA upstream code until modification and distribution rights are documented.
- Do **not** infer that UoN HPC access has been granted.

## Useful files

| File | Purpose |
|---|---|
| `CLAUDE.md` | Rules for coding agents |
| `docs/DEVELOPMENT_PLAN_v1.2.md` | Authoritative scientific/engineering specification |
| `docs/STAGE_0_CLAUDE_HANDOFF.md` | Stage 0 instructions for Claude Code |
| `docs/DECISIONS.md` | Decisions and unresolved gates |
| `docs/DATA_GOVERNANCE.md` | Dataset isolation and leakage prevention |
| `docs/RUN_MATRIX.md` | Approved versus proposed experiments |
| `docs/STAGE_GATES.md` | PR/review and scientific approval process |
| `docs/UPSTREAM_LICENSE_REVIEW.md` | License verification template |
| `scripts/jetson_inventory.sh` | Read-only system information collector |
| `reports/stage_0_TEMPLATE.md` | Stage 0 evidence format |

## Publication

Public release is planned **after** rights checks, documentation, reproducibility review, and scientific authorization. No raw clinical datasets are distributed in this starter. Dataset attribution belongs to the original Zhong et al. Zenodo record. Do not add an unverified upstream license or cite an unmeasured result.
