REDACTION-STATUS: PENDING-HUMAN-APPROVAL
<!-- After review: move to reports/evidence/ and replace line 1 with
     "REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>". CI enforces both headers. -->

# Stage 0 Xavier inventory: sanitized summary (draft for human redaction approval)

## Provenance

| Field | Value |
|---|---|
| Collected (UTC) | 2026-11-26T07:20:16Z |
| Collected by | Project owner, manually, over the project's private access path (not by an agent) |
| Script | `scripts/jetson_inventory.sh` at commit `e26e3db9824613d37a7577d4c87d6f213408ee83` |
| Script Git blob hash | `16b7cb9feb78a12cf5ef31b852bb01a1ad97b81a`. Independently re-computed from the repository with `git rev-parse e26e3db:scripts/jetson_inventory.sh`: **match** |
| Account | Dedicated project account (unprivileged invocation; no sudo used for the inventory) |
| Form of this file | **Structured transcription of owner-reported values**, prepared by the agent. The raw log was not seen by the agent and is not committed. The owner keeps it privately |
| Redactions | No hostnames, usernames, network addresses, VPN details, SSH material, serial numbers or home paths are included |

## Hardware

| Item | Observed |
|---|---|
| Device model | NVIDIA Jetson AGX Xavier |
| SoC | NVIDIA Tegra194 |
| Architecture | aarch64 |
| Memory | 16 GB shared CPU/GPU class; 14 GiB visible to Linux; 13 GiB available at measurement |
| Swap | 7.3 GiB compressed-RAM swap (zram) |
| Power mode (query only) | MAXN. The unprivileged `nvpmodel -q` could not read some kernel-level EMC parameters |
| Thermal at measurement | CPU 39.5 °C, GPU 39.5 °C |

## Operating system and NVIDIA stack

| Item | Observed |
|---|---|
| OS | Ubuntu 20.04.6 LTS |
| Kernel | 5.10.216-tegra |
| L4T | R35.6.4 |
| JetPack (`nvidia-jetpack`) | 5.1.6-b5 |
| CUDA toolkit package | 11.4.19-1 |
| `nvcc` | 11.4.315, at `/usr/local/cuda/bin/nvcc`, **not on PATH** |
| cuDNN | 8.6.0.166 |
| TensorRT | 8.5.2.2 |
| Tools present (not executed) | tegrastats, jtop, jetson_clocks, Docker |

## Python

| Item | Observed |
|---|---|
| Default `python3` | 3.8.10 (ABI `cp38`) |
| Additional interpreter | Python 3.9.5 |
| pip (system) | 20.0.2 |
| NumPy (system) | 1.17.4 |
| PyTorch | **not importable** under the default Python |
| torchvision | **not importable** under the default Python |
| PyTorch CUDA functionality | **not tested** (no PyTorch installed) |

## Storage

| Filesystem | Capacity | Used | Available | Use |
|---|---|---|---|---|
| Root (internal eMMC) | 28 GiB | 22 GiB | 4.5 GiB | 83% |
| `/data` (existing 500 GB NVMe SSD, ext4) | 458 GiB | 72 GiB | 363 GiB | 17% |

## Workspace (owner-reported, created manually after the inventory)

- `/data/bowelnca/` created by the owner with the device administrator's grant. It is owned by the project account with mode 700, and has the subdirectories `workspace, venvs, datasets, derived, checkpoints, experiments, reports, cache, tmp`.
- `/data` itself keeps the device owner's ownership and permissions (unchanged).
- Write test and final mount/ownership verification: **pending** (`scripts/verify_workspace.sh --write-test`).
- MRI data transferred: **none**.

## Observations that do not authorize changes

- The SSH client reported that no post-quantum key exchange was negotiated. Authentication works. No change is proposed in Stage 0.
- The root filesystem has only 4.5 GiB free. All research installs, caches and temp files must go to `/data/bowelnca`.
