# Feature-Augmented OctreeNCA for Jejunum-Ileum Segmentation in MR Enterography
## Development Plan v1.2 - controlled engineering and scientific protocol

**Date:** 25 November 2026  
**Scientific lead and approving reviewer:** Dr. Iyad Naim  
**Engineering lead:** To be assigned  
**Research target:** Jejunum-ileum, source label 3 only (small intestine excluding duodenum)  
**Status:** Scientific methodological amendments approved by Dr. Iyad; implementation has not been verified. Stage 0 is the first execution task.  
**Supersedes:** Development Plan v1.1 for implementation; updates the architecture and operations portions of Research Blueprint v1.1.  
**Publication objective:** A reproducible public research repository and, subject to valid results and review, a citable scientific paper/software release. No clinical-use claims.

> **Authority and gates.** Scientific approval of this protocol is not approval of a GPU budget, Nottingham HPC allocation, final-test unlock, public release, or any experimental result. The developer must stop at each stage gate for review. Confirmatory HPC experiments and release remain separate decisions.

## 1. Scientific mission

Build, assess, and document a lightweight **3D OctreeNCA** segmentation approach for the **jejunum-ileum (source label 3)** on coronal MR enterography (MRE). The central methodological hypothesis is that adding deterministic, multiscale Hessian-derived local-shape features improves segmentation over the otherwise equivalent image-only NCA. A contextual multi-class prediction head is a secondary experiment. Training with 20, 30, and 40 annotated volumes provides **supporting data-efficiency evidence**, not the study's identity or its title.

**Working paper title:** *Feature-Augmented Neural Cellular Automata for Jejunum-Ileum Segmentation in MR Enterography*.

**Primary, pre-specified scientific contrast:** Arm B versus Arm A at **n = 40**, on the same locked held-out test cohort, quantified with paired patient-level **3D Dice** differences. This contrast is required even if experimental Arm D becomes the preferred architecture during development. Secondary endpoints include HD95, computational cost, failures, sensitivity to training-set size, and optional Arm D mechanism analyses.

**Scope exclusions:** other-organ segmentation as a clinical output, disease diagnosis, deployment, claims of clinical readiness, claims of superiority over unrelated papers' non-equivalent splits, and using the locked test cohort to tune the model.

## 2. Approved v1.2 amendment record (relative to Iyad's v1.1)

| Topic | v1.2 rule | Why |
|---|---|---|
| Primary hypothesis | Always execute feature-augmented B versus image-only A at n = 40 in the confirmatory phase | Preserves the approved methodological claim, regardless of the development-design winner |
| Arm D | Secondary multi-class anatomical-context experiment; never substitute its result for the A/B primary contrast | Changes prediction task and loss, not only input features |
| Duplicate findings | Treat 102 unique scans and all reported ID groups as **provisional** until an independent, reproducible audit confirms them | Prior finding came from a report, not a verified pipeline artifact in this package |
| Split integrity | 40/10/52 is **conditional on confirming 102 eligible unique scans**; generate once, verify and freeze | Prevents cross-split leakage and unjustified changes |
| Selection versus validation | Selection30 is exploratory: validation10 plus 20 not in train20. The same 20 later join train40, so Selection30 is not an independent validation cohort | Prevents an inflated interpretation of validation performance |
| Test isolation | Never transfer the locked test images, labels, OR their alternate annotation versions onto Xavier | Alternate labels could reveal test-target masks |
| Training time | A fixed **200-batch benchmark** has fixed steps; a true full-dataset epoch changes with dataset size | Corrects the misleading claim that epoch cost never depends on n |
| Annotation differences | Alternate masks are evidence of label-version variability only, **not** validated inter-observer reliability or a model-accuracy ceiling | Observer identities and annotation provenance are unknown |
| Altered anatomy | Do not assert surgery or resection from an unusual label alone | Requires confirmed clinical history |
| Code licensing | Check OctreeNCA redistribution/modification rights before incorporating third-party source in a public repository | Publicly readable GitHub source does not necessarily grant a license |
| Reference standard | One released consensus reference mask per canonical scan; source paper reports multiple readers in annotation process | Avoids inaccurate 'one human annotator' framing |
| Research phases | Keep Xavier exploration distinct from confirmatory UoN HPC and final testing | Preserves permissions and scientific independence |
| Stage 1 split (D24, approved 27 Nov 2026) | Stage 1 becomes **1A** (Xavier environment and bounded CUDA validation) and **1B** (upstream reproduction); the GPU smoke test moves from Stage 0 to 1A | Environment work does not depend on the upstream license and has different risks |
| Private split artefacts (D31, approved 27 Nov 2026) | Real identifiers, the split manifest and its sidecar, the allowed-transfer manifest and restricted hashes stay in private research storage; never in the public repository | The repository is public (D16) |
| Evaluation definitions (D26, D27, D29, D30, approved 27 Nov 2026) | Empty-case Dice/HD95 rules, HD95 definition, spacing strata and Selection30 composition fixed as recorded in `docs/DECISIONS.md`. Threshold/inverse-mapping order (D28) still pending | Fixed before any comparison |

