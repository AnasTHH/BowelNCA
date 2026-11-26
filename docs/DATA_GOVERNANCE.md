# Dataset isolation and integrity policy

## Trust boundary

Only the authorized data steward may read the full acquired 114-file archive before the final-test campaign. Development users and AI coding agents on the Xavier receive *only* the approved 50 development images/masks after the canonical-image audit and split freeze. The 52 locked test cases are never sent to Xavier, including their alternate annotation versions.

## Independent duplicate audit

The 25 Nov v1.1 source document reported 11 duplicate-image groups, 12 excluded file IDs, and 102 unique scans. These are preliminary external observations. Write a reproducible audit using original file digests plus decompressed-array comparison, affine and shape checks, and inspection of possible patient identity. Label disagreement must be reported as *annotation-version variability*. Do not describe it as an independently measured reader-to-reader ceiling.

## Conditional splitting

- Target total: 102 independent eligible cases, **only after verified**.
- Partition: canonical 40 train, 10 development-validation, 52 final test; nested train20/train30/train40.
- Use fixed seed 42 and documented acquisition-spacing stratification; retain exact generation algorithm and IDs.
- Reject any duplicate group, same-patient scans, or slices crossing partitions.
- Store manifest checksum as sidecar `splits.json.sha256` to avoid self-referential hashing.
- The split is version-controlled, frozen and reviewed. Changes require formal amendment.

## Selection set is not an independent validation set

For exploratory n=20 arm ranking only, Selection30 = validation10 plus 20 future training cases. This choice reuses development data; its scores must not support held-out accuracy claims. After design freeze, train20/30/40 are evaluated provisionally on validation10 only, with confirmed conclusions reserved for the locked test campaign.

## Directory and access separation (example)

```text
private_data_steward/
  source_archive/             # original complete dataset; never on Xavier
  canonical_and_duplicates/   # audit only; can include test-linked annotations
  locked_test/                # restricted 52 cases; absent from Xavier
  approved_dev_transfer/      # exactly 50 canonical dev cases with checksums
xavier_dev/
  data/raw_dev/               # only 50 approved dev cases; ignored in Git
  data/derived/               # generated from dev only; ignored
  reports/                    # de-identified logs and quality checks
```

Make sure data identifiers cannot be reverse-mapped to patients without authorization. Public split IDs should follow the dataset's licensing and privacy terms.

## Publication boundary

No raw NIfTI volumes, real patient masks, DICOM IDs, credentials or private storage paths in GitHub Actions logs, code review comments or public issues. Publication of exemplar MRI overlays, derived masks and checkpoints is subject to dataset license/rights review and human approval.

## Public repository consequences

The GitHub repository is **public from day one** (owner decision, 25 Nov 2026; see `DECISIONS.md` D16). Treat every commit, issue, pull request, review comment, Actions log and artifact as world-readable and permanently cached.

- Device evidence (inventory logs) is committed only after redaction of hostnames, usernames, IP/MAC addresses, serial numbers and home-directory paths. Unredacted logs stay local (`*_inventory_local.log` is git-ignored).
- Hosted CI uses GitHub-hosted runners, `permissions: contents: read`, no secrets and synthetic inputs only.
- **Self-hosted runners (Xavier or HPC) must never be attached to workflows that run on `pull_request` events.** On a public repository any fork can open a PR, and a self-hosted runner would execute that untrusted code on the device that holds development data. The plan's optional "GPU smoke via a private runner" (Plan Section 12) therefore needs a design review before it is enabled: for example, `workflow_dispatch` only, an environment with required reviewers, an ephemeral runner, and no data mounts.
- `scripts/check_repo_policy.sh` blocks restricted directories at any depth (data, steward, locked-test, alternate-label, artefact, log and upstream-checkout folders), medical-image, weight, pickle, archive and key file types, log and raw console files, images outside `docs/figures/`, secret-like strings and files over 2 MiB. Committed device evidence must live in `reports/evidence/` and start with `REDACTED-BY-HUMAN: <initials> <YYYY-MM-DD>`. Unapproved drafts are never committed (a folder in a public repository is not private): any `evidence-draft` path or file marked `PENDING-HUMAN-APPROVAL` is rejected. Approved evidence is scanned for private, VPN (CGNAT) and link-local IPv4, `*.ts.net` names, private IPv6, MAC addresses, emails, home paths, block-device paths and SSH key material. It is a safety net for mistakes, not an access control.
