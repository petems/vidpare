# Self-Hosted GitHub Actions Runner Hardening (Public Repo)

This repository is public. GitHub's guidance for public repos is explicit: untrusted pull request code must not run on persistent self-hosted runners.

## Current baseline in this repo

- Workflows now default to least-privilege token access (`permissions: contents: read`) where possible.
- All actions in active workflows are pinned to immutable commit SHAs.
- `actions/checkout` now uses `persist-credentials: false` in all workflows.
- CI/release jobs now have explicit timeouts to reduce runner abuse blast radius.
- Codecov upload now runs only on `push` events.

## Required GitHub settings changes (UI)

1. Set `Settings -> Actions -> General -> Workflow permissions` to `Read repository contents permission`.
2. Set `Settings -> Actions -> General -> Fork pull request workflows from outside collaborators` to require approval for all external collaborators before workflow runs.
3. Restrict Actions usage to trusted sources and require pinned SHAs where available (`Allow OWNER, and select non-OWNER, actions and reusable workflows` + SHA pinning policy).
4. Put self-hosted runners in a dedicated runner group limited to this repository only.
5. Configure the runner group to allow only trusted workflows (for example `release.yml`, and optionally a dedicated trusted push workflow).

## Required runner architecture changes

1. Use ephemeral self-hosted runners (`--ephemeral`) or just-in-time runners so each job gets a fresh machine.
2. Do not attach persistent secrets, signing keys, or long-lived cloud credentials directly to runner hosts.
3. Prefer short-lived cloud credentials via OIDC (`id-token: write`) only in jobs that need deployment access.
4. Isolate runner networking and filesystem access so a compromised job cannot laterally move.

## Workflow design rules for this repo

1. Keep `pull_request` workflows on GitHub-hosted runners.
2. Use self-hosted runners only for trusted events (`push` to protected branches/tags, or `workflow_dispatch` by maintainers).
3. Keep release/signing jobs isolated from general CI jobs and guarded by protected branches/tags.
4. Never use `pull_request_target` to run untrusted code from PR heads on self-hosted infrastructure.

## Suggested next repo change (when self-hosted is enabled)

- Add a dedicated workflow (for example `.github/workflows/ci-trusted-self-hosted.yml`) that:
  - triggers only on `push` to `master`/`main` and optionally `workflow_dispatch`
  - runs on a dedicated trusted runner label (for example `[self-hosted, macOS, vidpare-trusted]`)
  - excludes any fork PR trigger