## 3. Dataset, anatomy, and source-of-truth rules

### 3.1 Source and labels

Source dataset: Zhong et al., *Scientific Data* (2025), DOI `10.1038/s41597-025-04760-z`; Zenodo dataset DOI `10.5281/zenodo.13839321`. Original package reportedly contains 114 indexed image/label NIfTI pairs with coronal T2 HASTE MRE volumes. These properties, headers, provenance, and redistribution terms must be verified from the acquired dataset.

**Positive ground truth is exactly `original_label == 3`.** In binary Arms A and B, label 3 maps to class 1; all other labels, including label 2 (duodenum), map to background 0. Name the task consistently **jejunum-ileum (small intestine excluding duodenum)** in code, charts, papers, metric exports, and model cards.

For Arm D only, construct auxiliary context classes from original annotations:

- class 0: source label 0 (background)
- class 1: source label 3 (jejunum-ileum; **only scored target**)
- class 2: source labels 4-10, called **lower-GI context**, including appendix and rectum; do not label this group merely 'colon'
- class 3: source labels 1-2, called **upper-GI context** (stomach and duodenum)

No auxiliary class changes the published anatomical target. Carefully audit non-overlapping remapping and whether any source label is unexpected.

### 3.2 Reported duplicate images: verification required

The supplied v1.1 plan states 114 files correspond to 102 unique images, with 11 duplicate-image groups. It lists exclusions `20,24,25,27,29,35,36,37,41,42,44,47` and proposes retaining the smallest numeric ID per group. **Neither the duplicate claim nor the independent scan/patient identity has been validated in this deliverable.** The data-audit stage must:

1. Check original file counts, file identity, NIfTI affine/orientation/voxel spacing, shape, and image-label alignment.
2. Compute reproducible hashes of decompressed image arrays with dtype, shape, endianness and canonical orientation handled explicitly; confirm exact-equality candidates voxel by voxel. Do not rely on an MD5 hash alone.
3. Detect any multiple scans from the same patient, if source metadata permits; splitting must be patient-disjoint, not merely file-disjoint.
4. Measure target-label Dice between duplicate-image label versions and record exact source IDs and provenance. Preserve alternate labels in an access-restricted **audit-only** location, not on Xavier.
5. Verify the proposed canonical-lowest-ID policy against the actual data. If choosing a different canonical policy, record a protocol amendment and clinical rationale.
6. Generate `reports/duplicate_audit.md` and a machine-readable manifest before the split is finalized.

**Do not claim inter-rater agreement or a segmentation Dice ceiling** from the alternate masks. We cannot assume different label versions represent independent readers or adjudications. A draft communication to dataset authors may be useful after confirmation; do not publicly accuse other studies of leakage without evidence of their exact splits.

### 3.3 Conditional frozen split

If and only if the audit confirms **102 eligible independent scans** and no patient-overlap issue:

- Test: **52 canonical cases**, locked away from training and Xavier.
- Development: **50 canonical cases**, comprising `train40 = 40` and `validation10 = 10`.
- Nested training subsets: `train20` subset `train30` subset `train40`.
- Fixed seed **42**; stratify by in-plane spacing rounded to 0.01 mm; strata with fewer than 3 cases are pooled into one "other" stratum and allocated by the same seeded procedure (D29). `train20` and `train30` are seeded stratified subsamples of `train40` (D30).
- Manifest must contain source dataset version and hashes, canonical/excluded IDs, duplicate-group identifiers, split assignments and ordering, algorithm version, and generation seed.

