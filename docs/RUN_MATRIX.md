# Experiment matrix - scientific requirements vs execution approval

**All run counts below are planning quantities, not completed experiments or GPU-hour measurements.**

## Xavier: exploratory stage (only after Stage 0-3 exit approvals)

| Stage | Arm | Training cases | Seeds | Scored on | Role |
|---|---|---:|---:|---|---|
| 4 | A (MRI only) | 20 | 1 | Selection30 (development) | Controlled baseline |
| 4 | B (MRI + Hessian) | 20 | 1 | Selection30 (development) | Primary feature candidate |
| 4 | D (multi-class context) | 20 | 1 | Selection30 (development) | Secondary context candidate |
| 6 | Frozen preferred design | 20,30,40 | 1 per size | Validation10 | Provisional learning curve |

Stage 4 and 6 require separate stage approvals. A Stage 4 checkpoint may be reused in Stage 6 only if the configuration and frozen training schedule match exactly; otherwise retrain. Stage 6 does not use the locked test cohort.

## Proposed confirmatory HPC - **not approved to execute**

| Experiment | Training cases | Intended seeds | Scientific requirement |
|---|---|---:|---|
| A: image-only NCA | 40 | >=3 | **Required primary comparator** |
| B: feature-augmented NCA | 40 | >=3 | **Required primary method** |
| Frozen preferred NCA design | 20,30,40 | >=3 per size | Supporting data-efficiency curve |
| nnU-Net v2 | 20,40 | Ideally >=3 per size | **Mandatory baseline**; fewer seeds only with justification + disclosure |
| Arm D at n=40 if not already covered by selected design | 40 | Cost-gated | Secondary anatomical-context analysis |
| nnU-Net at n=30, extra ablations | Optional | Cost-gated | Exploratory only |

If the preferred design is B, its n=40 runs can contribute to both the primary and learning-curve analysis if all configs match. The full deduplicated run count and cost will be approved after Stage 3 measurements. Every listed comparator uses the same frozen train/validation/test IDs.

## One-time test campaign

After training and analysis freeze, unlock the same 52 test cases once to evaluate **all prespecified final models**. Only label 3 (jejunum-ileum) counts for primary/secondary segmentation reporting, including Arm D. Compute 3D Dice and mm-space HD95 after mapping predictions to original acquisition grids. Record per-patient per-seed outputs and paired B-A bootstrap intervals. Never tune from final test outcomes.
