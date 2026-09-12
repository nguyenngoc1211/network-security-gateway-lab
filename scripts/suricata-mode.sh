#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
mode=${1:-}
project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pid_file="$project_dir/run/suricata.pid"
log_dir="$project_dir/logs/suricata"
rules="$project_dir/gateway/suricata/local.rules"
mkdir -p "$log_dir" "$project_dir/run"

remove_queue_rule() {
  local handle
  while read -r handle; do
    [[ -n $handle ]] || continue
    ip netns exec gateway nft delete rule inet security_filter forward handle "$handle" || true
  done < <(ip netns exec gateway nft -a list chain inet security_filter forward 2>/dev/null \
    | awk '/Suricata-NFQUEUE/{print $NF}')
}

if [[ -f $pid_file ]]; then
  old_pid=$(<"$pid_file")
  kill "$old_pid" 2>/dev/null || true
  for attempt in {1..30}; do kill -0 "$old_pid" 2>/dev/null || break; sleep 0.1; done
  rm -f "$pid_file"
fi
remove_queue_rule

common=(-D -c /etc/suricata/suricata.yaml -l "$log_dir" -S "$rules"
  --pidfile "$pid_file" --set 'vars.address-groups.HOME_NET=[10.10.10.0/24,10.10.20.0/24,10.10.30.0/24]')

case "$mode" in
  ids) ip netns exec gateway suricata "${common[@]}" -i eth-wan ;;
  ips)
    # Queue is present only while Suricata owns NFQUEUE 0. The baseline
    # firewall must continue enforcing policy when IPS is stopped.
    ip netns exec gateway nft insert rule inet security_filter forward \
      queue num 0 bypass comment '"Suricata-NFQUEUE"'
    ip netns exec gateway suricata "${common[@]}" -q 0 ;;
  stop) echo "Suricata stopped."; exit 0 ;;
  *) echo "Usage: $0 ids|ips|stop" >&2; exit 2 ;;
esac

sleep 3
[[ -s $pid_file ]] && kill -0 "$(<"$pid_file")" 2>/dev/null || {
  remove_queue_rule
  echo "Suricata failed to start; inspect $log_dir/suricata.log" >&2; exit 1;
}
echo "Suricata started in ${mode^^} mode."
