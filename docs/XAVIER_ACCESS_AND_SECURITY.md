# Xavier access, security and data-governance assessment

**Status: assessment and PROPOSAL.** No account, group, permission or system change has been made or is authorized by this document. Implementing any change needs the device owner (Dr. Iyad) and is a human administrative task.
**Last updated:** 26 Nov 2026. Network addresses, VPN configuration, hostnames, personal usernames and key material are intentionally omitted (public repository).

## 1. Current state (owner-reported, 26 Nov 2026)

| Control | State |
|---|---|
| Network path | Private mesh VPN, verified, with a direct peer-to-peer connection. No public SSH exposure reported |
| Authentication | OpenSSH with a dedicated ED25519 key, from the project owner's laptop |
| Account | One dedicated project account |
| Privilege | **Password-protected sudo** on that account, granted by the device administrator, for manual administration |
| Workspace | `/data/bowelnca` on the NVMe, owned by the project account, mode 700. `/data` keeps the device owner's ownership |
| Data | No MRI data on the device |
| Agent access | **None.** The cloud agent cannot reach the device. All on-device actions so far were performed by a human |

## 2. Risks in the current state

| # | Risk | Severity | Note |
|---|---|---|---|
| S1 | The research execution account is also a sudoer | **High** before any automation | Any process running as this account (training code, third-party packages, a future remote agent) is one password away from root. A compromised dependency could capture the password through a fake prompt |
| S2 | Docker is installed | **High** if the account joins the `docker` group | Docker group membership is root-equivalent and bypasses sudo entirely. Do not grant it |
| S3 | Single SSH key gives full shell access | Medium | Fine for a human. An agent key must be restricted (section 3.3) |
| S4 | Root eMMC at 83% (4.5 GiB free) | Medium (availability) | A filled root filesystem can destabilise the OS. All caches and installs must go to the NVMe |
| S5 | Dataset isolation not yet built | Gate for Stage 2 | No data yet. The structure must exist before any transfer |
| S6 | SSH reports no post-quantum key exchange | Low | Informational. Revisit only with the owner. No change in Stage 0 |

## 3. Proposed separation (for approval before any autonomous agent is enabled)

### 3.1 Two roles, two accounts

| Role | Account | Privilege | Used for |
|---|---|---|---|
| Human administrator | The existing project account (or the owner's own admin account) | Password-protected sudo (**never** `NOPASSWD: ALL`) | Manual, reviewed administration only: approved apt installs, permission setup, data-transfer setup |
| Research execution | A new unprivileged account (name to be chosen privately) | **No sudo**, **not** in `docker`, `sudo`, `adm`, `lxd`, `disk` | Virtualenvs, training, tests, and any future remote agent session |

The execution account gets its own workspace, or a group-shared subtree of `/data/bowelnca`, and its own SSH key.

### 3.2 Supplementary groups

| Group | Needed by the execution account? | Why |
|---|---|---|
| `video` (and `render` if present) | **Likely yes** | Jetson GPU device nodes are typically group-restricted. Verify with a bounded smoke test before granting anything else |
| `docker` | **No** | Root-equivalent (S2) |
| `sudo` / `admin` | **No** | S1 |
| `i2c`, `gpio`, `dialout`, `audio` | No | Not needed for research compute |

`scripts/verify_workspace.sh` reports risky group membership without printing account names.

### 3.3 Remote agent access (future; not requested now)

If an autonomous agent is ever enabled, use the **execution account only**:
- Its SSH key restricted with `restrict` and a forced command or allow-list wrapper, limited to the VPN source range.
- No agent or port forwarding.
- A separate key from the human's.
- Session logging.

The CLAUDE.md principle applies: real controls are OS accounts, ACLs and separate storage. Agent rules and hooks are defence in depth only.

### 3.4 Dataset isolation (required before Stage 2 data transfer)

- **Locked test cohort (52 cases) and all alternate annotations: never on the Xavier.** This is enforced by the data steward's transfer manifest, not by permissions on the device.
- `/data/bowelnca/datasets/`:
  - holds only the approved 50 development cases;
  - is written by the administrator role from the steward's manifest, with checksums;
  - is read-only to the execution account (owned by the admin role, group-readable, not writable).
- `/data/bowelnca/derived/`, `checkpoints/` and `experiments/` are writable by the execution account.
- Before the first transfer, run a verification that confirms:
  - the dataset directory is not writable by the execution account;
  - the file list equals the approved manifest;
  - no other copies exist on the device.

### 3.5 Root filesystem protection

- Installs and caches stay under `/data/bowelnca` (enforced by the installer: TMPDIR, PIP_CACHE_DIR, XDG_CACHE_HOME, TORCH_HOME and others).
- No `pip install --user` and no system pip.
- The verifier warns when caches appear under HOME.
- No Docker images are pulled for this project unless separately approved; Docker's data root is on the eMMC by default.

## 4. Publication boundary (unchanged, restated)

Never commit or post:
- VPN addresses or configuration, hostnames, personal usernames;
- SSH keys, fingerprints or credentials;
- unredacted device logs;
- private correspondence;
- patient data or locked-test identifiers.

The repository policy check scans `reports/evidence*/` for private and VPN IPv4 ranges, `*.ts.net` names, private IPv6, MAC addresses, emails, home paths, block-device paths and SSH key material. It is a safety net, not a substitute for human redaction.

## 5. Decisions requested

1. Approve the two-account separation (3.1) before any automated or remote-agent execution.
2. Confirm that the execution account will not be added to `docker` or `sudo`, and that `NOPASSWD` sudo is not configured for any project account.
3. Approve the dataset-isolation layout (3.4) as a Stage 2 precondition.
