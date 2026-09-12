#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

debug_dir=$(mktemp -d /tmp/nsgw-phase3-debug.XXXXXX)
server_pid=""
capture_pids=()

cleanup() {
  local pid
  if [[ -n $server_pid ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  for pid in "${capture_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf -- "$debug_dir"
}
trap cleanup EXIT

echo "FORWARDING"
ip netns exec gateway sysctl net.ipv4.ip_forward

echo
echo "CLIENT ROUTES AND LOOKUP"
ip -n client route
ip -n client route get 10.10.40.10

echo
echo "GATEWAY ROUTES AND LOOKUPS"
ip -n gateway route
ip -n gateway route get 10.10.40.10
ip -n gateway route get 10.10.10.10

echo
echo "ATTACKER ROUTES"
ip -n attacker route

ip netns exec attacker python3 -m http.server 8080 --bind 0.0.0.0 \
  --directory "$debug_dir" >"$debug_dir/server.log" 2>&1 &
server_pid=$!

for attempt in {1..30}; do
  if ip netns exec attacker ss -H -lnt 'sport = :8080' | grep -q .; then
    break
  fi
  sleep 0.1
done

if ! ip netns exec attacker ss -H -lnt 'sport = :8080' | grep -q .; then
  echo "Attacker listener failed:" >&2
  sed -n '1,120p' "$debug_dir/server.log" >&2
  exit 1
fi

packet_filter='arp or (tcp port 8080 and host 10.10.10.10 and host 10.10.40.10)'

timeout 6 ip netns exec client tcpdump -e -n -l -i eth0 "$packet_filter" \
  >"$debug_dir/client-eth0.txt" 2>&1 &
capture_pids+=("$!")

timeout 6 ip netns exec gateway tcpdump -e -n -l -i eth-lan "$packet_filter" \
  >"$debug_dir/gateway-eth-lan.txt" 2>&1 &
capture_pids+=("$!")

timeout 6 ip netns exec gateway tcpdump -e -n -l -i eth-wan "$packet_filter" \
  >"$debug_dir/gateway-eth-wan.txt" 2>&1 &
capture_pids+=("$!")

sleep 1
echo
echo "CURL RESULT"
ip netns exec client curl --noproxy '*' -v --connect-timeout 2 --max-time 3 \
  http://10.10.40.10:8080/ || true

for capture_pid in "${capture_pids[@]}"; do
  wait "$capture_pid" || true
done

echo
echo "CLIENT eth0 CAPTURE"
sed -n '1,160p' "$debug_dir/client-eth0.txt"

echo
echo "GATEWAY eth-lan CAPTURE"
sed -n '1,160p' "$debug_dir/gateway-eth-lan.txt"

echo
echo "GATEWAY eth-wan CAPTURE"
sed -n '1,160p' "$debug_dir/gateway-eth-wan.txt"

echo
echo "NEIGHBOR TABLES"
echo "client:"
ip -n client neigh
echo "gateway:"
ip -n gateway neigh
echo "attacker:"
ip -n attacker neigh

echo
echo "FORWARD CHAIN COUNTERS"
ip netns exec gateway nft list chain inet security_filter forward
