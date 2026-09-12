#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$project_dir/run" "$project_dir/logs/suricata" "$project_dir/logs/sanitized"
bash "$project_dir/scripts/services-down.sh" >/dev/null 2>&1 || true

start_web() {
  local ns=$1 identity=$2 ip=$3 port=$4
  nohup ip netns exec "$ns" python3 "$project_dir/web/server.py" \
    --identity "$identity" --bind 0.0.0.0 --port "$port" \
    >"$project_dir/logs/${ns}.log" 2>&1 &
  echo $! >"$project_dir/run/${ns}.pid"
}

start_web web01 WEB01 10.10.20.21 8080
start_web web02 WEB02 10.10.20.22 8080
start_web client INTERNAL-LAN 10.10.10.10 8080

ip netns exec proxy nginx -t -c "$project_dir/proxy/nginx.conf"
nohup ip netns exec proxy nginx -c "$project_dir/proxy/nginx.conf" -g 'daemon off;' \
  >"$project_dir/logs/nginx-process.log" 2>&1 &
echo $! >"$project_dir/run/nginx-launcher.pid"

for endpoint in 'web01 8080' 'web02 8080' 'client 8080' 'proxy 80'; do
  read -r ns port <<<"$endpoint"
  for attempt in {1..40}; do
    ip netns exec "$ns" ss -H -lnt "sport = :$port" | grep -q . && break
    sleep 0.1
  done
  ip netns exec "$ns" ss -H -lnt "sport = :$port" | grep -q . || {
    echo "Service failed: $ns TCP/$port" >&2; exit 1;
  }
done
echo "Web backends, reverse proxy/load balancer, and internal VPN demo service are ready."