Use a separate `splits.json.sha256` sidecar file, or hash the canonical JSON *excluding* any self-checksum field. **Do not put a file's full SHA-256 within the same bytes being hashed**. Keep the manifest and sidecar in **private research storage** (D31, amending v1.2), validate their equality there with the same tested code that CI runs on synthetic fixtures, and treat revisions as signed-off amendments. Never silently overwrite the frozen split.

If eligibility count differs from 102, patient identity is ambiguous, or duplicate checks fail, **stop** and propose a revised split; do not force a 40/10/52 partition to make counts fit.

### 3.4 Security and data access tiers

- **Restricted data steward environment (local secured machine or institutional storage):** source data, all masks, alternate annotations, duplicate audit, full split, and later approved final evaluation. Only an authorized human/data-steward process holds the test unlock capability.
- **Xavier / development training:** only the 50 canonical development images and their labels, and only after the split/audit gate passes. No test images, test labels, or alternate annotations corresponding to test cases. Avoid copying `data/second_labels/` wholesale.
- **Public Git:** code, split-generation algorithm, tests on synthetic fixtures, summary tables and derived visuals allowed by source license. **No real case identifiers, split manifests, allowed-transfer manifests or restricted hashes** (D31, amending v1.2). No raw scans, private patient metadata, private credentials, large checkpoints without rights review, or unpublished restricted labels.

Instruction files and Claude hooks are **not** a security boundary. Use operating-system accounts, restricted object-storage access and transfer manifests. Verify every transfer has exactly the allowed IDs.

## 4. MRI preprocessing and inverse mapping

Implement as a versioned, tested, deterministic pipeline with zero dependency on ground-truth labels for feature generation.

1. Load each image and annotation with affine, voxel spacing and metadata. Fail on unexpected shapes, invalid affines, NaNs or suspicious image-label mismatch.
2. Reorient to canonical RAS using the NIfTI affine rather than guessing array axis order. Review representative image+mask overlays.
3. Resample **in-plane to 1.25 mm**, retaining the original approximately 4.8-mm through-plane spacing unless separately amended. Use linear interpolation for intensities and nearest-neighbor for labels.
4. Produce an image-derived provisional foreground mask, run N4 bias-field correction with fixed documented settings, derive/refine a body mask, and preserve all transform metadata.
5. Clip body-foreground MRI intensities to per-volume 1st and 99th percentiles; normalize to [0,1]. Handle empty or uniform volumes explicitly.
6. Crop around the body bounding box; pad in-plane dimensions to a multiple of 16 and z to 32 only when the chosen OctreeNCA hierarchy actually supports this. Validate stride/level shapes, padded-voxel loss masking and memory on Xavier. Never assume model layout from prostate filenames alone.
7. Cache preprocessed **MRI, label, body mask, spacing, affine, transform history and validity mask** in derived storage; cache *static* inputs only. Recompute Hessian features after per-sample augmentation.
8. Provide tested inverse transforms to the original patient image grid for final 3D patient-level metrics. Confirm label interpolation stays nearest-neighbor. Whether the binary threshold is applied before or after inverse mapping is **pending** (D28).
9. Create QC overlays for **every development scan**; Dr. Iyad approves the QC report before meaningful training.

## 5. Architecture, inputs and augmentation

### 5.1 Backbone and implementation constraints

Use the 3D OctreeNCA design described in Lemke et al., *OctreeNCA: Single-Pass 184 MP Segmentation on Consumer Hardware* (arXiv:2508.06993), official repository `https://github.com/MECLabTUDA/OctreeNCA`. The v1.1 plan points to `src/models/Model_OctreeNCA_3d_patching2.py` and `train_prostate2.py`; verify exact paths, source commit, dependencies and compatibility against Xavier's actual JetPack/Python/PyTorch environment. Published memory savings on prostate are **not** a measured Xavier bowel-training result.

Until licensing is resolved, reference the upstream project as a separate checkout pinned by commit, not as copied source to be redistributed. Record author contact and written permission/license evidence in `reports/license_review.md`. Upstream use, adaptation, modification, and redistribution rights must be assessed against the actual repository and institutional policies.

### 5.2 Defined model arms

