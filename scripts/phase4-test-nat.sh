#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

test_dir=$(mktemp -d /tmp/nsgw-phase4.XXXXXX)
server_pids=()
capture_pids=()

cleanup() {
  local pid
  for pid in "${server_pids[@]}" "${capture_pids[@]}"; do
    [[ -n $pid ]] || continue
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf -- "$test_dir"
}
trap cleanup EXIT

start_server() {
  local ns=$1
  local port=$2
  ip netns exec "$ns" python3 -m http.server "$port" --bind 0.0.0.0 \
    --directory "$test_dir" >"$test_dir/${ns}-${port}.log" 2>&1 &
  server_pids+=("$!")

  local attempt
  for attempt in {1..30}; do
    if ip netns exec "$ns" ss -H -lnt "sport = :$port" | grep -q .; then
      echo "Listener ready: $ns TCP/$port"
      return 0
    fi
    sleep 0.1
  done

  echo "Listener failed: $ns TCP/$port" >&2
  sed -n '1,120p' "$test_dir/${ns}-${port}.log" >&2
  return 1
}

start_capture() {
  local ns=$1
  local interface=$2
  local output_file=$3
  local filter=$4
  timeout 7 ip netns exec "$ns" tcpdump -e -n -vv -l -i "$interface" "$filter" \
    >"$test_dir/$output_file" 2>&1 &
  capture_pids+=("$!")
}

wait_for_captures() {
  local pid
  for pid in "${capture_pids[@]}"; do
    wait "$pid" || true
  done
  capture_pids=()
}

if ! ip netns exec gateway nft list table ip security_nat &>/dev/null; then
  echo "NAT table is missing. Run phase4-apply-nat.sh first." >&2
  exit 1
fi

start_server attacker 8080
start_server proxy 80

echo
echo "SNAT/MASQUERADE TEST: client 10.10.10.10 -> attacker 10.10.40.10:8080"
syn_filter_8080='tcp port 8080 and (tcp[tcpflags] & tcp-syn != 0)'
start_capture gateway eth-lan snat-eth-lan.txt "$syn_filter_8080"
start_capture gateway eth-wan snat-eth-wan.txt "$syn_filter_8080"
sleep 1
ip netns exec client curl --noproxy '*' -fsS --max-time 3 -o /dev/null \
  http://10.10.40.10:8080/
wait_for_captures

echo
echo "BEFORE SNAT: gateway eth-lan"
sed -n '1,120p' "$test_dir/snat-eth-lan.txt"
echo
echo "AFTER SNAT: gateway eth-wan"
sed -n '1,120p' "$test_dir/snat-eth-wan.txt"
echo
echo "EXTERNAL SERVER ACCESS LOG"
sed -n '1,80p' "$test_dir/attacker-8080.log"

echo
echo "DNAT TEST: attacker -> gateway WAN 10.10.40.1:80 -> proxy 10.10.20.10:80"
syn_filter_80='tcp port 80 and (tcp[tcpflags] & tcp-syn != 0)'
start_capture gateway eth-wan dnat-eth-wan.txt "$syn_filter_80"
start_capture gateway eth-dmz dnat-eth-dmz.txt "$syn_filter_80"
sleep 1
ip netns exec attacker curl --noproxy '*' -fsS --max-time 3 -o /dev/null \
  http://10.10.40.1:80/
wait_for_captures

echo
echo "BEFORE DNAT: gateway eth-wan"
sed -n '1,120p' "$test_dir/dnat-eth-wan.txt"
echo
echo "AFTER DNAT: gateway eth-dmz"
sed -n '1,120p' "$test_dir/dnat-eth-dmz.txt"
echo
echo "DMZ PROXY ACCESS LOG"
sed -n '1,80p' "$test_dir/proxy-80.log"

echo
echo "NAT COUNTERS AFTER BOTH TESTS"
ip netns exec gateway nft list table ip security_nat
