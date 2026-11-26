# Security and publication policy

This repository is **public**. Treat everything pushed to GitHub (commits, commit messages, branches, pull requests, comments, issues, Actions logs, artifacts and releases) as immediately and permanently exposed. Deleting a file in a later commit does not remove it from history.

## Never publish

- Passwords, API keys, tokens, cookies or other credentials; `.env` files with secrets.
- SSH private or public keys, fingerprints, `authorized_keys` contents.
- VPN or Tailscale addresses, keys or configuration; private hostnames; network configuration.
- Real device account names, personal home paths, or connection commands that contain private identifiers.
- Private AI-assistant links (project, session, artifact, chat or share pages) or session trailers in commits.
- Remote-access tool identifiers or private infrastructure configuration.
- Private e-mail correspondence, personal contact details, internal approval communications.
- Raw terminal output, system logs, unredacted diagnostics.
- MRI volumes, masks, patient identifiers, medical metadata, locked-test identifiers, private split manifests, restricted dataset hashes.
- Model weights, checkpoints, unpublished results or upstream-derived code without explicit publication approval.

Public examples use placeholders such as `<admin-account>`, `<research-account>` and `<device>`. Credentials live only in operating-system credential stores or a secret manager, never in this repository.

## Automated checks (defence in depth, not access control)

| Check | Where | What it does |
|---|---|---|
| `scripts/check_repo_policy.sh` | CI `policy` (`--tree HEAD`) and `secret-scan` (every commit in the change), pre-commit (`--index`), pre-push (every new commit, `--tree`) | Reads the exact content Git publishes (the staged index or a commit's tree, never the working tree). Restricted paths and file types, secret-like content, evidence redaction headers, the **publication allowlist** of paths and types, symlinks, submodules and unusual file names, binary or control-character content in text files, images that do not match their extension or lack a recorded human approval, private AI-assistant links and session trailers, and **private identifiers** from a local pattern file (below). Prints only the rule and a safe reference; a path that matches a private pattern or uses unusual characters is withheld and the Git object is named instead |
| `scripts/check_commit_messages.sh` | CI `secret-scan`, commit-msg, pre-push | The same link, trailer, secret and private-identifier rules on commit (and pushed tag) messages, and author/committer e-mail must be a no-reply address |
| gitleaks 8.21.2 (`.gitleaks.toml`, default rules plus project rules) | CI `secret-scan`, pre-commit, pre-push | Secret scanning of history and tree with `--redact`. CI downloads the pinned release and verifies its SHA-256. No scan report or artifact is uploaded |

Shared rules and the pattern-file loader live in `scripts/lib/publication_checks.sh`. Every check fails closed: a Git command, object read, pattern file or scanner that fails is an error (exit 3), never a pass. GitHub Actions are pinned to full commit SHAs.

The **pre-push** hook validates every commit that the destination does not already have, for every pushed ref (not only the checked-out branch). "Already has" is taken from the destination's own ref list (`git ls-remote`), not from remote-tracking refs of other remotes. It refuses to push when that list cannot be read, from a shallow clone, or when gitleaks or the private pattern file is missing or invalid. Content that is added and removed again inside the pushed commits is still caught.

**Images** (`docs/figures/`, `docs/img/`) need a human publication approval recorded in `docs/figures/PUBLICATION_APPROVALS.md`, one line per image, keyed by the SHA-256 of its exact content: `<sha256>  <path>  APPROVED-BY-HUMAN: <initials> <YYYY-MM-DD>`. Changing the image invalidates the approval. Device evidence keeps its `REDACTED-BY-HUMAN` attestation.

Tests: `tests/test_repo_policy.sh` and `tests/test_commit_messages.sh` (synthetic fixtures only; the hooks are exercised with a stub scanner).

### What these checks cannot guarantee

Local hooks and hosted CI are **defence in depth, not pre-publication access controls**:
- Hooks run only in clones where they are installed and can be bypassed (`--no-verify`, another clone, the GitHub web editor or API).
- Hosted CI runs **after** a push: a pushed branch, its commits and its pull request are already public even when CI then fails.
- Pattern-based checks find known shapes of secrets and identifiers, not every sensitive value. Hosted CI never has the private pattern file.
- Human review of every change before it is pushed remains required. The real access controls are SSH permissions, dataset ACLs and separate storage.

Scan output stays redacted. If a scan finds something, do not paste the finding into an issue, PR or comment; follow the incident procedure below.

## Local setup (every environment that can push)

1. Install gitleaks 8.21.2 from its official GitHub release and verify the archive against the release's `gitleaks_8.21.2_checksums.txt` (the Linux x64 SHA-256 is pinned in `.github/workflows/research-contract.yml`). Put it on `PATH`, or set `BOWELNCA_GITLEAKS` to its path.
2. Create the private pattern file **outside the repository**, readable only by you:
   ```bash
   install -d -m 700 "${XDG_CONFIG_HOME:-$HOME/.config}/bowelnca"
   install -m 600 /dev/null "${XDG_CONFIG_HOME:-$HOME/.config}/bowelnca/private-patterns.txt"
   ```
   Add one extended regular expression per line (`#` starts a comment), for example the real device account names, hostnames and VPN address ranges. Never commit this file or copy its values into the repository. `BOWELNCA_PRIVATE_PATTERNS` can point to another location outside the clone. The checkers refuse (and therefore block publication) when the file is inside the repository, is not a regular file owned by you, is readable or writable by group or others, cannot be read, contains an invalid expression or one that matches empty text, or (where required) contains no patterns. Patterns are only ever reported by number.
3. Use bash 4 or newer (macOS ships bash 3.2; install a current bash). The checks refuse to run on older versions.
4. Install the hooks: `bash scripts/install_git_hooks.sh` (sets `core.hooksPath=scripts/hooks`). The hooks **fail closed** when gitleaks or the private pattern file is missing.

Hosted CI never has the private pattern file, so private-identifier checks run only locally. That is why the pre-push hook is required before publishing.

## Repository settings (owner)

- **Secret scanning and push protection:** Settings → Code security → enable secret scanning and push protection.
- **Actions:** Settings → Actions → General → workflow permissions **read repository contents** (read-only by default); require approval for workflows from outside contributors. Workflows declare `permissions: contents: read`.
- **Never** register the Xavier, an HPC node or any machine with private access as a self-hosted runner for this public repository.
- **Ruleset for `main`:** require a pull request before merging; require the status checks `policy` and `secret-scan` to pass; block force pushes and deletions; allow squash merging only. With a single maintainer, required approvals stay at 0 or a second reviewer is added.
- **Commit identity:** use the GitHub no-reply address (Settings → Emails → keep my e-mail address private, and block command-line pushes that expose it).

## Agent-prepared changes

AI agents commit with a no-reply identity, never add session or project links, and never merge their own pull requests. Where the agent tooling cannot guarantee that a pull request description stays free of private links, the change is staged privately and a human opens the pull request with a sanitized description.

## Incident procedure

1. Stop the affected publication or merge.
2. Tell the project owner privately, **without reproducing the exposed value**.
3. Revoke or rotate any exposed credential.
4. Assess the exposure, including Git history, pull request references and Actions logs.
5. Propose remediation; destructive history changes need the owner's explicit approval.
6. Verify the remediation. GitHub caches and pull request references may keep old commits, so erasure is never guaranteed.
