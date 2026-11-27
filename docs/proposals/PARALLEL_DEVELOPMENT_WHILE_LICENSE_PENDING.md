# Proposal: architecture-independent development while the OctreeNCA license is pending

**Status: approved by the project owner (Anas, 26 Nov 2026) and by Dr. Iyad (26 Nov 2026 (21:53 UTC)); not started** (decision D19). Scope: P1, P2, P4, P7, P8, synthetic data only, CPU only; P1 starts after the approval record is merged. D19 does not authorize real MRI access, upstream reproduction, GPU training, paid compute or privileged execution. Anas supports it (re-review, 25 Nov 2026), with initial priority **P1, P2, P4, P7, P8**, **synthetic data only and CPU only**, subject to scientific approval. It needs Dr. Iyad's approval because it starts parts of Stage 2 engineering before Stages 0 and 1 have closed.
**Date:** 25 Nov 2026 · **Plan:** `docs/DEVELOPMENT_PLAN_v1.2.md` · **Related:** D12, D17, D18, issue #1

## 1. Problem

Stage 1 and everything built on OctreeNCA are blocked until the licensing decision on **16 Dec 2026** (D17), and possibly longer. The plan's critical path is sequential (Stage 0, 1, 2, ...). A strict reading leaves engineering idle for at least 3 weeks. Much of the pipeline does not depend on the segmentation backbone at all.

## 2. Proposal

Build and test the **backbone-agnostic** parts of the pipeline now, using **synthetic data only**, CPU-only, in small reviewed PRs. Each component is specified by the plan, independent of which NCA implementation is eventually used (licensed upstream, written grant, or clean room), and testable without MRI data.

| # | Work package | Plan section | Synthetic test evidence | Est. effort |
|---|---|---|---|---|
| P1 | Synthetic fixture generator: NIfTI-like volumes with known affines, anisotropic spacing (1.25 x 1.25 x 4.8 mm), tube/blob phantoms and label maps with source labels 0-10 | 3.1, 5.3, 11 | Deterministic hashes per seed | 1-2 days |
| P2 | Label mapping: binary (label 3 -> 1, all else 0) and Arm D four-class context mapping, with unexpected-label failure | 3.1 | Exhaustive label-table tests; overlap and unknown-label cases | 0.5 day |
| P3 | Preprocessing: RAS reorientation from the affine, in-plane resampling to 1.25 mm (linear image / nearest label), percentile clip and normalization, crop/pad with validity mask, transform history | 4 | Round-trip and orientation tests on phantoms; empty/uniform-volume handling | 3-4 days |
| P4 | Inverse mapping to the original grid following D28 (linear probability interpolation, then threshold for A/B or argmax for D; nearest-neighbour for reference labels), plus metrics: 3D Dice and mm-space HD95 on the original grid with explicit empty-case rules (D26, D27) | 4.8, 7.1 | Probability versus categorical-label interpolation tested separately; multiclass argmax; original-grid metric checks; analytic cases (shifted spheres, known HD); parity against an independent reference implementation | 2-3 days |
| P5 | Hessian features (tubeness, blobness, dominant scale) at 4/8/12 mm with documented sigma and eigenvalue conventions | 5.3 | Tube/blob phantoms; parity with `skimage.feature.hessian_matrix` and its eigenvalues; near-zero and constant-response edge cases | 3-4 days |
| P6 | Augmentation: one in-plane rotation/scale per volume applied identically to image (linear) and masks (nearest), gamma/noise, **then** Hessian recomputation; no left-right flips; logged parameters | 5.4 | Alignment tests (feature maps of the transformed phantom equal features recomputed after the transform); flip-absence test | 2-3 days |
| P7 | Split tooling: seed-42 stratified nested `train20` within `train30` within `train40`, `splits.json` plus `splits.json.sha256` sidecar (real manifests written only to private research storage, D31; CI checks synthetic examples), and a halt when the eligible count is not 102 | 3.3 | Synthetic ID sets, including the 102 and non-102 cases | 1-2 days |
| P8 | Run-manifest schema and writer (commits, hashes, seed, versions, hardware, steps, memory, wall-clock), with an A/B pairing check that requires an equal evaluation policy (D28) | 11 | Schema validation tests; pairing-contract tests | 1 day |
| P9 | Model interface: a thin `SegmentationModel` protocol (input channels, output classes, `forward`, `parameter_count`) with a trivial reference model for wiring tests | 5.2 | Shape and contract tests | 0.5 day |

Total is about 15-20 engineering days, delivered as 6-9 PRs, each with its own issue.

## 3. Constraints (unchanged)

- **No MRI data, no masks, no test cohort, no Xavier access** for this work. Real-data use stays behind the Stage 2 audit gate.
- **No NCA code.** Nothing from upstream OctreeNCA is copied, adapted or paraphrased. P9 defines an interface only.
- **Clean-room hygiene.** Anyone who may later write a clean-room NCA (if D17 goes that way) should not study the upstream source in the meantime. The upstream checkout stays outside this repository.
- **CPU-only and hosted CI.** Tests run on GitHub-hosted runners with synthetic data. Python 3.8 and 3.10 run as a matrix, so the code works in both proposed environments (D18).
- **No methodology changes.** All definitions come from plan v1.2. Any ambiguity is raised in the PR, not silently resolved. For example, whether 4/8/12 mm denote sigma or diameter (Section 5.3) is a decision for Dr. Iyad.
- No package installation on the Xavier and no training.

## 4. Benefits, costs and risks

**Benefits.** The licensing wait is used productively. Stage 2 then starts with a tested pipeline, so its gate becomes about real-data audit rather than plumbing. Most items are reusable under every D17 outcome.

**Costs.** About 3-4 weeks of engineering effort, plus review time for Dr. Iyad and Anas. There is no compute cost.

**Risks.**
- Stage-order deviation: this needs explicit approval.
- Rework if Stage 1 shows that OctreeNCA's input/patching layout constrains preprocessing. Mitigation: keep crop/pad parameters configurable and do not freeze them before Stage 1.
- Review load: mitigated by small PRs.
- Scope creep into model work: P9 is limited to an interface.

## 5. Decision requested

Approve or reject starting the initial priority set **P1 (synthetic fixtures), P2 (label mapping), P4 (inverse mapping and metrics), P7 (split tooling) and P8 (run manifest)** before Stage 1, under the constraints above (synthetic data only, CPU only). P3, P5, P6 and P9 would follow in a later, separately approved tranche. The initial set is about 5.5-8.5 engineering days by the estimates in section 2. If approved, each package gets its own issue and branch, and nothing touches the Xavier or real data.
