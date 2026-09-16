#!/system/bin/sh
# Run as root after boot and login. Optional arguments: peer IPv4 and IPv6.
set -eu
. /data/adb/tailscale/settings.ini

wait_running() {
  attempt=0
  while [ "$attempt" -lt 60 ]; do
    if "$tailscale_bin" status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  echo 'FAIL: daemon did not become Running' >&2
  return 1
}

# First wait for boot startup; don't mask a broken boot service by starting it.
wait_running
"$tailscaled_service" status
before=$("$tailscale_bin" ip)
pid_before=$(cat "$tailscaled_pid")
"$tailscaled_service" start
test "$(cat "$tailscaled_pid")" = "$pid_before"
echo 'PASS: repeated start retains the same daemon'

for iteration in 1 2 3; do
  "$tailscaled_service" restart
  wait_running
  test "$("$tailscale_bin" ip)" = "$before"
  test "$(ip rule | grep -c '5270:.*lookup 52')" = 1
  test "$(ip -6 rule | grep -c '5270:.*lookup 52')" = 1
done
echo 'PASS: three restarts retain login/IP and one routing rule per family'

if [ -n "${1:-}" ]; then
  "$tailscale_bin" ping --c=3 "$1"
  ping -c 3 -W 3 "$1"
fi
if [ -n "${2:-}" ]; then
  ping6 -c 3 -W 3 "$2"
fi
echo 'PASS: Android service smoke test'
