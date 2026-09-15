# Magisk Tailscaled

This repository contains a Magisk and KernelSU module for running Tailscale on rooted Android devices.

## Prerequisites
- Magisk or KernelSU

## Quick Start & Installation

1. Download the latest zip file from the [Releases](https://github.com/mgksu/tailscaled/releases/latest) page.
2. Install the downloaded zip file using Magisk & reboot your phone.
3. Open the Terminal.
4. Run `tailscale up --ssh --accept-dns=false` to initiate login.You can skip ssh if you don't need it.
5. Run 'tailscale ip' to retrieve your Tailscale IP.

After installation, the Tailscale daemon (`tailscaled`) will run automatically on boot.

## Limitation

- This module only support `arm64` architecture.

## Tailscale SSH 
- For ssh home directory is created at `/data/ssh/root` with Bourne shell (sh) as default shell.
- If you want to change to zsh or any other shell create a file `/data/ssh/root/.profile` with below content assuming you have installed zsh through termux.
```
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
export SHELL="zsh"
exec zsh
```

## Available command

- `tailscale`: This command  execute tailscale operation.
- `tailscaled`: This command execute tailscaled daemon operation.
- `tailscaled.service`: This command for manage tailscaled service, you can start,stop,restart daemon and view live logs the tailscaled operation.

### Cannot access other tailnet devices

1. Verify that `tailscaled.service` is running. If not, restart it with `tailscaled.service restart`.
2. Check if your device is connected to tailscaled and try a ping connection with `tailscale ping <your_tailnet_ip>`.
3. Verify the port you want to access is accessible. You can do this by accessing it with another tailscale device or using the Tailscale Android App.

### Other Error & Bugs

You can explore to the issue tab, if there not exists, you can open issue, for help me resolve the problem, you can include fresh log.

1. Restart tailscaled with `tailscaled.service restart`
2. Reproduce what are you doing which has problem.
3. Get log at `tailscaled.service log`

## Notes

This module is confirmed to be supported for KernelSU

## Building from source (fork)

- `./build.sh` builds the module ZIP from the upstream Tailscale tag pinned in
  `TAILSCALE_VERSION`, applies `android.ssh.patch`, and prints the SHA-256 of
  the resulting ZIP. Requires Go; optionally set `ANDROID_NDK_HOME` for a
  CGO build (otherwise a static `CGO_ENABLED=0` build is produced).
- CI (`.github/workflows/build.yml`) builds on `v*-module.*` tag pushes and on
  `workflow_dispatch`, attaching the ZIP to a GitHub Release.
- **This is an unofficial fork/module packaging of Tailscale** — releases are
  versioned `<upstream>-module.<n>` (e.g. `v1.102.4-module.1`) and contain
  Android-specific patches. arm64 (aarch64) only.
- If you fork this repository, the CI stamps `module.prop`/`update.json` URLs
  from the repository it runs in; update the committed `updateJson`/
  `zipUrl` hosts if you also want in-app update checks on your fork.

## Credits

- [ANASFANANI & AUTHORS](https://github.com/anasfanani/Magisk-Tailscaled). for the repo structure.
