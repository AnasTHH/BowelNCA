# Xavier access, security and data-governance assessment

**Status: assessment and PROPOSAL.** No account, group, permission or system change has been made or is authorized by this document. Every step below is a manual task for the device administrator, after Dr. Iyad's recorded approval (D21).
**Last updated:** 26 Nov 2026 (round 3 revision). Network addresses, VPN configuration, hostnames, account names and key material are intentionally omitted (public repository). The proposed account names are held in the project's private notes; this document uses `<admin-account>`, `<research-account>` and `<research-group>`.

## 1. Current state (owner-reported, 26 Nov 2026)

| Control | State |
|---|---|
| Network path | Private mesh VPN, verified, with a direct peer-to-peer connection. No public SSH exposure reported |
| Authentication | OpenSSH with a dedicated ED25519 key, from the project owner's laptop |
| Account | One dedicated project account (the existing SSH research identity, `<research-account>`) |
| Privilege | **Password-protected sudo** on that account, granted by the device administrator, for manual administration |
| Workspace | `/data/bowelnca` on the NVMe, owned by the project account, mode 700 (the "interim" layout). `/data` keeps the device owner's ownership |
| Data | No MRI data on the device |
| Agent access | **None.** The cloud agent cannot reach the device. All on-device actions so far were performed by a human |

## 2. Risks in the current state

| # | Risk | Severity | Note |
|---|---|---|---|
| S1 | The research execution account is also a sudoer | **High** before any installation or automation | Any process running as this account (installer, training code, third-party packages, a future agent) is one password away from root. A compromised dependency could capture the password through a fake prompt |
| S2 | Docker is installed | **High** if a project account joins `docker` | Docker group membership is root-equivalent and bypasses sudo entirely. Do not grant it |
| S3 | Single SSH key gives full shell access | Medium | Fine for a human. Any agent key must be restricted (section 5) |
| S4 | Root eMMC at 83% (4.5 GiB free) | Medium (availability) | All caches and installs go to the NVMe |
| S5 | Dataset isolation not yet built | Gate for Stage 2 | In the interim layout `datasets/` is research-writable |
| S6 | SSH reports no post-quantum key exchange | Low | Informational. No change proposed |

## 3. Proposed separation (D21)

### 3.1 Two accounts, two roles

| Account | Role | Privilege | Used for |
|---|---|---|---|
| `<admin-account>` (new) | Human administration only | Password-protected sudo. **Never `NOPASSWD`** | Approved package installs, permission setup, dataset transfers from the steward's manifest |
| `<research-account>` (existing SSH research identity) | Research execution | **No sudo.** Not in `docker`, `sudo`, `admin`, `wheel`, `lxd`, `libvirt` or `disk` | Virtualenvs, the installer, training, tests and any future remote agent session |

- Each account has its own ED25519 key. The admin key is never used for research sessions.
- `<research-account>` keeps `video` (and `render` if present) only if the GPU smoke test shows it is needed for CUDA device access.
- The installer (`scripts/proposed/install_xavier_env.sh`) **refuses to run** unless the separated layout is in place and the running account is in no privileged group. So D21 is a prerequisite for the environment installation.

### 3.2 Directory layout (target)

| Path | Owner : group | Mode | Research account can |
|---|---|---|---|
| `/data` | device owner (unchanged) | unchanged | traverse (unchanged) |
| `/data/bowelnca` | `<admin-account>` : `<research-group>` | `0750` | traverse and list; **cannot** create, rename or delete top-level entries |
| `/data/bowelnca/datasets` | `<admin-account>` : `<research-group>` | `0750` (files `0640`) | read only |
| `workspace venvs derived checkpoints experiments reports cache tmp` | `<research-account>` : `<research-group>` | `0700` | read and write |

`<research-group>` is the research account's own primary group, so no other account gains access. Nothing is world-accessible. `scripts/verify_workspace.sh --layout separated` checks exactly this table, plus the mount, filesystem type, nested mounts, symlinks and group membership.

### 3.3 Migration procedure (proposed; run by the administrator; not executed)

Principle: **current access is preserved until the new administrator account is independently verified**, and every phase has a stop condition and a rollback. Keep one already-authenticated session open as `<research-account>` (which still has sudo) for the whole procedure, and make sure console access or the device owner's own admin account is available as a fallback.

**Phase 0. Record the starting state (read-only).**
```bash
id -nG                                   # as <research-account>; keep the output privately
stat -c '%U:%G %a %n' /data /data/bowelnca /data/bowelnca/*
bash scripts/verify_workspace.sh --layout interim
```

**Phase 1. Create the administrator account** (from the open `<research-account>` session).
```bash
sudo adduser <admin-account>                       # sets a strong password interactively
sudo usermod -aG sudo <admin-account>
sudo install -d -m 700 -o <admin-account> -g <admin-account> /home/<admin-account>/.ssh
sudo install -m 600 -o <admin-account> -g <admin-account> admin_ed25519.pub /home/<admin-account>/.ssh/authorized_keys
```
Do not add any `NOPASSWD` rule. Do not add the account to `docker`.

