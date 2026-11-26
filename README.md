# Feature-Augmented OctreeNCA for Jejunum-Ileum MRI Segmentation

**Status: research development starter, not trained or validated.**

> **This repository is public by design, from day one.** Everything committed here, including issues, pull requests, CI logs and review comments, is world-readable. Never commit or paste raw MRI, masks, patient metadata, unredacted device logs, hostnames, usernames, IP addresses, credentials or upstream OctreeNCA source. See [`docs/DATA_GOVERNANCE.md`](docs/DATA_GOVERNANCE.md).

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
- A Git ignore policy (`.gitignore`) and a repository-policy CI workflow (`.github/workflows/research-contract.yml`) that runs ShellCheck, a no-data/no-secrets policy check and regression tests on GitHub-hosted runners. The tests catch known mistakes; they are not a security sandbox.

## Xavier status (Stage 0, 26 Nov 2026)

The read-only inventory was run manually by the project owner (script commit `e26e3db`). Observed: JetPack 5.1.6, L4T R35.6.4, Python 3.8.10, CUDA 11.4, cuDNN 8.6, TensorRT 8.5; root eMMC 4.5 GiB free, NVMe `/data` 363 GiB free. The research workspace is `/data/bowelnca` (D20). See [`reports/stage_0.md`](reports/stage_0.md).

1. **Evidence.** A sanitized transcription waits for human redaction approval in `reports/evidence-draft/` (header `REDACTION-STATUS: PENDING-HUMAN-APPROVAL`). After review it moves to `reports/evidence/` with the header `REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>`. CI enforces both headers and scans for network addresses, hostnames, home paths and key material. Raw logs stay private and git-ignored.
2. **Workspace check (read-only):** `bash scripts/verify_workspace.sh` (add `--write-test` for a 1 MiB temp file that is verified and removed).
3. **Installation: proposed, not approved.** [`docs/XAVIER_ENVIRONMENT.md`](docs/XAVIER_ENVIRONMENT.md) describes a hash-locked Python 3.8 venv on the NVMe using NVIDIA's JetPack 5 PyTorch wheel. The script in `scripts/proposed/` refuses to run without a recorded approval token.
4. **Access and security:** [`docs/XAVIER_ACCESS_AND_SECURITY.md`](docs/XAVIER_ACCESS_AND_SECURITY.md) (account separation, groups, dataset isolation).
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
| `scripts/check_repo_policy.sh` | Public-repo policy check (no data, weights, secrets) |
| `scripts/verify_workspace.sh` | Non-destructive Xavier workspace verification |
| `scripts/proposed/install_xavier_env.sh` | Proposed installer (**not approved**; refuses to run without an approval token) |
| `env/xavier/` | Hash-locked dependency sets for the Xavier (bootstrap, core, scientific) |
| `docs/XAVIER_ENVIRONMENT.md` | Installation proposal and dependency assessment |
| `docs/XAVIER_ACCESS_AND_SECURITY.md` | Access, security and data-governance assessment |
| `reports/evidence-draft/` | Sanitized evidence awaiting human redaction approval |
| `tests/` | Regression tests for the inventory script, repository policy and proposed scripts (not security guarantees) |
| `reports/stage_0.md` | Stage 0 report (pending review) |
| `reports/stage_0_TEMPLATE.md` | Stage 0 evidence format |

## Publication

The **source repository** is public from day one. What remains gated is the release of anything beyond engineering code and documentation: trained weights, scientific results, figures derived from patient images, upstream-derived OctreeNCA code, a tagged software release and DOI. Each requires rights checks, reproducibility review and scientific authorization. No raw clinical datasets are distributed in this repository. Dataset attribution belongs to the original Zhong et al. Zenodo record. Do not add an unverified upstream license or cite an unmeasured result.
