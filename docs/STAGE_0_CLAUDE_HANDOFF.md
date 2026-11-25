# Claude Code handoff: Stage 0 - Xavier environment inventory

**Project:** Feature-Augmented OctreeNCA for Jejunum-Ileum Segmentation in MRE
**Approved research plan:** `docs/DEVELOPMENT_PLAN_v1.2.md`
**Current permission:** Read-only environment analysis and a documented proposal; no installation or training.

## Paste this prompt into Claude Code, while working in this directory

> Read `CLAUDE.md`, `docs/DEVELOPMENT_PLAN_v1.2.md` (especially Sections 3, 5, 8, 11) and `docs/STAGE_GATES.md` in full. Implement **Stage 0 only**. Confirm that this is the NVIDIA AGX Xavier by running `bash scripts/jetson_inventory.sh`, collecting non-sensitive local output. Determine the installed Jetson Linux/JetPack, CUDA, Python, ARM64, existing PyTorch availability, RAM/storage and power mode. Do not use sudo; do not install or upgrade packages; do not change clock/power mode; do not fetch MRI data; do not start a training job. Research which NVIDIA-supported PyTorch wheel/container actually matches this specific release and Python ABI, but only propose installation commands for human approval. Inspect the exact OctreeNCA upstream repository commit and document the redistribution/license issue without copying its implementation into this repository. Write `reports/stage_0.md` according to `reports/stage_0_TEMPLATE.md`, redacting personal hostnames/usernames and any network information. Propose a reproducible environment lock plan and next steps. Run local checks of your authored shell/markdown only. Create a Stage 0 PR and **stop**; do not claim Stage 0 or licensing is approved until reviewers sign off.

## Stage 0 evidence checklist

- [ ] Exact device model, processor architecture and Jetson Linux release captured.
- [ ] Python and CUDA versions, installed PyTorch version and `torch.cuda.is_available()` captured, including absent-import cases.
- [ ] Available memory/storage and cooling/power limits noted.
- [ ] NVIDIA ARM64 PyTorch version and wheel URL/container tag checked against observed JetPack and Python ABI, not installed.
- [ ] OctreeNCA source commit identified and license/redistribution status recorded separately.
- [ ] Installation commands proposed only (no privileged changes executed).
- [ ] `reports/stage_0.md` created with evidence and reproducibility notes.
- [ ] Research lead reviews and approves any host mutation or progression to Stage 1.

## Suggested PR title

`stage0: Xavier inventory and pinned-environment proposal (no host changes)`

## Suggested GitHub issue

**Stage 0 - Xavier reproducibility preflight**. Acceptance criteria: all items above, redacted evidence, zero raw scans, zero privileged changes, next-stage gate explicitly pending.