| Arm | Input channels | Prediction task | Loss starting point | Hypothesis / status |
|---|---|---|---|---|
| A | 1: MRI | Binary jejunum-ileum vs background | Dice + BCE | **Mandatory control**, primary comparator at n=40 |
| B | 4: MRI + tubeness + blobness + dominant scale | Binary jejunum-ileum vs background | Dice + BCE | **Primary proposed method**, B-A at n=40 |
| D | Same 4 features as B | Four-class contextual labels, but score jejunum-ileum only | Dice + cross entropy | Secondary/exploratory anatomical-context arm |

Compare A/B with matched patient splits, seed indices, training schedule, patch sizes, optimizer, augmentation distribution, update steps, postprocessing, threshold-selection policy and metric code. Changes necessitated by input width must be reported, along with actual parameter counts. B vs D alters output and supervision and therefore cannot be described as a feature-only ablation.

### 5.3 Feature definitions

For Arms B and D, derive three **non-trainable** per-coronal-plane shape channels from the augmented normalized MRI, not from its label:

1. **Tubeness:** multiscale Hessian/Frangi-type response to candidate tubular intensity patterns.
2. **Blobness:** Hessian eigenvalue magnitude and ratio response to approximately rounded structures.
3. **Dominant scale:** scale index maximizing the defined response, encoded consistently.

Initial physical scales are **4, 8, 12 mm**; document whether each number represents Gaussian sigma versus physical structure diameter and verify scale normalization. Use physical in-plane spacing to convert mm to pixel-domain sigma. Record Hessian derivative conventions, eigenvalue signs, bright/dark response, padding, aggregation, clipping and scale encoding. Test synthetic tube/blob phantoms and parity against `skimage.feature.hessian_matrix` and eigenvalues on at least 3 development scans. Target correlation >0.99 **only after identical conventions have been established**; include absolute/relative error checks and attention to near-zero/constant-response edge cases.

**No body-depth or coordinate channels** in this OctreeNCA v1.2 baseline. This removes the old eight-channel coordinate-augmentation problem but does not remove the need to keep morphology channels aligned with augmented images.

### 5.4 Exact augmentation policy

- Sample a single conservative geometric augmentation per **whole coronal volume**: in-plane rotation up to +/-10 degrees and scaling by 0.9-1.1 around the body, with deterministic seed for reproducibility. Do not rotate indiscriminately through the thick-slice axis; verify the plane with the RAS affine.
- Apply **the same** geometric transform to MRI (linear interpolation), reference masks (nearest-neighbor), and image-derived body/validity masks (nearest-neighbor). Use a fixed physical output-grid convention and log the transform parameters. Reject transformations that crop target anatomy.
- Apply intensity gamma/noise to the warped MRI **before** Hessian generation; regenerate tubeness/blobness/scale after both geometric and intensity transforms. Do not rotate or interpolate cached pre-augmentation Hessian maps as substitutes for recalculation.
- Generate volume-consistent features before sampling training patches. MRI-only Arm A uses identical MRI/label augmentation distributions; A simply omits the three derived channels.
- No left-right flips by default. Validation/test have no stochastic augmentation. Include synthetic phantom and visual feature-alignment tests in CI or local tests.

## 6. Development design selection and learning curve

### 6.1 Xavier design-selection experiment: exploratory only

- Train A, B and D on the **same `train20`** once each under the controlled arm settings.
- Evaluate the candidate architectures on a **30-case Selection30 set** = `validation10` plus the 20 canonical training candidates in `train40` that are not in `train20`.
- These 30 cases are *development cases*. They are not an independent external or final holdout. Their use for architecture selection must be disclosed and never described as a 30-patient untouched validation set.
- Compute per-case Dice, HD95, paired A/B and B/D performance differences and 95% patient-bootstrap CIs. Use them only for design selection; no definitive hypothesis test at this stage.
- Provisional selection policy: higher mean jejunum-ileum Dice, with simpler design preferred for differences within approximately 0.02 unless clinically interpretable, substantial lower-GI confusion reduction supports D. Record all rules before examining selection outcomes. No automatic choice based on the locked test cohort.

### 6.2 Architecture freeze

Before any learning-curve training using more than 20 scans, commit `reports/design_freeze.md` containing the selection candidates, parameters, source hashes, selection cohort membership, metrics, rationale, checkpoint IDs and the exact frozen settings. If the preferred exploratory design is Arm D, **A vs B at n=40 remains obligatory in HPC**. Record all post-freeze amendments; do not silently retune based on provisional learning-curve outcomes.

