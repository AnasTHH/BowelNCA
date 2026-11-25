# Engineering stages, pull requests and sign-off gates

The initial deliverable is **Stage 0** only. The stages below define sequencing, not blanket spending authorization.

| Stage | Suggested issue / branch | Exit evidence | Gate |
|---|---|---|---|
| 0 | `stage0/jetson-env` | Redacted inventory, pinned toolchain proposal, license investigation, `reports/stage_0.md` | Dr. Iyad reviews any changes before installation |
| 1 | `stage1/octree-repro` | CUDA smoke/overfit, upstream prostate reproduction or approved exception, timings | Review before data training |
| 2 | `stage2/data-audit` | Independent duplicate audit, patient-disjoint split, QC overlays, hashes and transfer ACL | Data steward + Dr. Iyad review |
| 3 | `stage3/benchmark` | 200-step measured GPU pilot, memory/run-time matrix, cost estimate | Permission for Stage 4; 24-hour stop limit |
| 4 | `stage4/arm-screen` | A/B/D n=20 one-seed results on Selection30, per-case output | Scientific review |
| 5 | `stage5/design-freeze` | Signed design freeze, source/version/checkpoint hashes | Lock before learning curve |
| 6 | `stage6/learning-curve` | 20/30/40 validation10 results; UoN request estimate | Separate HPC approval |
| HPC | Future authorization | Frozen confirmatory matrix, repeated seeds, nnU20/40, single held-out test | New budget + test-unlock sign-off |

PR checklist: issue linked, plan version noted, config/code hashes, tests performed, logs redacted, data permissions respected, numerical outputs identified as actual or illustrative, scientific impact explained. Never self-merge a scientifically consequential stage PR.
