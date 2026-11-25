# OctreeNCA reuse and publication license review

**Status: UNRESOLVED. No license is granted by this file. Not legal advice.**
Last updated: 25 Nov 2026 (Stage 0, issue #1, review round 1).
**Internal licensing decision deadline (proposed): 16 December 2026** (see `DECISIONS.md` D17).

## Findings at the pinned commit

| Item | Finding | Evidence |
|---|---|---|
| Official upstream | https://github.com/MECLabTUDA/OctreeNCA | Linked from arXiv:2508.06993 and the README ("official implementation ... accepted at BMVC 2025") |
| Exact commit inspected | `70f774232305b76330a75edef9fddda8ec960cab` ("init", 2025-08-13T14:17:57+02:00) | `git clone` + `git ls-remote` on 25 Nov 2026: one branch (`master`), one commit, HEAD = this SHA |
| Root LICENSE / COPYING / NOTICE | **None** | No such file among the 222 tracked files |
| SPDX headers / copyright notices in source | **None** in any `.py`/`.cu` file | `grep -ril "license\|copyright\|SPDX"` matched only one notebook output cell, not a license |
| Packaging metadata declaring a license | **None** (no `setup.py`/`pyproject.toml` with license; `nca_cuda_compile.py` has none) | Repository tree |
| README license statement | **None**; README asks for citation only | README at the pinned commit |
| GitHub API license field | Not retrievable from this environment (proxy 403); the tree itself contains no license file, so GitHub cannot detect one | |
| Provenance of individual files | **Not assessed.** Some files implement baseline models that may have their own upstream origins and licenses; this review makes no finding about them | To be clarified with the authors in the license inquiry |
| Related lab repositories | `MECLabTUDA/M3D-NCA` (predecessor, co-author J. Kalkhof) is **MIT**, commit `f53f164a8445820055c08a3d78efc911b80b5571`; `MECLabTUDA/Med-NCA` is MIT (`a844a72a1099db165d57f2d87bbcd5afd23586cb`) | Shallow clones, 25 Nov 2026. This does **not** license OctreeNCA, but suggests the lab normally permits open reuse, so a request is likely to succeed |

## What this means

With no license, the default is **all rights reserved** by the copyright holders (the authors and/or their institution, TU Darmstadt). GitHub's Terms of Service only let other users view and fork the code within GitHub. They give no right to copy, modify or redistribute it elsewhere, including into this public repository.

| Use | Status |
|---|---|
| Read the paper and implement the published method independently (clean room, no copied code) | Generally permissible; method ideas are not protected by copyright. Must be done without copying code or close paraphrase |
| Run an **unmodified separate checkout** internally for Stage 1 reproduction | **Grey area.** Needs institutional (UoN) research-office view, or an author grant, before Stage 1 starts |
| Modify upstream code and run it internally | Requires a grant or license |
| Copy, adapt or vendor upstream code into **this public repo** | **Blocked** until a license or written grant exists |
| Publish trained weights or derivative assets from upstream code | **Blocked** until a license or written grant exists, plus dataset-rights review |

**Impact on the plan:** Stage 1 (reference reproduction) and every later stage that builds on upstream code are blocked on this gate. Plan Section 5.1 assumes upstream code is usable. Without rights, the only path is an independent re-implementation, which would change the Stage 1 scope and needs Dr. Iyad's approval.

## Recommended resolution (ranked)

1. **Ask the authors to add an OSI license to the repository** (ideally MIT, matching M3D-NCA). Contact: the authors listed on arXiv:2508.06993 (MECLab, TU Darmstadt), using addresses from the paper or institutional pages, verified by the sender. This is the cleanest outcome and benefits everyone. Also ask whether any files carry separate third-party licenses. A draft inquiry exists outside the public repository and is sent only by the project owner.
2. **Written permission** for this project (use, modification, publication of derived code and weights) if they won't add a license. Archive it privately and summarise it in `reports/license_review.md`.
3. **Clean-room re-implementation** from the paper, if neither a license nor a written grant is in hand by the **16 December 2026** decision point. Higher engineering cost, and reproduction fidelity to the published prostate Dice becomes harder to claim. Clean-room hygiene: the person writing the implementation must not read the upstream source.

## Still pending

- Upstream author contact and inquiry date: **drafted, not sent** (owner action; it is an outward-facing message).
- Decision at 16 Dec 2026 (owner + Dr. Iyad): proceed with upstream under license/grant, extend the wait, or authorize clean-room re-implementation.
- Institutional (UoN) review of internal use: **PENDING**.
- Permission to distribute trained weights and derivative assets: **PENDING**.
- Evidence/response archived privately: **PENDING**.
- Dataset (Zenodo 10.5281/zenodo.13839321) license and overlay-publication rights: separate check, **PENDING**.

Until resolved, keep upstream source in a **separate, pinned checkout** outside this repository (`OctreeNCA/`, `upstream/` and `third_party/` are git-ignored). Do not treat public GitHub visibility as an open-source license.