### 6.3 Xavier learning curve: supporting evidence

Train the frozen preferred design with nested `train20`, `train30`, `train40` (one seed per size), and report Dice/HD95 on **only validation10**. An existing `train20` checkpoint may be reused solely if the configuration, split, seed and training schedule exactly match the frozen design. Otherwise retrain it.

Because 20 Selection30 cases later become part of train40, their earlier selection scores are **not** independent estimates of n=40 generalization. The validation10 set remains disjoint from every training subset, but has been reused during design selection, so its later learning-curve scores also remain **provisional**. The final locked test is the confirmatory evidence.

Do not define 'epoch' as a fixed 200 batches without qualification. A fixed-step benchmark is a different quantity from a full pass over a dataset. Log `steps`, `samples_seen`, `epochs` (as defined by sampler), batch size, effective patches/case, and actual runtime. Data-size increases do not necessarily increase per-step compute, but can change full-epoch duration and convergence budget.

## 7. Evaluation and statistical analysis

### 7.1 Metrics

- **Primary:** per-patient 3D Dice for jejunum-ileum, after mapping predictions to each patient's **original NIfTI grid**.
- **Secondary:** HD95 in physical millimetres: the larger of the two directed 95th-percentile surface distances, boundary-voxel surfaces, original-grid spacing (D27). Empty cases: Dice 1 when both prediction and reference are empty, 0 when exactly one is; HD95 not computed when either is empty and reported as a separate count (D26); mean/median/SD/IQR/range and CIs across test cases.
- **Mechanism:** for all arms, proportion and absolute count of predicted jejunum-ileum false-positive voxels located inside true lower-GI region; for Arm D, false-negative jejunum-ileum voxels assigned to predicted lower-GI class. Record denominators and do not compare non-equivalent definitions.
- **Efficiency:** trainable parameters, checkpoint size, GPU peak allocation and system memory (important on shared-memory Xavier), wall-clock training and inference, hardware/power mode and software versions.
- **Visual review:** best, typical, worst and clinically unusual cases; document failure modes, not just appealing overlays.

### 7.2 Primary contrast plan for HPC

**Estimand:** difference in average patient-level test Dice, **B minus A**, for models trained at n=40 under the predeclared matched experiment policy. Use at least three seeds for NCA unless a protocol amendment is approved. For each patient, aggregate the matched-seed predictions or per-seed Dice according to a frozen analysis rule; the default is to average each arm's **per-seed patient Dice**, then compute patient-level paired B-A differences. Report mean paired difference with a **two-sided 95% patient-level bootstrap interval**, with patient as the resampling unit and number of bootstrap replicates and seed sensitivity predeclared. A positive interval is evidence for benefit, not guaranteed by the architecture.

Pre-register checkpoint choice, binary threshold selection from development data, any connected-component postprocessing, all metrics, and evaluation scripts **before test unlock**. Report per-seed and aggregated results and seed variability. Treat other arms and learning curves as secondary exploratory analyses, and disclose multiple comparisons where relevant.

### 7.3 Practical development go/no-go (not a clinical accuracy threshold)

On the exploratory Selection30: mean Dice >=0.70 supports an HPC proposal; 0.60-0.70 supports investigation with documented failure analysis; <0.60 calls for an explicit negative-result review. These are project management thresholds only, **not** validated clinical performance requirements. A low result is not a reason to peek at test data or move cases across splits.

## 8. Xavier environment, staged execution, and review gates

**Hardware:** Dr. Iyad's NVIDIA Jetson AGX Xavier with 16 GB *shared* memory, headless. The supplied v1.1 plan reports Jetson Linux R35.6.4 and Python 3.8.10; re-check on-device before installation. R35.6.4 corresponds to JetPack 5.1.6; use NVIDIA-supported ARM64 PyTorch wheels/containers appropriate to the actual JetPack/CUDA stack. Do not assume a stock x86 PyTorch build or current CUDA 12 image is compatible.

**Stage 0 - Inventory and environment feasibility (execute first)**

