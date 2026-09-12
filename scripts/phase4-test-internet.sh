#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

capture_dir=$(mktemp -d /tmp/nsgw-phase4-internet.XXXXXX)
capture_pids=()

cleanup() {
  local pid
  for pid in "${capture_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf -- "$capture_dir"
}
trap cleanup EXIT

echo "DEFAULT ROUTE"
ip -n gateway route show default

echo
echo "DNS RESOLUTION FROM LAN CLIENT"
echo "Direct DNS query through the gateway:"
ip netns exec client dig @1.1.1.1 example.com A +short +time=3 +tries=1
echo "Resolver configuration visible inside client:"
ip netns exec client cat /etc/resolv.conf
target_ip=$(ip netns exec client getent ahostsv4 example.com 2>/dev/null | awk 'NR == 1 { print $1 }' || true)
if [[ -z $target_ip ]]; then
  echo "DNS resolution failed inside client namespace." >&2
  exit 1
fi
echo "example.com -> $target_ip"

syn_filter="host $target_ip and tcp port 443 and (tcp[tcpflags] & tcp-syn != 0)"

timeout 10 ip netns exec gateway tcpdump -e -n -l -i eth-lan "$syn_filter" \
  >"$capture_dir/eth-lan.txt" 2>&1 &
capture_pids+=("$!")

timeout 10 ip netns exec gateway tcpdump -e -n -l -i eth-uplink "$syn_filter" \
  >"$capture_dir/eth-uplink.txt" 2>&1 &
capture_pids+=("$!")

timeout 10 tcpdump -e -n -l -i eth0 "$syn_filter" \
  >"$capture_dir/wsl-eth0.txt" 2>&1 &
capture_pids+=("$!")

sleep 1
echo
echo "HTTPS REQUEST FROM LAN CLIENT"
ip netns exec client curl --noproxy '*' -fsSI --max-time 8 \
  --resolve "example.com:443:$target_ip" https://example.com/ | sed -n '1,12p'

for capture_pid in "${capture_pids[@]}"; do
  wait "$capture_pid" || true
done
capture_pids=()

echo
echo "BEFORE GATEWAY NAT: gateway eth-lan"
sed -n '1,80p' "$capture_dir/eth-lan.txt"
echo
echo "AFTER GATEWAY NAT: gateway eth-uplink"
sed -n '1,80p' "$capture_dir/eth-uplink.txt"
echo
echo "AFTER DOCKER/WSL UPLINK NAT: WSL eth0"
sed -n '1,80p' "$capture_dir/wsl-eth0.txt"

echo
echo "NAT COUNTERS"
ip netns exec gateway nft list table ip security_nat
