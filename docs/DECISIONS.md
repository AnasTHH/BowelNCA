# Scientific decisions and open gates

| ID | Decision | Status | Authority / evidence |
|---|---|---|---|
| D01 | Target source label 3 only; name jejunum-ileum excluding duodenum | Approved | Dr. Iyad, Blueprint v1.1 |
| D02 | Primary contrast feature-augmented NCA (B) vs image-only (A) at n=40 | Approved | Dr. Iyad, v1.2 correction |
| D03 | Arm D contextual multi-class experiment is secondary | Approved | Dr. Iyad, v1.2 correction |
| D04 | 20/30/40 train sizes are evidence of data efficiency, not research title | Approved | Research discussion |
| D05 | 3D OctreeNCA backbone, four-channel proposed approach | Accepted design direction | Dr. Iyad Development Plan v1.1; verify compatibility |
| D06 | Reported 102 unique scans, 11 duplicate-image groups | **Unverified** | Requires independent dataset audit |
| D07 | 40 train / 10 validation / 52 locked test cases | Conditional approval | Only if audit verifies 102 eligible independent scans |
| D08 | Selection30 used only for exploratory design ranking | Approved with disclosure | Dr. Iyad, v1.2 correction |
| D09 | nnU-Net v2 required baseline at n=20 and n=40 | Approved research requirement | Dr. Iyad |
| D10 | Final test opened only after checkpoint and analysis freeze | Approved policy; not authorized to execute | Research protocol |
| D11 | UoN HPC as proposed confirmatory execution environment | Pending access and cost | UoN allocation not verified |
| D12 | Upstream OctreeNCA code licensing / redistribution | **Open gate** | Verify explicit rights before publication |
| D13 | Alternative annotations are audit-only, not rater ceiling | Approved | Dr. Iyad, v1.2 correction |
| D14 | Start Stage 0 read-only Xavier verification | Authorized to prepare and execute | User approval to begin on 25 Nov 2026 |
| D15 | Host changes, long training, paid GPU spend, full HPC matrix, public release of weights/results/upstream-derived code | **Not authorized by this package** | Require separately recorded sign-off |
| D16 | Source repository is public from day one (code, docs, redacted reports only) | Owner decision; recorded, pending Dr. Iyad acknowledgment | Anas, 25 Nov 2026; Stage 0 PR. Does not authorize release of weights, results or upstream-derived code (D12, D15) |
| D17 | Internal OctreeNCA licensing decision deadline: 16 Dec 2026 (license/grant, extend, or clean-room) | **Proposed**; supported by Anas (re-review, 25 Nov 2026); pending Dr. Iyad | PR #2 review, 25 Nov 2026. License inquiry sent 25 Nov 2026, awaiting response |
| D18 | Separate Xavier development environment (JetPack 5.1.x, Python 3.8, CUDA 11.4) from a modern CUDA reference environment for upstream reproduction | **Proposed**; supported by Anas (re-review, 25 Nov 2026); pending Dr. Iyad | PR #2 review, 25 Nov 2026; `reports/stage_0.md` section 2.1 |
| D19 | Parallel architecture-independent development while the license is pending: initial priority P1, P2, P4, P7, P8; synthetic data only, CPU only | **Proposed**; supported by Anas (re-review, 25 Nov 2026); **not approved, not started**; pending Dr. Iyad's scientific approval | `docs/proposals/PARALLEL_DEVELOPMENT_WHILE_LICENSE_PENDING.md` |

Any changed scientific decision requires a new log row specifying date, requester, approving reviewer, rationale, affected protocol version and impact on published comparisons.
