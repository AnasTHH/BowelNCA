# OctreeNCA reuse and publication license review

**Status: PARTLY RESOLVED. Written author statement received; formal upstream license NOT yet verified. No license is granted by this file. Not legal advice.**
Last updated: 26 Nov 2026.
**Internal licensing decision deadline: 16 December 2026** (see `DECISIONS.md` D17).

## Status at a glance (26 Nov 2026)

Two separate pieces of evidence are tracked. Only the second is a license that can be cited for publication.

| Evidence | Status | Detail |
|---|---|---|
| **A. Written author statement** | **Received 26 Nov 2026** | In reply to the 25 Nov 2026 inquiry, an upstream author (a co-author of arXiv:2508.06993) stated in writing that OctreeNCA should be considered MIT-licensed and that the missing license file will be added upstream. The correspondence is private and is not reproduced here |
| **B. Formal upstream LICENSE file** | **PENDING** | Re-checked 26 Nov 2026: upstream still has one commit, `70f774232305b76330a75edef9fddda8ec960cab`, with no LICENSE file. To be verified when a commit adding it appears: the license text, the copyright holder line, and that it covers the code at the commit we pin |

Not yet established by either piece of evidence:
- whether the statement is made for all copyright holders (the authors and/or their institution);
- the provenance and licenses of individual files (for example baseline implementations);
- the University of Nottingham view on internal use;
- dataset rights (separate check, below).

## Findings at the pinned commit

| Item | Finding | Evidence |
|---|---|---|
| Official upstream | https://github.com/MECLabTUDA/OctreeNCA | Linked from arXiv:2508.06993 and the README ("official implementation ... accepted at BMVC 2025") |
| Exact commit inspected | `70f774232305b76330a75edef9fddda8ec960cab` ("init", 2025-08-13T14:17:57+02:00) | `git clone` + `git ls-remote` on 25 Nov 2026: one branch (`master`), one commit, HEAD = this SHA |
| Root LICENSE / COPYING / NOTICE | **None** (re-checked 26 Nov 2026: upstream HEAD unchanged) | No such file among the 222 tracked files |
| SPDX headers / copyright notices in source | **None** in any `.py`/`.cu` file | `grep -ril "license\|copyright\|SPDX"` matched only one notebook output cell, not a license |
| Packaging metadata declaring a license | **None** (no `setup.py`/`pyproject.toml` with license; `nca_cuda_compile.py` has none) | Repository tree |
| README license statement | **None**; README asks for citation only | README at the pinned commit |
| GitHub API license field | Not retrievable from this environment (proxy 403); the tree itself contains no license file, so GitHub cannot detect one | |
| Provenance of individual files | **Not assessed.** Some files implement baseline models that may have their own upstream origins and licenses; this review makes no finding about them | To be clarified with the authors in the license inquiry |
| Related lab repositories | `MECLabTUDA/M3D-NCA` (predecessor from the same lab) is **MIT**, commit `f53f164a8445820055c08a3d78efc911b80b5571`; `MECLabTUDA/Med-NCA` is MIT (`a844a72a1099db165d57f2d87bbcd5afd23586cb`) | Shallow clones, 25 Nov 2026. This does **not** license OctreeNCA, but suggests the lab normally permits open reuse, so a request is likely to succeed |

## What this means

Until a license file exists upstream, the repository itself still carries **no license**, and the default there is all rights reserved. The written author statement (evidence A) is a strong indication of intent and supports internal research use, but it is not yet a license text that can be cited, attributed and reproduced in a public release.

| Use | Status |
|---|---|
| Read the paper and implement the published method independently | Permissible; method ideas are not protected by copyright |
| Run an **unmodified separate pinned checkout** internally (Stage 1B reproduction) | **Supported by the written author statement (A).** Still needs the owner and Dr. Iyad to record the D17 decision, and the Stage 1A gate. UoN view: pending |
| Modify upstream code and run it internally, in the separate checkout | **Supported by A** for internal research; record every local patch against the pinned commit |
| Copy, adapt or vendor upstream code into **this public repo** | **Blocked until B is verified** and the MIT notice requirements (copyright and permission notice) are met for every copied file |
| Publish trained weights or derivative assets from upstream code | **Blocked until B is verified**, plus dataset-rights review and publication approval |

**Impact on the plan:** a clean-room re-implementation now looks unnecessary. Stage 1B can be planned on the upstream code under the author statement, subject to the D17 decision and the Stage 1A gate. Upstream code stays a **separate pinned checkout** outside this repository until B is verified.

## Recommended resolution (ranked)

1. **Ask the authors to add an OSI license to the repository** (ideally MIT, matching M3D-NCA). **In progress:** inquiry sent 25 Nov 2026; written reply received 26 Nov 2026 confirming MIT and that the license file will be added upstream. Remaining: verify the LICENSE file when it lands, then pin that commit. Whether any files carry separate third-party licenses is still to be confirmed.
2. **Written permission** for this project (use, modification, publication of derived code and weights) if they won't add a license. Archive it privately and summarise it in `reports/license_review.md`.
3. **Clean-room re-implementation** from the paper, if neither a license nor a written grant is in hand by the **16 December 2026** decision point. Higher engineering cost, and reproduction fidelity to the published prostate Dice becomes harder to claim. Clean-room hygiene: the person writing the implementation must not read the upstream source.

## Still pending

- Upstream LICENSE file (evidence B): **PENDING**. When it appears: record the upstream commit that adds it, verify text, holder and coverage, and decide whether to re-pin from `70f7742` to that commit (a Stage 1B input; recorded as a decision).
- Third-party file provenance inside upstream: **PENDING** (ask when acknowledging the LICENSE commit).
- Decision by 16 Dec 2026 (owner + Dr. Iyad, D17): proceed with upstream under the author statement for internal use, publication only after B; extend; or clean-room. Recommended: proceed with upstream, internal only, until B is verified.
- Institutional (UoN) review of internal use: **PENDING**.
- Permission to distribute trained weights and derivative assets: **PENDING**.
- Private archiving of the correspondence (outside this repository): **PENDING confirmation by the project owner**.
- Dataset (Zenodo 10.5281/zenodo.13839321) license and overlay-publication rights: separate check, **PENDING**.

Until evidence B is verified, keep upstream source in a **separate, pinned checkout** outside this repository (`OctreeNCA/`, `upstream/` and `third_party/` are git-ignored). Do not treat public GitHub visibility as an open-source license.
