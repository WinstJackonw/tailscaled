#!/system/bin/sh
# Run as root on Android after installing the module. Does not stop the real daemon.
set -eu
test_dir=$(mktemp -d /data/local/tmp/tailscale-service.XXXXXX)
case "$test_dir" in /data/local/tmp/tailscale-service.*) ;; *) exit 1 ;; esac
trap 'kill "$unrelated" 2>/dev/null || true; rm -rf "$test_dir"' EXIT
unrelated=
mkdir -p "$test_dir/scripts" "$test_dir/run"
cp /data/adb/tailscale/scripts/tailscaled.service "$test_dir/scripts/"
sed "s|tailscale_dir=\"/data/adb/tailscale\"|tailscale_dir=\"$test_dir\"|; s|module_dir=\"/data/adb/modules/tailscaled\"|module_dir=\"$test_dir/module\"|" \
  /data/adb/tailscale/settings.ini > "$test_dir/settings.ini"
svc="$test_dir/scripts/tailscaled.service"

if "$svc" start > "$test_dir/start.log" 2>&1; then
  echo 'FAIL: missing executable reported ready'; exit 1
fi
test ! -e "$test_dir/run/tailscaled.pid"
test ! -e "$test_dir/run/service.lock"
echo 'PASS: failed startup returns failure and clears PID/lock'

sleep 120 &
unrelated=$!
echo "$unrelated" > "$test_dir/run/tailscaled.pid"
if "$svc" status; then
  echo 'FAIL: unrelated PID reported as daemon'; exit 1
fi
"$svc" stop
kill -0 "$unrelated"
test ! -e "$test_dir/run/tailscaled.pid"
echo 'PASS: stale PID does not kill unrelated process'

mkdir "$test_dir/run/service.lock"
echo $$ > "$test_dir/run/service.lock/pid"
if "$svc" start; then
  echo 'FAIL: concurrent operation ignored lock'; exit 1
fi
kill -0 "$unrelated"
echo 'PASS: concurrent service operation is rejected'
