#!/usr/bin/env bash
# Install the repository's git hooks (commit-msg, pre-commit, pre-push) for
# this clone by pointing core.hooksPath at scripts/hooks. Run once per clone,
# in every development environment that can push.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
git -C "$root" config core.hooksPath scripts/hooks
echo "hooks installed: core.hooksPath=scripts/hooks"
command -v "${BOWELNCA_GITLEAKS:-gitleaks}" >/dev/null 2>&1 \
  || echo "warning: gitleaks not found; the hooks will refuse to commit or push until it is installed (see SECURITY.md)" >&2
p="${BOWELNCA_PRIVATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/bowelnca/private-patterns.txt}"
[ -f "$p" ] || echo "warning: no private pattern file at the configured location; the hooks will refuse until it exists (see SECURITY.md)" >&2
