#!/system/bin/sh
DIR=${0%/*}
. "$DIR/../settings.ini"

stop_service() {
  if [ -f "${tailscaled_run_dir}/tailscaled.pid" ]; then
    "${tailscaled_service}" stop >> "/dev/null" 2>&1
  fi
}
start_service() {
  if [ ! -f "${module_dir}/disable" ]; then
    "${tailscaled_service}" start >> "/dev/null" 2>&1
  fi
}
start_inotifyd() {
  # With "busybox inotifyd", the process name is busybox on Android.
  for PID in $(busybox pidof busybox inotifyd); do
    if tr '\000' '\n' < "/proc/$PID/cmdline" 2>/dev/null | grep -Fxq "$tailscaled_inotify"; then
      return 0
    fi
  done
  echo "${current_time} [Info]: Starting tailscaled inotify service" >> "${tailscaled_service_log}"
  nohup busybox inotifyd "${tailscaled_inotify}" "${module_dir}" >/dev/null 2>&1 < /dev/null &
}
umask 077
mkdir -p "$tailscaled_run_dir"
chmod 0700 "$tailscaled_run_dir"
module_version=$(busybox awk -F'=' '!/^ *#/ && /version=/ { print $2 }' "$module_prop" 2>/dev/null)
log Info "Magisk Tailscaled version : ${module_version}."
start_service || exit 1
start_inotifyd