- Run only **read-only** diagnostics first (`scripts/jetson_inventory.sh`) through the developer's own restricted SSH account. Record Jetson model, JetPack/L4T, Python/CPU architecture, CUDA toolkit availability, existing torch, storage, memory, power mode and thermals if available.
- Verify exact NVIDIA ARM64 PyTorch compatibility and OctreeNCA upstream commit/license; propose a pinned environment in `requirements-xavier.txt` / separate lockfile. No automatic firmware updates, OS flashing, destructive package changes, power-mode changes or privileged installs in this step.
- Stage exit evidence: `reports/stage_0.md` containing redacted diagnostic output, proposed installation commands, compatibility evidence, license status and Dr. Iyad's explicit authorization for any host changes.

**Stage 1A - Xavier environment and CUDA validation** (D24, approved 27 Nov 2026)

- Account separation (D21) by the human administrator, separated-layout workspace verification (W2), then the core environment (D22) with a bounded CUDA smoke test and, after a passing core record, the scientific environment (D23). No agent device access, no power-mode changes, no long benchmarks.
- Exit: `reports/stage_1a.md` with the redacted workspace check, environment records ending `result: pass`, and any deviations.

**Stage 1B - OctreeNCA reference reproduction** (formerly Stage 1)

- Under approved software and licensing terms, verify one forward/backward training step, memory, and a simple overfit control. Reproduce the published prostate experiment using `train_prostate2.py` if runtime and hardware permit, comparing to reported Dice ~0.8251 with a documented tolerance and protocol differences. If the full reproduction projects above 24 hours or is memory-infeasible, stop for scientific review, do not quietly substitute a different benchmark.
- Runs in the environment chosen under D18.
- Exit: `reports/stage_1b.md`, exact upstream commit, configurations, measured GPU memory/seconds per step and any replication gap.

**Stage 2 - Data integrity and pipeline**

- A restricted data steward independently validates the reported duplicates and patient grouping, generates the conditional split, isolates test/alternate labels, transfers only the 50 allowed development cases, and records transfer checksums. Run orientation/spacing, label-map, mask, inverse-transform, preprocessing and Hessian parity tests; Dr. Iyad inspects all development scan overlays.
- Exit: approved `reports/duplicate_audit.md`, `splits.json`, SHA-256 sidecar, allowed-transfer manifest, audit tests and `reports/stage_2.md`. If duplicates don't match the report, stop for amendment.

**Stage 3 - Xavier representative benchmark**

- Run a controlled **200-batch fixed-step** Arm D workload (not 'one true epoch') representative of expected resolution, patching, features, backpropagation and validation. Measure warmup, median step runtime, data-loader time, actual allocated/peak memory (and Jetson shared-memory metrics), failures and extrapolated training time. Include smaller A/B smoke steps to detect model-specific issues. Project total time using measured steps/epoch, not the false assumption of constant full-epoch time.
- Exit: `reports/stage_3.md` and a **measured** runtime/budget matrix. If any projected training run >24 hours or memory becomes unsafe, stop and request Dr. Iyad's approval before Stage 4.

**Stage 4 - One-seed exploratory arm screen**

- Only after Stage 3 approval: train A/B/D on train20. Evaluate on Selection30 only. Produce per-case CSV, mean/intervals and overlays. No test data used.
- Exit: `reports/stage_4.md` and reproducible experiment manifests.

**Stage 5 - Freeze design**

- Predeclare/execute selection rule; archive `reports/design_freeze.md` signed by Dr. Iyad, exact code hash and any selected checkpoint. Optional second seed of top candidates requires time/compute approval.

**Stage 6 - Provisional learning curve**

- Run frozen preferred design on train20/train30/train40 at one seed each (reuse n20 only if strictly equivalent); evaluate validation10 only. Record accuracy, uncertainty and true end-to-end runtime.
- Exit: `reports/stage_6.md`, reproducible configs, proposed UoN HPC resource request and any deviations.

**Universal stage gate:** Write a report, attach raw logs/artifact hashes and create a reviewed PR; do not self-approve or automatically start the next stage. No training run projected above **24 hours** without Dr. Iyad's explicit authorization. Maintain raw data integrity and never run as an unbounded unattended process.

## 9. Confirmatory HPC phase - proposed, not yet authorized

University of Nottingham (UoN) HPC access is **proposed, not confirmed**. The full matrix and compute budget require measured Xavier results, resource availability, and Dr. Iyad's separate sign-off. Minimum scientific requirements:

