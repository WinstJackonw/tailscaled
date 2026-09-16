# Rooted Android validation

Validated on 2026-09-15/16 with a Q101, Linux 4.19.193 AArch64 kernel,
32-bit ARM Android userspace (`armeabi-v7a,armeabi`, shell `uname -m` reports
`armv8l`), and Magisk 31.0. `/system/bin/linker64` is absent.

## Build

- Final packaged fixes: commit `cf3e05e` on `update/v1.102.4-module.1`.
- [Successful workflow run](https://github.com/WinstJackonw/tailscaled/actions/runs/34989953235).
- Go regression checks cover `util/androidroot`, `util/osuser` and
  `wgengine/router/osrouter`; `paths` is also compiled.
- ELF: 64-bit AArch64, statically linked, no PT_INTERP or dynamic segment.
- ZIP SHA-256:
  `ecec9dfcd7f59f02088051afc3ac9a11ea53862d7fd69557c7903edc00cdf70a`.
- Combined binary SHA-256:
  `92d9b23d512979de9813146c38ed614eda21aace589d60d352282733b58fd4b1`.

## Device results

- Magisk installation executes the payload successfully despite `ARCH=arm`.
- Bare combined CLI and installed wrappers use the same absolute socket.
- Interactive login reaches the control server with valid TLS and enters
  `Running`; login state persists across module upgrades and service restarts.
- DNS lookup succeeds using Android network DNS. The control connection no
  longer needs bootstrap DNS after wiring the caching resolver to it.
- TUN creation and UDP work; DERP netcheck succeeds.
- Tailscale establishes a direct LAN peer connection.
- Both directions of IPv4 and IPv6 ICMP pass, three packets each, zero loss.
- Full device reboot mounts the module commands and starts the daemon
  automatically after boot completion and the configured 20-second delay.
- Repeated start retains the same PID. Three sequential service restarts
  preserve login and addresses, with one table-52 policy rule per IP family.
- Creating/removing the module's `disable` marker stops/restarts the service.
- Repeated boot-script invocation retains one BusyBox inotify watcher.
- Wi-Fi disable/enable recovers connectivity without restarting the daemon.
- The daemon remained running with the same PID for more than eight hours
  before the final package installation; its addresses were unchanged.
- Negative tests reject a missing executable, clear failed-start PID/lock
  files, reject concurrent operations, and do not kill an unrelated process
  referenced by a stale PID file.

## Repeat the tests

After installing, rebooting and completing login, push the scripts with ADB:

```sh
adb push tests/android-smoke.sh /data/local/tmp/android-smoke.sh
adb push tests/android-service-negative.sh /data/local/tmp/android-service-negative.sh
adb shell su -c 'sh /data/local/tmp/android-smoke.sh PEER_IPV4 PEER_IPV6'
adb shell su -c 'sh /data/local/tmp/android-service-negative.sh'
```

Replace the peer address placeholders with an online tailnet peer. The smoke
test restarts the real daemon three times; the negative tests use an isolated
temporary directory. A `Running` backend may take a few seconds after the
LocalAPI becomes reachable. The smoke test waits for this separately.

This verifies the tested device and ordinary tailnet connectivity. Tailscale
SSH sessions, exit-node use/advertising, subnet routing and other Android
versions were not exercised. Android application DNS remains managed by netd;
the module uses `--accept-dns=false` for this validation.
