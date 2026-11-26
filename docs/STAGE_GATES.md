# Engineering stages, pull requests and sign-off gates

Stage 0 was approved by Dr. Iyad on 27 Nov 2026. Stage 1 is split into **1A** (Xavier environment) and **1B** (upstream reproduction), approved as D24 on 27 Nov 2026. The stages below define sequencing, not blanket spending authorization.

| Stage | Suggested issue / branch | Exit evidence | Gate |
|---|---|---|---|
| 0 | `stage0/jetson-env` | Redacted inventory, pinned toolchain proposal, license investigation, `reports/stage_0.md` | Dr. Iyad reviews any changes before installation |
| 1A | `stage1a/xavier-env` | Separated-layout workspace check (W2), core environment record and bounded CUDA smoke test (`result: pass`), optional scientific environment record, redacted `reports/stage_1a.md` | Stage 0 acceptance; D21 done; recorded D22/D23 references; review before Stage 1B on the Xavier |
| 1B | `stage1b/octree-repro` | CUDA forward/backward and overfit check, upstream prostate reproduction or approved exception, timings, in the environment chosen under D18 | License status (D12/D17); D18 environment; review before data training |
| 2 | `stage2/data-audit` | Independent duplicate audit, patient-disjoint split, QC overlays, hashes and transfer ACL (identifiers, manifests and restricted hashes in private storage only, D31) | Data steward + Dr. Iyad review |
| 3 | `stage3/benchmark` | 200-step measured GPU pilot, memory/run-time matrix, cost estimate | Requires Stages 1B and 2 complete; permission for Stage 4; 24-hour stop limit |
| 4 | `stage4/arm-screen` | A/B/D n=20 one-seed results on Selection30, per-case output | Scientific review |
| 5 | `stage5/design-freeze` | Signed design freeze, source/version/checkpoint hashes | Lock before learning curve |
| 6 | `stage6/learning-curve` | 20/30/40 validation10 results; UoN request estimate | Separate HPC approval |
| HPC | Future authorization | Frozen confirmatory matrix, repeated seeds, nnU20/40, single held-out test | New budget + test-unlock sign-off |

PR checklist: issue linked, plan version noted, config/code hashes, tests performed, logs redacted, data permissions respected, numerical outputs identified as actual or illustrative, scientific impact explained. Never self-merge a scientifically consequential stage PR.