1. **Mandatory n=40 A/B comparison** with >=3 matched NCA seeds under a predeclared evaluation policy; this is the primary methodological test even if Arm D was selected as exploratory winner.
2. **Mandatory nnU-Net v2 baselines at n=20 and n=40**, on the identical canonical patient partitions and locked final test. Prefer >=3 seeds; any reduction must be specifically approved, justified and prominently disclosed. Configure nnU-Net so it cannot use test cases for auto-planning/validation, and override default folds with the fixed development split.
3. Supporting frozen-design n=20, n=30 and n=40 learning curve with >=3 NCA seeds. The n=30 nnU-Net point and additional Arm D runs are optional and separately cost-gated.
4. Validate faithful preprocessing, size of input volumes, model-checkpoint selection using development data only, and reproducible run manifests.
5. Freeze all tested checkpoints, seeds, script versions, postprocessing, endpoints and statistical analysis; have a data steward **unlock the 52-case test cohort once** for a prespecified final campaign. A campaign may contain all predeclared models, but the team must not use test feedback to retune.
6. Report per-case, per-seed Dice and HD95, paired bootstrap intervals, failure modes, resource use, limitations and any deviations. If a fatal bug requires rerunning testing, disclose the compromised holdout status and document the protocol amendment.

## 10. Budget and compute policy

Xavier development is opportunistic use of an existing device; its **time, energy, storage and opportunity costs still count**. No fixed training runtime or cloud cost is claimed until Stage 3 measurements. The earlier approximately USD 1,000 cloud budget is a contingency reserve, **not an authorized expense**; expected UoN HPC allocation and any charges must be confirmed. For each run estimate:

`cost_per_run = GPU_hours * billed_hourly_rate + persistent_storage + expected_failure_and_retry_overhead`

For a free institutional allocation, still record GPU-hours, queue time, job quotas and transfer/storage requirements. Keep a run ledger, stop limits, low-storage alerts and checkpoint backups. Never leave paid GPU resources idle for code review.

## 11. Reproducibility and experiment identifiers

Each stage must be restartable from a clean clone and documented dataset access procedure. Every training/evaluation run writes an immutable **run manifest** with:

- research-plan version and stage; exact Git commit and upstream commit(s);
- dataset/archive version, checksum, split manifest digest, allowed scan IDs;
- Python/PyTorch/CUDA/JetPack versions; host/GPU type, memory and power mode;
- architecture arm, feature definitions, patch/level/step configuration, loss and optimizer;
- augmentation policy, preprocessing hash, random seed(s), batch size, steps, epochs, patch sampling details;
- train/validation case IDs only, validation checkpoint-selection rule and timestamp;
- all metric implementation versions, wall-clock time, peak GPU/system memory and checkpoint hashes;
- failure codes and deviations from protocol.

Keep raw MRI scans and checkpoint files outside Git; publish training recipes, model weights only after licensing and dataset/IP review, and tables/aggregates with valid source attribution. Make synthetic test data available to exercise the pipeline without downloading medical scans.

## 12. Repo layout and workflow

Recommended files/directories:

```text
README.md
CLAUDE.md
.github/workflows/research-contract.yml
docs/DEVELOPMENT_PLAN_v1.2.md
docs/DECISIONS.md
docs/STAGE_0_CLAUDE_HANDOFF.md
docs/DATA_GOVERNANCE.md
docs/RUN_MATRIX.md
scripts/jetson_inventory.sh
reports/stage_0_TEMPLATE.md
src/                     # built by approved implementation PRs
tests/                   # added with features
configs/                 # pinned, versioned run settings
artifacts/               # ignored; no MRI or test data in Git
data/                    # ignored; no MRI or test data in Git
```

**GitHub process:** One issue per stage/subsystem; branch names `stage0/jetson-env`, `stage1/octree-repro`, `stage2/data-audit`, `stage3/benchmark`; small tested PRs; no PR merger without independent review, stage artifacts and Dr. Iyad gate for scientifically consequential decisions. CI validates scripts and policy, unit tests, data-split integrity with synthetic fixtures, then optional GPU smoke via a *private* runner. Do not put private patient data into hosted CI logs.