**Phase 2. Verify the administrator independently.** From a **new** terminal on the laptop, with the admin key:
```bash
ssh <admin-account>@<device>        # must log in with the new key
id -nG                              # must include sudo
sudo -k && sudo -v                  # must prompt for the password and succeed
sudo -l                             # must show no NOPASSWD entries
```
**Stop condition:** if any of these fails, stop here. Nothing about `<research-account>` has changed. Fix the admin account, or remove it with `sudo deluser --remove-home <admin-account>`.

**Phase 3. Re-own the parent and datasets** (as `<admin-account>`; `/data` is not touched).
```bash
sudo chown <admin-account>:<research-group> /data/bowelnca
sudo chmod 0750 /data/bowelnca
sudo chown -R <admin-account>:<research-group> /data/bowelnca/datasets
sudo chmod 0750 /data/bowelnca/datasets
sudo find /data/bowelnca/datasets -type f -exec chmod 0640 {} +
stat -c '%U:%G %a %n' /data /data/bowelnca /data/bowelnca/*   # /data unchanged; others as in 3.2
```

**Phase 4. Remove privileges from the research account** (as `<admin-account>`, while the original session stays open).
```bash
sudo gpasswd -d <research-account> sudo
for g in admin wheel docker lxd libvirt disk; do id -nG <research-account> | grep -qw "$g" && sudo gpasswd -d <research-account> "$g"; done
sudo grep -rn '<research-account>' /etc/sudoers /etc/sudoers.d/ || echo "no sudoers entries"
```
Group changes apply to **new** sessions. Remove any sudoers entry found only after reviewing it.

**Phase 5. Verify the research account** (new session as `<research-account>`, with its own key).
```bash
id -nG                                                   # must show no privileged group
bash scripts/verify_workspace.sh --layout separated      # must report 0 FAIL
bash scripts/verify_workspace.sh --layout separated --write-test
```
Then close the original privileged session.

**Rollback** (as `<admin-account>`):
```bash
sudo usermod -aG sudo <research-account>
sudo chown -R <research-account>:<research-group> /data/bowelnca && sudo chmod 0700 /data/bowelnca
```
Review each command before running it. No step touches `/data`, the kernel, JetPack, Docker, power modes or SSH server configuration.

### 3.4 Supplementary groups

| Group | Research account? | Why |
|---|---|---|
| `video` (and `render` if present) | **Only if needed** | Jetson GPU device nodes may be group-restricted. The smoke test shows whether access works |
| `docker` | **No** | Root-equivalent (S2) |
| `sudo`, `admin`, `wheel` | **No** | S1 |
| `lxd`, `libvirt`, `disk` | **No** | Root-equivalent or raw-device access |
| `i2c`, `gpio`, `dialout`, `audio` | No | Not needed for research compute |

## 4. Dataset isolation (required before Stage 2 data transfer)

- **Locked test cohort (52 cases) and all alternate annotations: never on the Xavier.** Enforced by the data steward's transfer manifest, not by device permissions.
- `/data/bowelnca/datasets/` holds only the approved 50 development cases, written by `<admin-account>` from the steward's manifest with checksums, read-only to `<research-account>` (section 3.2).
- `derived/`, `checkpoints/` and `experiments/` are research-writable.
- Before the first transfer, verify: `verify_workspace.sh --layout separated` passes (datasets not research-writable); the file list equals the approved manifest; no other copies exist on the device.

## 5. Remote agent access (future; not requested)

If an autonomous agent is ever enabled, it uses `<research-account>` only, after D21:
- a separate SSH key restricted with `restrict`, a forced command or allow-list wrapper, limited to the VPN source range;
- no agent or port forwarding;
- session logging.

Real controls are OS accounts, ACLs and separate storage. Agent rules and hooks are defence in depth only.

## 6. Approval references are not access controls

The installer's approval references (`BOWELNCA_CORE_APPROVAL`, `BOWELNCA_SCI_APPROVAL`) and `BOWELNCA_REVIEWED_COMMIT` are **guards against accidental execution**. They are not authentication or authorization: anyone who can run the script can type them. Before each run, a human confirms that the reference exists in `docs/DECISIONS.md`, that it approves that stage, and that the checkout is the exact reviewed commit. The script itself only checks the format, that `HEAD` equals the stated commit, and that the checkout is clean.

## 7. Publication boundary

Never commit or post:
- VPN addresses or configuration, hostnames, account names;
- SSH keys, fingerprints or credentials;
- unredacted device logs, or **unapproved evidence drafts** (a folder in a public repository is not private);
- private correspondence;
- patient data or locked-test identifiers.

The repository policy check rejects any `evidence-draft` path or file marked `PENDING-HUMAN-APPROVAL`, and scans approved evidence in `reports/evidence/` for private and VPN IPv4 ranges, `*.ts.net` names, private IPv6, MAC addresses, emails, home paths, block-device paths and SSH key material. It is a safety net, not a substitute for human redaction.

## 8. Decisions requested

1. Approve the two-account separation and layout (D21, sections 3.1 and 3.2) and the migration procedure (3.3), executed manually by the administrator.
2. Confirm that no project account is added to `docker` or `sudo` beyond `<admin-account>`'s `sudo`, and that `NOPASSWD` is not configured.
3. Approve the dataset-isolation layout (section 4) as a Stage 2 precondition.
