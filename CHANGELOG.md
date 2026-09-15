## Tailscaled Change Log

### v1.102.4-module.1 (2026-09-15)

Unofficial fork/module release — not an official Tailscale build. arm64 only.

- Update bundled Tailscale from v1.82.5 to **v1.102.4** (latest stable upstream).
- Rebase `android.ssh.patch` onto v1.102.4:
  - Upstream now excludes the Tailscale SSH server from Android builds
    (`//go:build linux && !android` on `ssh/tailssh/*` and `feature/ssh`);
    the patch re-includes it on Android and re-applies the Android-specific
    behavior: allow `tailscaled` + Tailscale SSH on rooted Android, root
    (uid 0) user/group lookup, `/system/bin/sh` login shell, `/data/ssh/root`
    home directory, Android-safe default socket path, daemon environment
    inheritance for SSH sessions.
  - Ported the previous session-launch patch to the new `incubatorEnv()` /
    `handleSSHInProcess` flow introduced upstream.
  - Build with `ts_omit_systray` (upstream omit tag): the desktop systray
    feature cannot compile on Android (`fyne.io/systray` has no Android
    backend) and is unused by this headless module.
- Add `build.sh`: reproducible build that pins the upstream tag
  (`TAILSCALE_VERSION`), applies the patch, builds arm64 with proper
  version metadata, and assembles the module ZIP with SHA-256.
- Rework CI (`.github/workflows/build.yml`): builds on `v*-module.*` tag
  pushes and `workflow_dispatch`, attaches the ZIP to a GitHub Release,
  uses only `GITHUB_TOKEN` with minimal `contents: write` permissions, and
  fails if the patch or compile fails. The weekly auto-build cron and its
  force-push to `main` were removed.
- Versioning scheme: `<upstream>-module.<n>` (e.g. `v1.102.4-module.1`).
  The workflow refuses to build a release tag whose upstream part does not
  match `TAILSCALE_VERSION`.