**Agent process:** Claude Code follows `CLAUDE.md` but is not allowed to grant its own scientific approval, install system-level packages, disclose credentials, transfer test data, or merge stage-gated PRs. Human authorization and infrastructure access control are separate.

## 13. Limitations and reporting discipline

- **Consensus reference limitation:** One released consensus annotation for each retained scan; no independent per-rater set for a formal interobserver analysis. Some alternate label versions are reported, but their provenance is unknown.
- **Small development cohorts:** Selection30 is adaptively used; validation10 is only ten scans and also used in early selection; provisional scores have uncertainty and potential selection optimism.
- **Cohort and external generalization:** source appears to be a specific MRE/Crohn's cohort with particular scanners/protocols; external hospital and scanner generalization is unestablished.
- **Duplicate ambiguity:** exact-image duplicates may be revised masks, repeat exports or other cases; cannot be assumed separate independent patients. Published benchmark bias is a hypothesis until exact splits are inspected.
- **Physical anisotropy and label quality:** thick slices and variable bowel boundaries can limit surface distance reliability and clinical conclusions.
- **Anatomical variants:** unusual image/label structures must be clinically adjudicated; do not infer surgery solely from missing caecum annotations.
- **Method dependency:** license, CUDA/ARM64 support, memory feasibility and institutional HPC allocation have unresolved gates.
- **No clinical claims:** an exploratory >=0.70 Dice threshold is not proof of clinical usefulness or safety.

## 14. Required deliverables and exit checklist

- [ ] Stage 0 Xavier inventory, supported toolchain proposal and license findings reviewed.
- [ ] Stage 1 OctreeNCA reference reproduction or documented, authorized feasibility exception.
- [ ] Independent 114-file duplicate audit and clinical reconciliation of canonical cases.
- [ ] Frozen patient-disjoint split (40/10/52 if 102 eligible) with checksums and allowed-transfer manifest.
- [ ] Data preprocessing, inverse-grid metric, Hessian and augmentation unit/integration tests.
- [ ] QC overlays reviewed by Dr. Iyad without test-cohort exposure.
- [ ] Stage 3 measured steps, memory, run projections and budget.
- [ ] Stage 4 A/B/D development evidence and frozen architecture rationale.
- [ ] Stage 6 provisional 20/30/40 learning curve and UoN HPC proposal.
- [ ] Separate HPC authorization, confirmatory A/B n40, required nnU-Net baselines n20/n40 and repeated-seed study.
- [ ] One-time frozen 52-case final evaluation and audit trail.
- [ ] Publication license, dataset-rights verification, code/tests/documentation, reproducible release, and DOI when authorized.

## 15. External references

1. Zhong Z et al., *A comprehensive dataset of magnetic resonance enterography images with intestinal segment annotations*. *Scientific Data* (2025). https://doi.org/10.1038/s41597-025-04760-z
2. Dataset Zenodo record: https://doi.org/10.5281/zenodo.13839321
3. Lemke N et al., *OctreeNCA: Single-Pass 184 MP Segmentation on Consumer Hardware*. https://arxiv.org/abs/2508.06993
4. Upstream OctreeNCA: https://github.com/MECLabTUDA/OctreeNCA
5. nnU-Net v2: https://github.com/MIC-DKFZ/nnUNet
6. NVIDIA JetPack 5.1.6/R35.6.4: https://developer.nvidia.com/embedded/jetson-linux-r3564
7. NVIDIA PyTorch for Jetson: https://docs.nvidia.com/deeplearning/frameworks/install-pytorch-jetson-platform/index.html
8. Rahman A et al., *A Two-Stage Deep Learning Framework for Segmentation of Ten Gastrointestinal Organs from Coronal MR Enterography*. https://arxiv.org/abs/2604.17118
9. CLAIM 2024 checklist: https://pubs.rsna.org/doi/10.1148/ryai.240300

---

**Change control:** This v1.2 document reflects Dr. Iyad's approval of the methodological corrections described in the conversation, with the amendments approved on 27 Nov 2026 (D24 stage split; D26, D27, D29, D30 evaluation and split definitions; D31 private split artefacts) recorded in section 2 and `docs/DECISIONS.md`. It is not evidence that the dataset, device, model or HPC environment has been independently verified. Deviations require an explicit decision-log entry and reviewer acknowledgment before they affect the primary experiment.
