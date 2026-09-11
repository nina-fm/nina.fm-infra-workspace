Perform a thorough code review of the current changes.

$ARGUMENTS

If $ARGUMENTS contains a PR number (e.g., `42`), fetch the PR diff with `gh pr diff` and post the review as a PR comment at the end.

---

### Step 1 — Gather the diff

```bash
BASE=${BASE:-main}
git diff $BASE...HEAD
git diff $BASE...HEAD --stat
git log $BASE..HEAD --oneline
```

If $ARGUMENTS specifies a PR number, use `gh pr view <number> --json title,body,files` for context and the list of changed files, and `gh pr diff <number>` for the diff.

---

### Step 2 — Review each changed file

Go through each changed file systematically. Apply the relevant checks below based on file type.

Each infra repo documents its own conventions in its README (e.g. nina.fm-backup: comments in French without accents, explaining the why and past incidents). Read it before reviewing.

#### Shell scripts (`*.sh`)
- [ ] `set -euo pipefail`, and shellcheck clean at `--severity=style` (CI runs it)
- [ ] Variables quoted; function variables declared `local`
- [ ] No `|| true` / `2>/dev/null` hiding a real failure — only where the failure is expected and explained
- [ ] Files read by another process written atomically (temp file in the same directory + `mv`), with the right mode for the reader
- [ ] Scripts run by cron: `flock` so runs don't pile up, silent on success, errors to stderr (→ journald → Loki)
- [ ] Nothing accumulates (temp files, logs, caches): bounded or cleaned up
- [ ] Idempotent: running it twice changes nothing the second time

#### System configuration (nina.fm-backup: `system/`, `bootstrap.sh`)
- [ ] Never overwrites a dpkg conffile — use the `.d/` directory or a drop-in instead
- [ ] Validated **before** being installed (`logrotate --debug`, `alloy validate`, `visudo -c`, …) — nothing half-installed
- [ ] "Applied, not just installed": the daemon is checked against the real state (`needs_apply`, config hash), not "did this deploy change a file?"
- [ ] A failure ends the deploy in explicit red, never silently
- [ ] No one-shot script left in the repo once executed
- [ ] `sudoers.d` rules and the workflow commands stay identical to the character

#### Docker / compose (broadcast, webserver)
- [ ] Image versions pinned; restart policy and healthcheck where relevant
- [ ] Memory limit set and justified (the droplet has 2 GB of RAM and swaps — check the `nina-memory` dashboard)
- [ ] No local `logging:` block without a reason: the default comes from `/etc/docker/daemon.json` (nina.fm-backup)
- [ ] Secrets come from the environment or GitHub Secrets, never committed

#### nginx (webserver)
- [ ] `nginx -t` passes; new server blocks reuse `ssl-common/` and the wildcard certificate
- [ ] Upstream port matches the service it proxies

#### GitHub Actions workflows
- [ ] Secrets passed through `env:` and stdin, never as command-line arguments (visible in `/proc`) nor inlined as `${{ }}` in `run:`
- [ ] Actions pinned to a version that runs on Node 24 (see nina-fm/nina.fm-infra-workspace#1)
- [ ] `paths:` triggers match the files the workflow actually deploys
- [ ] A final verification step proves the result on the server

#### Deployment impact
- [ ] Does it restart something that cuts the stream (Docker, icecast, liquidsoap, playout)? If so, it must be explicit and scheduled — never part of an ordinary deploy
- [ ] Rollback path known and written down (README or PR description)
- [ ] Tested where it can be: CI, local run, read-only run on the server, deployment simulation (`.claude/plans/sim-deploiement/`)
- [ ] No secret printed in logs or in the PR

---

### Step 3 — Write the structured review

Format your review output **exactly** as follows:

---

## Code Review

**Branch:** `[branch]` → `main`
**Files changed:** [n] | **Commits:** [n]
**Overall:** ✅ LGTM | ⚠️ Minor issues | ❌ Changes required

### Strengths
- [what is done particularly well]

### Issues

| Severity | File | Issue | Suggestion |
|----------|------|-------|------------|
| 🔴 Critical | `path/to/file` | [issue description] | [how to fix] |
| 🟡 Warning | `path/to/file` | [issue description] | [how to fix] |
| 🔵 Suggestion | `path/to/file` | [improvement idea] | [how to improve] |

_If no issues: "No issues found."_

### Summary
[2–3 sentence overall assessment — quality, risks, readiness to merge]

---

### Step 4 — Post as PR comment (if PR number provided)

If $ARGUMENTS contains a PR number, write the review to a temporary file and post it with `gh pr comment <number> --body-file <file>`.

Report: "Review posted on PR #[number]" with the PR URL.
