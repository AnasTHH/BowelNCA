# Stage 0 - Xavier system and compatibility report (template)

**Date/time (UTC):** [fill]
**Device owner/reviewer:** Dr. Iyad Naim
**Engineer:** [fill]
**Git commit:** [fill]
**Status:** Draft; no stage approved by this template

## 1. System facts (observed; sanitized)

| Item | Value | Evidence |
|---|---|---|
| Exact Jetson model | | |
| Kernel / Jetson Linux / JetPack | | |
| CPU ABI / Python version | | |
| `nvcc` and CUDA runtime | | |
| PyTorch version / CUDA available | | |
| Total/free RAM and swap | | |
| Disk free space | | |
| Current power mode | | |
| GPU/thermal status | | |

## 2. NVIDIA PyTorch compatibility determination

- Verified wheel/container and exact URL/tag:
- Wheel Python ABI (`cp38`, etc.) and ARM64:
- Corresponding JetPack/L4T/CUDA versions:
- Verified CUDA smoke result (if already installed):
- Installation actions proposed (NOT executed):

## 3. Upstream OctreeNCA and license

- Commit/tag:
- Code path(s) and reproducibility findings:
- Exact license findings, author contacts and evidence:
- Redistribution permission status: **unresolved unless documented**

## 4. Redacted evidence

- Inventory log path and SHA-256:
- Any unexpected errors:
- Data transfer or training executed? **No**
- Privileged changes executed? **No**

## 5. Exit recommendation and open blockers

- Is environment suitable for Stage 1 smoke testing?
- Required disk/OS compatibility fixes (proposals only):
- License gate:
- Safety/power/cooling risks:
- Reviewer sign-off (name, date, decision):
